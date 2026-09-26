// TEST HARNESS ONLY — thin Playwright driver for a Flutter web build.
//
// Flutter renders to a canvas, so there is no ordinary DOM to query. The
// harness turns on Flutter's accessibility tree (the hidden "Enable
// accessibility" placeholder) and drives the app through `<flt-semantics>`
// nodes, which carry `aria-label` and `role` for every widget that has
// semantics.
import fs from 'node:fs';
import path from 'node:path';

export const BASE = process.env.SMOKE_BASE || 'http://127.0.0.1:8080';
export const MOCK = process.env.SMOKE_MOCK || 'http://127.0.0.1:54321';

/** Console / page errors and failed requests, grouped by the current screen. */
export class Recorder {
    constructor() {
        this.screen = 'boot';
        this.events = [];
        this.screens = [];
    }

    at(screen) {
        this.screen = screen;
    }

    push(kind, text) {
        this.events.push({ screen: this.screen, kind, text: String(text).slice(0, 600) });
    }

    attach(page) {
        page.on('console', (m) => {
            const text = m.text();
            // google_fonts verifies a downloaded font against an expected
            // hash; the sandbox has no CDN, so every family fails and rethrows
            // a bare `Error`. Harness noise, not an app defect.
            if (/google_fonts was unable to load|Failed to load font/i.test(text)) {
                this._fontNoise = Date.now();
                return;
            }
            if (m.type() === 'error' || m.type() === 'warning') {
                if (/GL Driver Message|WebGL|swiftshader|GroupMarkerNotSet/i.test(text)) return;
                if (/ERR_CERT_AUTHORITY_INVALID|net::ERR_TUNNEL/.test(text)) return;
                this.push(`console.${m.type()}`, text);
            }
        });
        page.on('pageerror', (e) => {
            const kind = Date.now() - (this._fontNoise ?? 0) < 4000 ? 'font-noise' : 'pageerror';
            this.push(kind, e?.stack || e);
        });
        page.on('requestfailed', (r) => {
            const url = r.url();
            // Fonts and the Google Fonts CDN are stubbed by `route()`; anything
            // still failing there is environmental, not an app defect.
            if (/gstatic|googleapis|onesignal/.test(url)) return;
            this.push('requestfailed', `${r.method()} ${url} — ${r.failure()?.errorText}`);
        });
        page.on('response', (r) => {
            if (r.status() >= 400) this.push('http', `${r.status()} ${r.request().method()} ${r.url()}`);
        });
    }
}

const FONT = '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf';

/** Serves a local font for every Google Fonts request (the sandbox has no CDN). */
export async function stubFonts(context) {
    const bytes = fs.existsSync(FONT) ? fs.readFileSync(FONT) : null;
    await context.route(/fonts\.gstatic\.com|fonts\.googleapis\.com/, async (route) => {
        if (!bytes) return route.abort();
        await route.fulfill({ status: 200, contentType: 'font/ttf', body: bytes });
    });
    // OneSignal's web SDK is not part of this build, but block it defensively.
    await context.route(/onesignal\.com/, (route) => route.abort());
}

export async function enableSemantics(page) {
    await page.waitForSelector('flt-semantics-placeholder', { timeout: 60000 }).catch(() => {});
    await page.evaluate(() => {
        const el = document.querySelector('flt-semantics-placeholder');
        if (el) el.click();
    });
    await page.waitForTimeout(600);
}

/** Every semantics node currently on screen. */
export async function nodes(page) {
    return page.evaluate(() => {
        const out = [];
        document.querySelectorAll('flt-semantics').forEach((el) => {
            const r = el.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) return;
            // Only leaves carry meaningful text: a container's textContent is
            // the concatenation of everything below it.
            const isLeaf = el.querySelector('flt-semantics') === null;
            const label = el.getAttribute('aria-label') || (isLeaf ? (el.textContent || '').trim() : '');
            const field = el.querySelector(':scope > input, :scope > textarea');
            out.push({
                label,
                role: el.getAttribute('role') || el.tagName.toLowerCase(),
                input: !!field,
                value: field ? field.value : null,
                x: r.x, y: r.y, w: r.width, h: r.height,
            });
        });
        out.sort((a, b) => (a.y - b.y) || (a.x - b.x));
        return out;
    });
}

/** All visible text on the current screen (for language / content assertions). */
export async function screenText(page) {
    return (await nodes(page)).map((n) => n.label).filter(Boolean);
}

