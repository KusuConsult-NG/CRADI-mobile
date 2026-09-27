// TEST HARNESS ONLY — the "is every control wired to something?" pass.
//
// The other passes walk screens and look for crashes. This one does the
// opposite: it enumerates every interactive node Flutter publishes on a
// screen, clicks each one in turn, and records whether ANYTHING observable
// happened — a route change, a new/removed label (dialog, sheet, snackbar,
// toggled state), or a request to the backend.
//
// A control that produces none of those three is reported as `dead`. That is
// a *candidate*, not a verdict: share sheets, TTS and the camera are
// plugin-backed and cannot do anything in a browser, so they are classified
// separately (`plugin`) from the label list below.
import path from 'node:path';
import {
    BASE, Shots, enableSemantics, findNode, goto, nodes,
} from './driver.mjs';

/**
 * Controls whose only effect is outside the page (a platform share sheet,
 * speech synthesis, the camera, a dialler, an external URL). In a browser
 * these legitimately change nothing on screen.
 */
const PLUGIN_BACKED = [
    /share/i, /listen/i, /speak/i, /read aloud/i,
    /call /i, /dial/i, /^sos/i, /emergency call/i,
    /camera/i, /take a photo/i, /gallery/i, /photo/i,
    /download/i, /open in browser/i, /^map$/i, /use my location/i,
];

/**
 * Controls the probe must not press: they end the session or destroy the
 * fixture the rest of the pass walks over.
 */
const DESTRUCTIVE = [
    /log ?out/i, /sign ?out/i, /delete account/i, /^delete$/i, /clear all/i,
    /^remove$/i, /reject/i, /disable/i,
];

/**
 * Controls whose label says they are inert: a cascading dropdown that is
 * disabled until its parent is chosen. Flutter publishes a `DropdownButton`
 * with `onChanged: null` without `aria-disabled`, so the tree cannot be asked.
 */
const INERT_BY_DESIGN = [/select .* first/i];

/**
 * Controls that hand off to an external URL scheme (`tel:`, `sms:`,
 * `mailto:`). `url_launcher` hands those to `window.open`, and Chromium then
 * puts up its native external-protocol prompt, which blocks the renderer:
 * every later control on the pass would read as dead. They are recorded as
 * plugin-backed without being pressed — a browser could not show their effect
 * anyway.
 */
const EXTERNAL_SCHEME = [
    /contact support/i, /^sos/i, /emergency \d/i, /^call /i, /dial/i,
    /send a text message/i, /\bsms\b/i,
];

/** Locale switches rewrite every label, which breaks later label matching. */
const LOCALE_SWITCH = [/hausa/i, /yor[uù]b[aá]/i, /igbo/i, /naij[aá]/i, /pidgin/i];

const matches = (label, list) => list.some((re) => re.test(label));

