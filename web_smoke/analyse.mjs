// TEST HARNESS ONLY — summarises web_smoke/report.json.
import fs from 'node:fs';

const r = JSON.parse(fs.readFileSync('web_smoke/report.json', 'utf8'));

console.log('=== screens reached ===');
for (const p of r.passes) {
    console.log(`\n-- ${p.pass} (${p.screens.length} screens)`);
    for (const s of p.screens) {
        const flag = s.redirected ? ' [redirected]' : '';
        console.log(`   ${String(s.screen).padEnd(34)} ${String(s.landed).padEnd(30)} labels=${s.labels ?? '-'}${flag}`);
    }
}

console.log('\n=== console / page errors (deduped) ===');
const seen = new Map();
for (const p of r.passes) {
    for (const e of p.events) {
        if (e.kind === 'font-noise') continue;
        const key = `${e.kind}|${e.text.slice(0, 160)}`;
        if (!seen.has(key)) seen.set(key, { ...e, count: 0, passes: new Set() });
        seen.get(key).count += 1;
        seen.get(key).passes.add(p.pass);
    }
}
for (const e of seen.values()) {
    console.log(`[${e.kind} ×${e.count}] ${[...e.passes].join(',')} @ ${e.screen}\n    ${e.text.slice(0, 300).replace(/\n/g, ' ')}`);
}

console.log('\n=== findings ===');
for (const f of r.findings) console.log(`[${f.kind}] ${f.pass} / ${f.screen}: ${f.text}`);

console.log('\n=== blank screens ===');
for (const p of r.passes) {
    for (const s of p.screens) if (s.labels === 0) console.log(`  ${p.pass} / ${s.screen}`);
}