function escapeForCss(value) {
    return value.replace(/["\\]/g, '\\$&');
}

/**
 * Locates a semantics node. `match` is an exact aria-label, or a RegExp /
 * `{ contains }` for a substring match.
 */
export async function findNode(page, match) {
    const all = await nodes(page);
    if (match instanceof RegExp) return all.find((n) => match.test(n.label)) || null;
    if (typeof match === 'object' && match.contains) {
        return all.find((n) => n.label.toLowerCase().includes(match.contains.toLowerCase())) || null;
    }
    return all.find((n) => n.label === match) || all.find((n) => n.label.trim() === String(match).trim()) || null;
}

export async function has(page, match) {
    return (await findNode(page, match)) !== null;
}

/** Taps a widget by its semantics label. Returns false when it is not there. */
export async function tap(page, match, { settle = 900 } = {}) {
    let node = await findNode(page, match);
    if (!node) return false;
    const view = page.viewportSize();
    // Scroll the target into view first: Flutter draws to a canvas, so a
    // widget below the fold still has a (negative / oversized) rect and
    // clicking a clamped point would hit whatever is on screen instead.
    const centre = node.y + node.h / 2;
    if (centre < 8 || centre > view.height - 8) {
        const delta = Math.round(centre - view.height / 2);
        await page.mouse.move(view.width / 2, view.height / 2);
        await page.mouse.wheel(0, delta);
        await page.waitForTimeout(700);
        node = await findNode(page, match);
        if (!node) return false;
    }
    const y = node.y + node.h / 2;
    if (y < 0 || y > view.height) return false;
    await page.mouse.click(
        Math.min(Math.max(node.x + node.w / 2, 2), view.width - 2),
        Math.min(Math.max(y, 2), view.height - 2),
    );
    await page.waitForTimeout(settle);
    return true;
}

/** Types into a text field identified by its label / hint. */
export async function type(page, match, text) {
    const all = await nodes(page);
    const target = (() => {
        const byLabel = all.find((n) => n.input && (match instanceof RegExp ? match.test(n.label) : n.label.includes(match)));
        if (byLabel) return byLabel;
        return null;
    })();
    if (!target) return false;
    await clickNode(page, target);
    await page.waitForTimeout(200);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(text, { delay: 12 });
    await page.waitForTimeout(250);
    return true;
}

/** Clicks a node's centre, scrolling it into view when necessary. */
async function clickNode(page, node) {
    const view = page.viewportSize();
    let centre = node.y + node.h / 2;
    if (centre < 8 || centre > view.height - 8) {
        await page.mouse.move(view.width / 2, view.height / 2);
        await page.mouse.wheel(0, Math.round(centre - view.height / 2));
        await page.waitForTimeout(600);
        centre = Math.min(Math.max(view.height / 2, 8), view.height - 8);
    }
    await page.mouse.click(Math.min(Math.max(node.x + node.w / 2, 2), view.width - 2), centre);
}

/** Types into the n-th editable field on screen (when labels are ambiguous). */
export async function typeNth(page, index, text) {
    const inputs = (await nodes(page)).filter((n) => n.input);
    const target = inputs[index];
    if (!target) return false;
    await clickNode(page, target);
    await page.waitForTimeout(200);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(text, { delay: 12 });
    await page.waitForTimeout(250);
    return true;
}

/**
 * Sets a Slider's value. Flutter exposes a Slider as `<input type=range>` in
 * the semantics tree; that element swallows pointer events (so dragging the
 * painted thumb does nothing) but the widget does react to its `change`
 * event. [fraction] is 0..1 of the slider's range.
 */
export async function setRange(page, fraction) {
    return page.evaluate((f) => {
        const el = document.querySelector('flt-semantics input[type=range]');
        if (!el) return null;
        const min = Number(el.min || 0);
        const max = Number(el.max || 1);
        el.value = String(Math.round(min + (max - min) * f));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return el.value;
    }, fraction);
}

export async function scroll(page, dy = 400) {
    const v = page.viewportSize();
    await page.mouse.move(v.width / 2, v.height / 2);
    await page.mouse.wheel(0, dy);
    await page.waitForTimeout(700);
}

export async function currentRoute(page) {
    return page.evaluate(() => location.hash || location.pathname);
}

/** Navigates by URL (go_router uses the hash strategy on web). */
export async function goto(page, route, { settle = 2200 } = {}) {
    await page.evaluate((r) => {
        window.location.hash = r;
    }, route);
    await page.waitForTimeout(settle);
}

export class Shots {
    constructor(dir) {
        this.dir = dir;
        this.n = 0;
        fs.mkdirSync(dir, { recursive: true });
    }

    async take(page, name) {
        this.n += 1;
        const file = path.join(this.dir, `${String(this.n).padStart(3, '0')}-${name.replace(/[^a-z0-9._-]+/gi, '-')}.png`);
        await page.screenshot({ path: file });
        return file;
    }
}

/** Waits until the semantics tree has content (the frame has painted). */
export async function settle(page, ms = 1500) {
    await page.waitForTimeout(ms);
}
