// TEST HARNESS ONLY — drives the built Flutter web app through every screen.
//
//   node web_smoke/mock-supabase.mjs &        # local mock backend
//   node web_smoke/serve.mjs build/web &      # static server
//   node web_smoke/smoke.mjs                  # this script
//
// See web_smoke/README.md. Everything runs against 127.0.0.1 — no real
// Supabase project is ever contacted.
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '/home/user/CRADI-Mobile-Admin/node_modules/playwright/index.mjs';
import {
    BASE, MOCK, Recorder, Shots, enableSemantics, findNode, goto, has, nodes,
    screenText, scroll, setRange, stubFonts, tap, type, typeNth,
} from './driver.mjs';

const OUT = path.resolve('web_smoke/screenshots');
const REPORT = path.resolve('web_smoke/report.json');
const PASSWORD = 'Password123!';

const ACCOUNTS = {
    user: 'user@cradi.test',
    ewm: 'ewm@cradi.test',
    ewv: 'ewv@cradi.test',
    ewr: 'ewr@cradi.test',
    ldp: 'ldp@cradi.test',
    staff: 'staff@cradi.test',
    admin: 'admin@cradi.test',
    tech: 'tech@cradi.test',
    pending: 'pending@cradi.test',
    unverified: 'unverified@cradi.test',
};

const results = { passes: [], findings: [] };

function note(pass, screen, kind, text) {
    results.findings.push({ pass, screen, kind, text });
    console.log(`  ! [${kind}] ${screen}: ${text}`);
}

async function newSession(browser, { width = 390, height = 844, fontScale = 1 } = {}) {
    const ctx = await browser.newContext({
        viewport: { width, height },
        deviceScaleFactor: 1,
        permissions: [],
        locale: 'en-US',
    });
    await stubFonts(ctx);
    const page = await ctx.newPage();
    const rec = new Recorder();
    rec.attach(page);
    if (fontScale !== 1) {
        await page.addInitScript((s) => {
            Object.defineProperty(window, 'devicePixelRatio', { get: () => 1 });
            window.__forcedTextScale = s;
        }, fontScale);
    }
    await page.goto(BASE, { waitUntil: 'load' });
    await page.waitForTimeout(6000);
    await enableSemantics(page);
    return { ctx, page, rec };
}

async function login(page, email) {
    await goto(page, '#/login', { settle: 2500 });
    if (!(await type(page, /Email/i, email))) {
        // Fall back to field order: email, then password.
        await typeNth(page, 0, email);
    }
    await typeNth(page, 1, PASSWORD);
    await page.keyboard.press('Escape');
    const ok = (await tap(page, 'Login', { settle: 3500 })) || (await tap(page, { contains: 'Login' }, { settle: 3500 }));
    await page.waitForTimeout(3000);
    return ok;
}

async function visit(pass, page, rec, shots, name, route, { after } = {}) {
    rec.at(name);
    if (route) {
        // Dismiss anything the previous step left open (drawer, bottom sheet,
        // dialog) so the next screen is not driven through an overlay.
        await page.keyboard.press('Escape');
        await page.waitForTimeout(400);
        await page.keyboard.press('Escape');
        await page.waitForTimeout(400);
        await goto(page, route, { settle: 2600 });
    }
    await page.waitForTimeout(900);
    if (after) {
        try {
            await after(page);
        } catch (e) {
            note(pass, name, 'harness', `interaction failed: ${e.message}`);
        }
    }
    const texts = await screenText(page);
    const file = await shots.take(page, `${name}`);
    const hash = await page.evaluate(() => location.hash);
    const entry = { screen: name, requested: route || '(current)', landed: hash, labels: texts.length, shot: path.relative(process.cwd(), file) };
    if (texts.length === 0) note(pass, name, 'blank', 'no semantics nodes — screen rendered nothing');
    if (route && hash && route !== hash && !hash.startsWith(route)) {
        entry.redirected = true;
    }
    // Flutter surfaces build errors as a red "…Exception…" box; the semantics
    // tree then contains the exception text.
    const err = texts.find((t) => /RenderFlex overflowed|Exception|Failed assertion|A RenderFlex/i.test(t));
    if (err) note(pass, name, 'render-error', err.slice(0, 300));
    return entry;
}

// ── Passes ──────────────────────────────────────────────────────────────────

