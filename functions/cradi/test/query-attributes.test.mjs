import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';

/**
 * Every attribute the Functions query must exist in the provisioned schema.
 *
 * Appwrite refuses a query naming an attribute it does not have —
 * "Invalid query: Attribute not found in schema: isActive", 400 — so a
 * stray filter does not narrow a list, it fails the whole call. That is
 * how `notifyApproved` filtered `authorities` on an `isActive` that never
 * existed in either schema: the SMS send failed on every approved report,
 * and no unit test noticed because the fake never validated attributes.
 *
 * This reads the committed column list, so a column renamed in the
 * migrations and forgotten in a Function shows up here rather than at 3am.
 */
const here = dirname(fileURLToPath(import.meta.url));
const SRC = join(here, '..', 'src');
const COLUMNS = join(here, '..', '..', '..', 'infra', 'appwrite', 'columns.json');

const SYSTEM = new Set(['$id', '$createdAt', '$updatedAt', '$permissions', '$sequence']);

function jsFiles(dir) {
    const out = [];
    for (const entry of readdirSync(dir)) {
        const full = join(dir, entry);
        if (statSync(full).isDirectory()) out.push(...jsFiles(full));
        else if (entry.endsWith('.js')) out.push(full);
    }
    return out;
}

/** Module-level `const NAME = 'literal';` in one file. */
const CONST = /^\s*(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*=\s*'([a-z_]+)'\s*;/gm;
/** `import { A as B, C } from './rel.js';` */
const IMPORT = /import\s*\{([^}]*)\}\s*from\s*'(\.[^']*)'/g;
const OPEN = /(?:listRowsOrThrow|listRows)\(\s*(?:'([a-z_]+)'|([A-Za-z_$][\w$]*))\s*,/g;
const ATTR = /Query\.\w+\(\s*'([^']+)'/g;

const sources = new Map(jsFiles(SRC).map((f) => [f, readFileSync(f, 'utf8')]));
const constantsOf = new Map(
    [...sources].map(([f, src]) => [f, new Map([...src.matchAll(CONST)].map((m) => [m[1], m[2]]))]),
);

/**
 * The literal a name stands for in `file`: its own constant, or the one it
 * imports under that alias.
 *
 * Needed because most reads name their collection by constant, and
 * `operation.js` imports the outbox's as `OUTBOX`. Resolving only
 * same-file constants left that call site unchecked.
 */
function resolveName(file, name) {
    const own = constantsOf.get(file)?.get(name);
    if (own) return own;
    for (const [, spec, from] of sources.get(file).matchAll(IMPORT)) {
        for (const part of spec.split(',')) {
            const [exported, alias] = part.split(/\s+as\s+/).map((s) => s.trim());
            if ((alias || exported) !== name) continue;
            const target = resolve(dirname(file), from);
            const hit = constantsOf.get(target)?.get(exported);
            if (hit) return hit;
        }
    }
    return null;
}

/** The source from `from` to the paren closing the one before it. */
function argumentList(src, from) {
    let depth = 0;
    for (let i = from; i < src.length; i++) {
        const c = src[i];
        if (c === '(' || c === '[') depth += 1;
        else if (c === ']') depth -= 1;
        else if (c === ')') {
            if (depth === 0) return src.slice(from, i);
            depth -= 1;
        }
    }
    return src.slice(from);
}

describe('query attributes exist in the schema', () => {
    const columns = JSON.parse(readFileSync(COLUMNS, 'utf8'));
    const known = new Map(
        Object.entries(columns).map(([table, cols]) => [table, new Set(cols.map((c) => c.key))]),
    );

    const found = [];
    const unresolved = [];
    for (const [file, src] of sources) {
        for (const match of src.matchAll(OPEN)) {
            const body = argumentList(src, match.index + match[0].length);
            const attributes = [...body.matchAll(ATTR)].map((m) => m[1]);
            // A read with no attribute filter has nothing to check — which
            // is what the two wrapper definitions in lib/appwrite.js are.
            if (attributes.length === 0) continue;
            const table = match[1] ?? resolveName(file, match[2]);
            if (!table) {
                unresolved.push({ file, name: match[2], attributes });
                continue;
            }
            for (const attribute of attributes) found.push({ file, table, attribute });
        }
    }

    it('found the reads to check', () => {
        // A matcher that silently finds nothing would make every assertion
        // below pass. 17 is what the Functions have today; a read added
        // without this rising means the matcher stopped seeing it.
        assert.ok(found.length >= 17, `only ${found.length} filtered attributes found`);
    });

    it('resolves every collection it checks', () => {
        assert.deepEqual(unresolved, []);
    });

    it('names only collections the plan provisions', () => {
        const unknown = [...new Set(found.map((f) => f.table))].filter((t) => !known.has(t));
        assert.deepEqual(unknown, []);
    });

    it('names only attributes those collections have', () => {
        const bad = found.filter(
            (f) => !SYSTEM.has(f.attribute) && !known.get(f.table).has(f.attribute),
        );
        assert.deepEqual(
            bad.map((f) => `${f.table}.${f.attribute}`),
            [],
        );
    });
});