/** The interactive nodes on screen, de-duplicated by label + role. */
export async function controlsOnScreen(page) {
    const all = await nodes(page);
    const out = [];
    const seen = new Set();
    for (const n of all) {
        const interactive = n.tappable
            || n.input
            || ['button', 'link', 'checkbox', 'switch', 'radio', 'slider', 'tab', 'menuitem'].includes(n.role);
        if (!interactive) continue;
        const label = (n.label || '').trim();
        if (!label && !n.input) continue;
        const key = `${n.role}|${label}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ ...n, label, key });
    }
    return out;
}

async function snapshot(page, net) {
    const all = await nodes(page);
    return {
        pixels: (await page.screenshot()).toString('base64'),
        hash: await page.evaluate(() => location.hash),
        labels: all.map((n) => n.label).filter(Boolean).sort(),
        states: all.map((n) => `${n.label}:${n.checked ?? ''}:${n.selected ?? ''}:${n.value ?? ''}`).sort(),
        requests: net.length,
    };
}

function diff(before, after) {
    const b = new Set(before.labels);
    const a = new Set(after.labels);
    const added = [...a].filter((x) => !b.has(x));
    const removed = [...b].filter((x) => !a.has(x));
    const stateChanged = before.states.join('\u0001') !== after.states.join('\u0001');
    return {
        routeChanged: before.hash !== after.hash,
        added, removed, stateChanged,
        pixelsChanged: before.pixels !== after.pixels,
        requests: after.requests - before.requests,
    };
}

function classify(d) {
    if (d.routeChanged) return 'navigation';
    if (d.added.length || d.removed.length) return 'content-change';
    if (d.stateChanged) return 'state-change';
    if (d.requests > 0) return 'network';
    // Flutter paints to a canvas and does not mirror every widget's state in
    // the semantics tree (a selected report-wizard tile keeps the same
    // aria-* attributes), so the last check is the rendered frame itself.
    if (d.pixelsChanged) return 'visual-change';
    return 'dead';
}

function describe(d) {
    const bits = [];
    if (d.routeChanged) bits.push('route changed');
    if (d.added.length) bits.push(`+${d.added.length} label(s): ${d.added.slice(0, 3).join(' / ').slice(0, 120)}`);
    if (d.removed.length) bits.push(`-${d.removed.length} label(s)`);
    if (d.stateChanged && !d.added.length && !d.removed.length) bits.push('widget state changed');
    if (d.pixelsChanged && !d.routeChanged && !d.added.length && !d.removed.length && !d.stateChanged) {
        bits.push('the rendered frame changed (canvas-only feedback)');
    }
    if (d.requests) bits.push(`${d.requests} backend request(s)`);
    return bits.join('; ') || 'nothing observable';
}

/**
 * Clicks every control on one screen and records what each one did.
 *
 * `restore` is run between probes so a dialog or a pushed route does not
 * leave the next probe on the wrong screen.
 */
export async function probeScreen({ page, shots, net, screen, route, rows, log, max = 40, before, external }) {
    // The navigation Drawer and some bottom sheets are route overlays that
    // neither Escape nor a hash change closes, so a soft restore can leave
    // the next probe behind an overlay. When the control we are about to
    // press is not back in the tree, reload the whole app (the Supabase
    // session lives in localStorage, so the role survives).
    // `url_launcher` opens `mailto:` / `tel:` / news links with
    // `window.open`, which leaves a second page in the context. The Flutter
    // engine in the page we are driving then stops reacting to synthetic
    // pointer events, so every later control on the pass reads as dead.
    const closePopups = async () => {
        for (const other of page.context().pages()) {
            if (other !== page) await other.close().catch(() => {});
        }
        await page.bringToFront().catch(() => {});
    };
    const softRestore = async () => {
        await closePopups();
        for (let i = 0; i < 3; i++) {
            await page.keyboard.press('Escape');
            await page.waitForTimeout(250);
        }
        await goto(page, route, { settle: 2000 });
        if (before) await before(page);
    };
    const hardRestore = async () => {
        await closePopups();
        await page.goto(BASE, { waitUntil: 'load' });
        await page.waitForTimeout(6000);
        await enableSemantics(page);
        await goto(page, route, { settle: 2600 });
        if (before) await before(page);
    };
    const restoreFor = async (key) => {
        await softRestore();
        const back = (await controlsOnScreen(page)).some((n) => n.key === key);
        if (!back) await hardRestore();
    };

    // Start every screen from a fresh load. After a few hundred synthetic
    // clicks and hash navigations the engine in a long-lived headless page
    // starts throwing out of its pointer/semantics pipeline, and from then on
    // every control reads as dead. Reloading per screen keeps each screen's
    // verdict independent of how much came before it.
    await hardRestore();
    const list = (await controlsOnScreen(page)).slice(0, max);
    log(`  ${screen}: ${list.length} control(s)`);

    for (const control of list) {
        const label = control.label || '(unlabelled field)';
        const row = { screen, route, control: label, role: control.role };

        if (matches(label, EXTERNAL_SCHEME)) {
            row.result = 'plugin';
            row.detail = 'hands off to tel: / sms: / mailto: — not pressed (it blocks the browser)';
            rows.push(row);
            continue;
        }
        if (matches(label, DESTRUCTIVE) || matches(label, LOCALE_SWITCH)) {
            row.result = 'skipped';
            row.detail = matches(label, LOCALE_SWITCH)
                ? 'locale switch — rewrites every label, covered by the languages pass'
                : 'destructive / ends the session — not pressed';
            rows.push(row);
            continue;
        }

        // Re-find the node: the tree is rebuilt after every restore.
        let fresh = (await controlsOnScreen(page)).find((n) => n.key === control.key);
        if (!fresh) {
            await restoreFor(control.key);
            fresh = (await controlsOnScreen(page)).find((n) => n.key === control.key);
        }
        if (!fresh) {
            row.result = 'unreachable';
            row.detail = 'control no longer in the semantics tree after restore';
            rows.push(row);
            continue;
        }
        if (fresh.disabled === 'true') {
            row.result = 'disabled';
            row.detail = 'aria-disabled — a deliberate disabled state, not a dead control';
            rows.push(row);
            continue;
        }

        const slug = `${screen}-${label.replace(/[^a-z0-9]+/gi, '-').slice(0, 32) || 'field'}`;
        const shotBefore = await shots.take(page, `${slug}-before`);
        const snapBefore = await snapshot(page, net);
        try {
            if (fresh.input) {
                // Clicking a text field only focuses it. Typing is what the
                // field is for, and a live field re-filters the list under it.
                if (!(await tapControl(page, control.key))) {
                    row.result = 'unreachable';
                    row.detail = 'could not be scrolled into the viewport';
                    rows.push(row);
                    await softRestore();
                    continue;
                }
                await page.waitForTimeout(250);
                await page.keyboard.press('Control+A');
                await page.keyboard.type('flood', { delay: 20 });
            } else if (!(await tapControl(page, control.key))) {
                row.result = 'unreachable';
                row.detail = 'could not be scrolled into the viewport';
                rows.push(row);
                await softRestore();
                continue;
            }
        } catch (e) {
            row.result = 'harness-error';
            row.detail = e.message;
            rows.push(row);
            await softRestore();
            continue;
        }
        await page.waitForTimeout(1400);
        const snapAfter = await snapshot(page, net);
        const d = diff(snapBefore, snapAfter);
        let kind = classify(d);
        if (kind === 'dead' && matches(label, PLUGIN_BACKED)) kind = 'plugin';
        // Opens an external URL in a new tab (url_launcher): nothing changes
        // in the page the harness is driving.
        if (kind === 'dead' && external && external.test(label)) kind = 'external-link';
        if (kind === 'dead' && matches(label, INERT_BY_DESIGN)) kind = 'disabled';
        // Re-picking the chip / tab that is already active is a no-op by
        // design, not a dead control.
        if (kind === 'dead' && fresh.selected === 'true') kind = 'already-selected';
        if (kind === 'dead' && fresh.checked === 'true') kind = 'already-selected';
        row.result = kind;
        row.detail = describe(d);
        if (kind === 'dead' || kind === 'plugin' || kind === 'visual-change') {
            row.shotBefore = path.relative(process.cwd(), shotBefore);
            row.shotAfter = path.relative(process.cwd(), await shots.take(page, `${slug}-after`));
        }
        rows.push(row);
        if (kind === 'dead') log(`    ! DEAD  ${screen} :: ${label}`);
        await softRestore();
    }
}

/** Records every request the app makes to the mock backend. */
export function trackNetwork(page, mockOrigin) {
    const net = [];
    page.on('request', (r) => {
        if (r.url().startsWith(mockOrigin)) net.push(`${r.method()} ${r.url()}`);
    });
    return net;
}

/**
 * Clicks a control identified by its `key`, re-reading its rect after every
 * scroll. Flutter keeps a widget below the fold in the semantics tree with a
 * rect outside the viewport, so scrolling once and clicking the viewport
 * centre lands on whatever happens to be drawn there — usually a different
 * tile. Re-querying after each wheel makes the click land on the real target.
 */
async function tapControl(page, key) {
    const view = page.viewportSize();
    for (let attempt = 0; attempt < 10; attempt++) {
        const n = (await controlsOnScreen(page)).find((x) => x.key === key);
        if (!n) return false;
        const cx = n.x + n.w / 2;
        const cy = n.y + n.h / 2;
        const inX = cx > 8 && cx < view.width - 8;
        const inY = cy > 8 && cy < view.height - 8;
        if (inX && inY) {
            await page.mouse.click(cx, cy);
            return true;
        }
        if (!inY) {
            // Vertical scroller: move the pointer to the middle of the page.
            await page.mouse.move(view.width / 2, view.height / 2);
            await page.mouse.wheel(0, Math.round(cy - view.height / 2));
        } else {
            // Horizontal scroller (a chip row, a scrollable TabBar). The wheel
            // must be over the row itself, and clamping x instead would click
            // whichever chip happens to sit at the viewport edge.
            await page.mouse.move(view.width / 2, Math.min(Math.max(cy, 8), view.height - 8));
            await page.mouse.wheel(Math.round(cx - view.width / 2), 0);
        }
        await page.waitForTimeout(650);
    }
    return false;
}

export { Shots, findNode };