async function signedOutPass(browser) {
    const pass = 'signed-out';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);

    rec.at('splash');
    screens.push({ screen: 'splash-then-landing', landed: await page.evaluate(() => location.hash), shot: path.relative(process.cwd(), await shots.take(page, 'splash-or-landing')) });

    screens.push(await visit(pass, page, rec, shots, 'onboarding', '#/onboarding', {
        after: async (p) => {
            for (let i = 0; i < 3; i++) {
                if (!(await tap(p, { contains: 'Next' }))) await scroll(p, 300);
                await shots.take(p, `onboarding-step-${i + 2}`);
            }
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'landing', '#/landing'));
    screens.push(await visit(pass, page, rec, shots, 'login', '#/login', {
        after: async (p) => {
            await typeNth(p, 0, 'not-an-email');
            await typeNth(p, 1, 'short');
            await tap(p, 'Login', { settle: 1500 });
            await shots.take(p, 'login-validation');
            await typeNth(p, 0, ACCOUNTS.user);
            await typeNth(p, 1, 'WrongPassword1!');
            await tap(p, 'Login', { settle: 3000 });
            await shots.take(p, 'login-bad-credentials');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'forgot-password', '#/forgot-password', {
        after: async (p) => {
            await typeNth(p, 0, ACCOUNTS.user);
            await tap(p, { contains: 'Send' }, { settle: 2500 });
            await shots.take(p, 'forgot-password-sent');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'reset-password', `#/reset-password?email=${encodeURIComponent(ACCOUNTS.user)}`, {
        after: async (p) => {
            // Field 0 is the email (pre-filled from the query), 1 the code,
            // 2 / 3 the new password and its confirmation.
            await typeNth(p, 1, '000000');
            await typeNth(p, 2, 'NewPassword123!');
            await typeNth(p, 3, 'NewPassword123!');
            await shots.take(p, 'reset-password-filled');
            // A wrong code must be refused without leaving the form.
            await tap(p, 'Reset Password', { settle: 2500 });
            await shots.take(p, 'reset-password-wrong-code');
            await typeNth(p, 1, '123456');
            await tap(p, 'Reset Password', { settle: 3000 });
            await shots.take(p, 'reset-password-done');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'registration', '#/register', {
        after: async (p) => {
            const labels = (await nodes(p)).filter((n) => n.input).length;
            console.log(`    registration has ${labels} fields`);
            await typeNth(p, 0, 'Smoke Tester');
            await typeNth(p, 1, `smoke${Date.now()}@cradi.test`);
            await shots.take(p, 'registration-partial');
            await scroll(p, 600);
            await shots.take(p, 'registration-scrolled');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'verify-otp', `#/verify-otp?phone=${encodeURIComponent('+2348030000001')}`, {
        after: async (p) => {
            await typeNth(p, 0, '123456');
            await shots.take(p, 'verify-otp-filled');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'help-signed-out', '#/help'));
    screens.push(await visit(pass, page, rec, shots, 'offline-home', '#/offline'));
    screens.push(await visit(pass, page, rec, shots, 'route-not-found', '#/definitely-not-a-route'));

    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

const TOUR = [
    ['dashboard', '#/dashboard'],
    ['dashboard-nearby-tab', null, async (p) => { await tap(p, 'Nearby'); }],
    ['my-reports', '#/my-reports'],
    ['nearby-reports', '#/nearby-reports'],
    ['alerts', '#/alerts'],
    ['knowledge-base', '#/knowledge-base'],
    ['hazard-guides', '#/knowledge-base/guides'],
    ['contacts', '#/contacts'],
    ['chat', '#/chat'],
    ['notifications', '#/notifications'],
    ['profile', '#/profile'],
    ['settings', '#/settings'],
    ['about', '#/about'],
    ['help', '#/help'],
    ['reports-status', '#/reports-status'],
    ['verification-list', '#/verification'],
    ['verification-request', '#/verification/request'],
    ['alerts-manage', '#/alerts/manage'],
    ['admin', '#/admin'],
    ['admin-users', '#/admin/users'],
    ['admin-reports', '#/admin/reports'],
    ['admin-alerts', '#/admin/alerts'],
    ['admin-knowledge', '#/admin/knowledge'],
    ['route-not-found', '#/definitely-not-a-route'],
    ['deep-link-report-missing', '#/report/00000000-0000-4000-8000-000000009999'],
    ['deep-link-alert', '#/alert/00000000-0000-4000-8000-000000000101'],
];

async function rolePass(browser, role) {
    const pass = `role-${role}`;
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);

    rec.at('login');
    const ok = await login(page, ACCOUNTS[role]);
    const landed = await page.evaluate(() => location.hash);
    console.log(`  login(${role}) tapped=${ok} landed=${landed}`);
    screens.push({ screen: 'after-login', landed, shot: path.relative(process.cwd(), await shots.take(page, 'after-login')) });
    if (!/dashboard|pending|verify/.test(landed)) {
        note(pass, 'login', 'login-failed', `did not reach the dashboard (landed ${landed})`);
    }

    for (const [name, route, after] of TOUR) {
        screens.push(await visit(pass, page, rec, shots, name, route, { after }));
    }

    // Deeper interactions that only make sense once signed in.
    if (role === 'user' || role === 'ewm') {
        screens.push(...(await reportWizard(pass, page, rec, shots, 'Flooding')));
        screens.push(...(await reportWizard(pass, page, rec, shots, 'Conflict')));
    }
    if (role === 'admin') {
        screens.push(...(await reportWizard(pass, page, rec, shots, 'Drought')));
    }

    // Open the first alert, the first knowledge guide and the first report.
    screens.push(await visit(pass, page, rec, shots, 'alert-detail', '#/alerts', {
        after: async (p) => { await tap(p, { contains: 'Flood warning' }, { settle: 2200 }); },
    }));
    screens.push(await visit(pass, page, rec, shots, 'knowledge-detail', '#/knowledge-base', {
        after: async (p) => { await tap(p, { contains: 'Flood safety' }, { settle: 2200 }); },
    }));
    screens.push(await visit(pass, page, rec, shots, 'report-view', '#/reports-status', {
        after: async (p) => {
            if (!(await tap(p, 'View Details', { settle: 2500 }))) {
                note(pass, 'report-view', 'missing-control', 'no "View Details" link on the reports-status list');
            }
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'reports-status-tabs', '#/reports-status', {
        after: async (p) => {
            for (const tab of ['Verified', 'Approved', 'Rejected']) {
                await tap(p, tab, { settle: 1600 });
                await shots.take(p, `reports-status-${tab}`);
            }
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'sos-sheet', '#/profile', {
        after: async (p) => {
            await scroll(p, 400);
            if (!(await tap(p, { contains: 'SOS' }, { settle: 1800 }))) {
                note(pass, 'sos-sheet', 'missing-control', 'no SOS button on the profile screen');
            }
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'settings-toggles', '#/settings', {
        after: async (p) => {
            await tap(p, { contains: 'Push Notifications' }, { settle: 1200 });
            await shots.take(p, 'settings-push-toggled');
            await tap(p, { contains: 'Offline Mode' }, { settle: 1200 });
            await shots.take(p, 'settings-offline-toggled');
            await scroll(p, 500);
            await tap(p, { contains: 'Biometric' }, { settle: 1200 });
            await shots.take(p, 'settings-biometric-toggled');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'chat-send', '#/chat', {
        after: async (p) => {
            await typeNth(p, 0, 'Smoke test message');
            // flutter_chat_ui's send control is an unlabelled icon button at
            // the end of the composer row.
            if (!(await tap(p, { contains: 'Send' }, { settle: 1500 }))) {
                const field = (await nodes(p)).filter((n) => n.input).pop();
                if (field) {
                    await p.mouse.click(p.viewportSize().width - 24, field.y + field.h / 2);
                    await p.waitForTimeout(1200);
                }
                await p.keyboard.press('Enter');
                await p.waitForTimeout(2200);
            }
        },
    }));

    // Last: the drawer is a route overlay that neither Escape nor a URL
    // change closes, so opening it would derail every later step.
    screens.push(await visit(pass, page, rec, shots, 'shell-drawer', '#/dashboard', {
        after: async (p) => {
            for (const label of ['Open navigation menu', 'Menu', 'Show menu']) {
                if (await tap(p, { contains: label }, { settle: 1400 })) break;
            }
        },
    }));

    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

async function reportWizard(pass, page, rec, shots, hazard) {
    const out = [];
    out.push(await visit(pass, page, rec, shots, `report-1-hazard-${hazard}`, '#/report', {
        after: async (p) => {
            let picked = await tap(p, hazard, { settle: 900 });
            for (let i = 0; !picked && i < 4; i++) {
                await scroll(p, 260);
                picked = await tap(p, hazard, { settle: 900 });
            }
            if (!picked) note(pass, `report-1-hazard-${hazard}`, 'missing-control', `hazard tile "${hazard}" not reachable`);
            await shots.take(p, `report-1-hazard-selected-${hazard}`);
            if (!(await tap(p, 'Continue', { settle: 1800 }))) {
                note(pass, `report-1-hazard-${hazard}`, 'missing-control', 'no Continue button on the hazard screen');
            }
        },
    }));
    out.push(await visit(pass, page, rec, shots, `report-2-severity-${hazard}`, null, {
        after: async (p) => {
            // Severity is a Slider; Flutter exposes it as a range input.
            const value = await setRange(p, 1); // highest severity
            if (value === null) {
                note(pass, `report-2-severity-${hazard}`, 'missing-control', 'no severity slider');
            }
            await p.waitForTimeout(800);
            await shots.take(p, `report-2-severity-set-${hazard}`);
            if (!(await tap(p, { contains: 'Next: Location' }, { settle: 1800 }))) {
                note(pass, `report-2-severity-${hazard}`, 'missing-control', 'no "Next: Location" button');
            }
        },
    }));
    out.push(await visit(pass, page, rec, shots, `report-3-location-${hazard}`, null, {
        after: async (p) => {
            // Location permission prompt. geolocator is unavailable on the
            // web, so either the "Not Now" rationale or the
            // "permanently denied → Open Settings" dialog can appear.
            for (const dismiss of ['Not Now', 'Cancel', 'Dismiss', 'Close']) {
                if (await tap(p, dismiss, { settle: 1200 })) break;
            }
            await pickDropdown(p, 'Select State', 'Benue');
            await pickDropdown(p, 'Select LGA', 'Makurdi');
            await pickDropdown(p, 'Select Ward', 'Agan');
            await shots.take(p, `report-3-location-filled-${hazard}`);
            await scroll(p, 500);
            if (!(await tap(p, { contains: 'Confirm & Continue' }, { settle: 2000 }))) {
                if (!(await tap(p, { contains: 'Continue' }, { settle: 2000 }))) {
                    note(pass, `report-3-location-${hazard}`, 'missing-control', 'no Continue on the location screen');
                }
            }
        },
    }));
    out.push(await visit(pass, page, rec, shots, `report-4-details-${hazard}`, null, {
        after: async (p) => {
            await typeNth(p, 0, `Automated smoke-test description for ${hazard}.`);
            await p.keyboard.press('Escape');
            await scroll(p, 500);
            await shots.take(p, `report-4-details-filled-${hazard}`);
            if (!(await tap(p, { contains: 'Review Report' }, { settle: 2000 }))) {
                note(pass, `report-4-details-${hazard}`, 'missing-control', 'no "Review Report" button');
            }
        },
    }));
    out.push(await visit(pass, page, rec, shots, `report-5-review-${hazard}`, null, {
        after: async (p) => {
            await scroll(p, 700);
            await shots.take(p, `report-5-review-scrolled-${hazard}`);
            if (!(await tap(p, { contains: 'Submit Report' }, { settle: 5000 }))) {
                note(pass, `report-5-review-${hazard}`, 'missing-control', 'no Submit Report button on the review screen');
            } else if (!(await has(p, { contains: 'Report Submitted' }))) {
                // The success screen is a modal dialog over the review page.
                note(pass, `report-5-review-${hazard}`, 'submit-failed', 'no "Report Submitted" dialog after Submit');
            }
        },
    }));
    out.push(await visit(pass, page, rec, shots, `report-6-after-submit-${hazard}`, null, {
        after: async (p) => {
            await tap(p, { contains: 'Return to Dashboard' }, { settle: 2000 });
        },
    }));
    return out;
}

/** Picks a value from a Flutter DropdownButton by label. */
async function pickDropdown(page, trigger, wanted) {
    if (!(await tap(page, { contains: trigger }, { settle: 1400 }))) return false;
    for (let attempt = 0; attempt < 8; attempt++) {
        if (await tap(page, wanted, { settle: 1200 })) return true;
        await scroll(page, 200);
    }
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    return false;
}

async function languagePass(browser) {
    const pass = 'languages';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);
    await login(page, ACCOUNTS.ewv);

    const perLanguage = {};
    // The picker shows each language's native name.
    const NATIVE = { Hausa: 'Hausa', Yoruba: 'Yorùbá', Igbo: 'Asụsụ Igbo', Pidgin: 'Naijá', English: 'English' };
    // English first: it is the baseline the other four are compared against.
    for (const lang of ['English', 'Hausa', 'Yoruba', 'Igbo', 'Pidgin']) {
        rec.at(`language-${lang}`);
        await goto(page, '#/settings', { settle: 2200 });
        // The settings row is itself translated, so try every locale's word
        // for "Language" (en/pcm: Language, ha: Harshe, yo: Èdè, ig: Asụsụ).
        let opened = false;
        for (const label of ['Language', 'Harshe', 'Èdè', 'Asụsụ', 'Ede', 'Asusu']) {
            if (await tap(page, { contains: label }, { settle: 1400 })) {
                opened = true;
                break;
            }
        }
        if (!opened) note(pass, 'settings', 'missing-control', 'no Language row on the settings screen');
        await shots.take(page, `language-picker-${lang}`);
        const picked = await tap(page, { contains: NATIVE[lang] }, { settle: 2200 });
        if (!picked) note(pass, 'settings', 'missing-control', `language option "${lang}" not found`);
        await tap(page, { contains: 'Close' }, { settle: 800 });
        await page.keyboard.press('Escape');
        await page.waitForTimeout(800);

        perLanguage[lang] = {};
        for (const [name, route] of [
            ['dashboard', '#/dashboard'],
            ['alerts', '#/alerts'],
            ['report-hazards', '#/report'],
            ['my-reports', '#/my-reports'],
            ['nearby-reports', '#/nearby-reports'],
            ['knowledge-base', '#/knowledge-base'],
            ['hazard-guides', '#/knowledge-base/guides'],
            ['contacts', '#/contacts'],
            ['chat', '#/chat'],
            ['notifications', '#/notifications'],
            ['profile', '#/profile'],
            ['settings', '#/settings'],
            ['about', '#/about'],
            ['help', '#/help'],
            ['reports-status', '#/reports-status'],
            ['verification', '#/verification'],
        ]) {
            rec.at(`${lang}/${name}`);
            await goto(page, route, { settle: 1800 });
            const texts = await screenText(page);
            perLanguage[lang][name] = texts;
            await shots.take(page, `${lang}-${name}`);
        }
        screens.push({ screen: `language-${lang}`, landed: lang });
    }
    fs.writeFileSync(path.resolve('web_smoke/language-texts.json'), JSON.stringify(perLanguage, null, 1));

    // Compare each translated screen with the English one.
    const english = perLanguage.English;
    for (const lang of ['Hausa', 'Yoruba', 'Igbo', 'Pidgin']) {
        for (const screen of Object.keys(english)) {
            const en = new Set(english[screen]);
            const tr = perLanguage[lang][screen] ?? [];
            if (tr.length === 0) continue;
            const identical = tr.filter((t) => en.has(t) && /[a-z]/i.test(t) && t.length > 3);
            const ratio = identical.length / tr.length;
            if (ratio > 0.8) {
                note(pass, `${lang}/${screen}`, 'untranslated', `${identical.length}/${tr.length} labels identical to English`);
            } else if (identical.length > 0) {
                results.findings.push({
                    pass, screen: `${lang}/${screen}`, kind: 'partial-translation',
                    text: `${identical.length}/${tr.length} labels still English: ${identical.slice(0, 12).join(' | ')}`,
                });
            }
        }
    }

    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

async function smallViewportPass(browser) {
    const pass = 'small-viewport-320x640';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser, { width: 320, height: 640 });
    const screens = [];
    console.log(`\n== ${pass} ==`);
    await login(page, ACCOUNTS.admin);
    for (const [name, route, after] of TOUR) {
        screens.push(await visit(pass, page, rec, shots, name, route, { after }));
    }
    screens.push(...(await reportWizard(pass, page, rec, shots, 'Wildfires')));
    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

async function edgeAccountsPass(browser) {
    const pass = 'edge-accounts';
    const shots = new Shots(path.join(OUT, pass));
    console.log(`\n== ${pass} ==`);
    const screens = [];
    for (const account of ['pending', 'unverified']) {
        const { ctx, page, rec } = await newSession(browser);
        rec.at(account);
        await login(page, ACCOUNTS[account]);
        const landed = await page.evaluate(() => location.hash);
        console.log(`  ${account} landed on ${landed}`);
        screens.push({ screen: `${account}-after-login`, landed, shot: path.relative(process.cwd(), await shots.take(page, `${account}-after-login`)) });
        // The guarded routes each account should be bounced away from.
        for (const route of ['#/dashboard', '#/report', '#/settings']) {
            await goto(page, route, { settle: 2000 });
            screens.push({ screen: `${account}${route}`, landed: await page.evaluate(() => location.hash), shot: path.relative(process.cwd(), await shots.take(page, `${account}${route.replace(/\W+/g, '-')}`)) });
        }
        results.passes.push({ pass: `${pass}-${account}`, screens: [], events: rec.events });
        await ctx.close();
    }
    results.passes.push({ pass, screens, events: [] });
}

async function offlinePass(browser) {
    const pass = 'offline';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);
    await login(page, ACCOUNTS.user);
    await ctx.setOffline(true);
    await page.waitForTimeout(4000);
    for (const [name, route] of [
        ['offline-home', '#/offline'],
        ['offline-dashboard', '#/dashboard'],
        ['offline-report', '#/report'],
        ['offline-knowledge', '#/knowledge-base'],
        ['offline-settings', '#/settings'],
        ['offline-contacts', '#/contacts'],
        ['offline-alerts', '#/alerts'],
    ]) {
        screens.push(await visit(pass, page, rec, shots, name, route));
    }
    await ctx.setOffline(false);
    await page.waitForTimeout(3000);
    screens.push(await visit(pass, page, rec, shots, 'back-online-dashboard', '#/dashboard'));
    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

/** Report wizard only, across several hazard categories. */
async function wizardPass(browser) {
    const pass = 'wizard';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);
    await login(page, ACCOUNTS.ewm);
    for (const hazard of ['Flooding', 'Drought', 'Wildfires', 'Pest Outbreak', 'Conflict']) {
        screens.push(...(await reportWizard(pass, page, rec, shots, hazard)));
    }
    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

/** Short pass for the interactions the broad tour cannot reach cleanly. */
async function focusPass(browser) {
    const pass = 'focus';
    const shots = new Shots(path.join(OUT, pass));
    const { ctx, page, rec } = await newSession(browser);
    const screens = [];
    console.log(`\n== ${pass} ==`);
    await login(page, ACCOUNTS.ewv);

    // Settings toggles, on their own so no overlay is in the way.
    screens.push(await visit(pass, page, rec, shots, 'settings-push-toggle', '#/settings', {
        after: async (p) => {
            await tap(p, { contains: 'Push Notifications' }, { settle: 1500 });
            await shots.take(p, 'settings-after-push-toggle');
            await tap(p, { contains: 'Biometric' }, { settle: 1500 });
            await shots.take(p, 'settings-after-biometric-tap');
        },
    }));

    // Peer verification: open the first report in the verify list and vote.
    screens.push(await visit(pass, page, rec, shots, 'verification-detail', '#/verification', {
        after: async (p) => {
            // Tap the first list row by position: its label is multi-line, so
            // a label lookup would scroll the list instead of opening it.
            const row = (await nodes(p)).find((n) => n.y > 120 && n.y < 300 && n.w > 250);
            if (!row) {
                note(pass, 'verification-detail', 'missing-control', 'no report rows in the verify list');
                return;
            }
            await p.mouse.click(row.x + row.w / 2, row.y + row.h / 2);
            await p.waitForTimeout(2500);
            await shots.take(p, 'verification-detail-open');
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'verification-vote', null, {
        after: async (p) => {
            for (let i = 0; i < 5; i++) await scroll(p, 400);
            await shots.take(p, 'verification-detail-bottom');
            const btn = (await nodes(p)).find((n) => /I Can Confirm/i.test(n.label));
            if (!btn) {
                note(pass, 'verification-vote', 'missing-control', 'no "I Can Confirm" button');
                return;
            }
            await p.mouse.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
            await p.waitForTimeout(4000);
            if (!(await has(p, { contains: 'Thank you' }))) {
                note(pass, 'verification-vote', 'vote-failed', 'no confirmation after casting a peer vote');
            }
        },
    }));

    // Report view with peer votes (the embedded verifier select).
    screens.push(await visit(pass, page, rec, shots, 'report-view-with-votes', '#/reports-status', {
        after: async (p) => {
            await tap(p, 'View Details', { settle: 2500 });
            await scroll(p, 400);
        },
    }));

    // Severity slider: drag it to a level other than the default.
    screens.push(await visit(pass, page, rec, shots, 'severity-slider', '#/report', {
        after: async (p) => {
            await tap(p, 'Flooding', { settle: 900 });
            await tap(p, 'Continue', { settle: 1800 });
            await setRange(p, 1); // drag the severity slider to Critical
            await p.waitForTimeout(900);
        },
    }));

    // Nearby reports + alerts search / filters.
    screens.push(await visit(pass, page, rec, shots, 'alerts-search', '#/alerts', {
        after: async (p) => {
            await typeNth(p, 0, 'flood');
            await p.waitForTimeout(1200);
            await shots.take(p, 'alerts-search-flood');
            await tap(p, { contains: 'Report History' }, { settle: 2000 });
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'knowledge-search', '#/knowledge-base', {
        after: async (p) => {
            await typeNth(p, 0, 'flood');
            await p.waitForTimeout(1500);
        },
    }));
    screens.push(await visit(pass, page, rec, shots, 'contacts-add', '#/contacts', {
        after: async (p) => {
            await tap(p, { contains: 'Add' }, { settle: 1800 });
        },
    }));

    // Last: switching Offline Mode on reroutes every protected screen to
    // /offline, so nothing else can run after it.
    screens.push(await visit(pass, page, rec, shots, 'settings-offline-mode', '#/settings', {
        after: async (p) => {
            await tap(p, { contains: 'Offline Mode' }, { settle: 2500 });
            await shots.take(p, 'settings-offline-mode-on');
            await goto(p, '#/dashboard', { settle: 2500 });
        },
    }));

    results.passes.push({ pass, screens, events: rec.events });
    await ctx.close();
}

// ── Main ────────────────────────────────────────────────────────────────────

const only = process.argv.slice(2);
const wanted = (name) => only.length === 0 || only.includes(name);

// Clear only the passes this invocation will rewrite, so a partial re-run
// does not throw away the screenshots of the passes it is not running.
fs.mkdirSync(OUT, { recursive: true });
const PASS_DIRS = { small: 'small-viewport-320x640', edge: 'edge-accounts' };
for (const dir of fs.readdirSync(OUT)) {
    const selected = only.length === 0
        || only.includes(dir)
        || only.some((o) => PASS_DIRS[o] === dir)
        || (dir.startsWith('role-') && only.includes('roles'));
    if (selected) fs.rmSync(path.join(OUT, dir), { recursive: true, force: true });
}
await fetch(`${MOCK}/__mock/reset`, { method: 'POST' }).catch(() => {
    console.error(`Mock backend not reachable at ${MOCK} — start web_smoke/mock-supabase.mjs first.`);
    process.exit(1);
});

const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--no-sandbox'] });
try {
    if (wanted('signed-out')) await signedOutPass(browser);
    for (const role of ['user', 'ewm', 'ewv', 'ewr', 'admin']) {
        if (wanted(`role-${role}`) || wanted('roles')) await rolePass(browser, role);
    }
    if (wanted('edge')) await edgeAccountsPass(browser);
    if (wanted('offline')) await offlinePass(browser);
    if (wanted('wizard')) await wizardPass(browser);
    if (wanted('focus')) await focusPass(browser);
    if (wanted('languages')) await languagePass(browser);
    if (wanted('small')) await smallViewportPass(browser);
} finally {
    await browser.close();
    fs.writeFileSync(REPORT, JSON.stringify(results, null, 1));
    console.log(`\nScreenshots: ${OUT}\nReport:      ${REPORT}`);
    const bad = results.passes.flatMap((p) => p.events.filter((e) => e.kind === 'pageerror' || e.kind.startsWith('console.error')));
    console.log(`Findings: ${results.findings.length}, console/page errors: ${bad.length}`);
}
