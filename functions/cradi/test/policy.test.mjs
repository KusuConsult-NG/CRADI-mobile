import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { RULES, WRITABLE, assertCoverage, assertLocation, assertTarget } from '../src/lib/policy.js';
import { wardTeam } from '../src/lib/appwrite.js';
import { strip } from '../src/write.js';

// Resolved from this file, so `npm test` works from the Function
// directory and from the repo root alike.
const here = dirname(fileURLToPath(import.meta.url));
const inRepo = (p) => resolve(here, '../../..', p);
const LOCATIONS = resolve(here, '../src/data/locations.json');

describe('the rules agree with themselves', () => {
  it('serverOwned lists exactly what create() stamps', () => {
    // `strip` removes `serverOwned` and `create` puts the real values
    // back. If the two drift, a field the client sent survives the strip
    // and is then overwritten anyway (harmless) — or worse, a field
    // create() does *not* set is stripped and silently lost.
    const ctx = { userId: 'u1', profile: { name: 'A', role: 'ewm' }, documentId: 'd1' };
    for (const [collection, rule] of Object.entries(RULES)) {
      if (!rule.create) continue;
      const stamped = Object.keys(rule.create(ctx));
      const declared = rule.serverOwned ?? [];
      for (const field of stamped) {
        assert.ok(
          declared.includes(field),
          `${collection}: create() sets "${field}" but serverOwned does not list it`,
        );
      }
    }
  });

  it('every rule covers a collection this Function will write', () => {
    for (const collection of Object.keys(RULES)) {
      assert.ok(WRITABLE.has(collection), `${collection} has a rule but is not writable`);
    }
  });

  it('nothing the client may write directly is also written here', () => {
    // The client-side list and this one must not overlap, or the same
    // collection has two write paths with two different sets of rules.
    const clientWritable = readFileSync(
      inRepo('lib/core/services/appwrite/appwrite_config.dart'),
      'utf8',
    );
    const block = clientWritable.split('clientWritableCollections = {')[1].split('};')[0];
    const names = [...block.matchAll(/AppConfig\.(\w+)/g)].map((m) => m[1]);
    assert.ok(names.length >= 5, 'did not find the client-writable list');

    const toCollection = {
      contactsCollection: 'contacts',
      messagesCollection: 'messages',
      trustedDevicesCollection: 'trusted_devices',
      loginHistoryCollection: 'login_history',
      ndpaConsentsCollection: 'ndpa_consents',
    };
    for (const name of names) {
      const collection = toCollection[name];
      assert.ok(collection, `unmapped collection constant: ${name}`);
      assert.ok(
        !WRITABLE.has(collection),
        `${collection} is client-writable AND Function-written — two sets of rules`,
      );
    }
  });

  it('no ACL names a label Appwrite will reject', () => {
    // Appwrite labels are alphanumeric only — no underscores, 36 chars.
    // Phase 7's migration already converts `tech_support` to
    // `techSupport`; the Functions' own ACLs did not, and the result was
    // every registration failing at the profile write with
    // "Role \"label\" identifier value is invalid".
    const sources = ['src/auth.js', 'src/lib/policy.js', 'src/write.js'];
    for (const file of sources) {
      const text = readFileSync(resolve(here, '..', file), 'utf8');
      for (const [, label] of text.matchAll(/label:([A-Za-z0-9_]+)/g)) {
        assert.match(
          label,
          /^[A-Za-z0-9]{1,36}$/,
          `${file} uses label "${label}" — alphanumeric only`,
        );
      }
    }
  });

  it('every Function-written collection has an ACL', () => {
    for (const collection of WRITABLE) {
      assert.ok(RULES[collection]?.acl, `${collection} would be written with no permissions`);
    }
  });
});

describe('the ward team id', () => {
  it('is the same shape the migration writes', () => {
    // The ACLs name a team. If this and `migrate/migrate.mjs` disagree by
    // one character, every migrated document points at a team nobody is
    // in and the whole ward sees nothing.
    assert.equal(wardTeam('Benue', 'Makurdi', 'North Bank I'),
      'ward-benue-makurdi-north-bank-i');
    assert.equal(wardTeam('Benue', 'Makurdi', 'Ankpa/Wadata'),
      'ward-benue-makurdi-ankpa-wadata');
  });

  it('shortens the ones that would not fit, and says so in the id', () => {
    // `ward-benue-makurdi-central-south-mission` is 40 characters, so
    // this one is shortened — a slug that runs to the cut plus a digest
    // of the whole name.
    const id = wardTeam('Benue', 'Makurdi', 'Central/South Mission');
    // At most 36 — a slug whose cut lands on a hyphen loses it, so some
    // are 35.
    assert.ok(id.length <= 36);
    assert.match(id, /^ward-benue-makurdi-[0-9a-f]{16}$/);
  });

  it('keeps the short ones exactly as Phase 0 verified them', () => {
    // 549 of the 584 fit, and those must not move: Phase 0's assertions,
    // the spike's teams and anything already designed around them all
    // name the plain slug.
    assert.equal(wardTeam('Benue', 'Makurdi', 'North Bank I'),
      'ward-benue-makurdi-north-bank-i');
  });

  it('is at most 36 characters, which is Appwrite\'s limit for a team id', () => {
    const locations = JSON.parse(
      readFileSync(LOCATIONS, 'utf8'),
    );
    const tooLong = [];
    for (const [state, lgas] of Object.entries(locations)) {
      for (const [lga, wards] of Object.entries(lgas)) {
        for (const ward of wards) {
          const id = wardTeam(state, lga, ward);
          if (id.length > 36) tooLong.push(`${id} (${id.length})`);
        }
      }
    }
    assert.deepEqual(tooLong, [], 'these ward team ids will be rejected by Appwrite');
  });

  it('gives all 584 wards a distinct id', () => {
    // Shortening to fit is only safe if it stays one-to-one: two wards
    // sharing a team id would show each other's reports.
    const locations = JSON.parse(
      readFileSync(LOCATIONS, 'utf8'),
    );
    const ids = new Set();
    let wards = 0;
    for (const [state, lgas] of Object.entries(locations)) {
      for (const [lga, names] of Object.entries(lgas)) {
        for (const ward of names) {
          wards += 1;
          ids.add(wardTeam(state, lga, ward));
        }
      }
    }
    assert.equal(wards, 584);
    assert.equal(ids.size, 584);
  });

  it('shortens deterministically, so a re-run writes the same id', () => {
    const long = ['Plateau', 'Langtang North', 'Langtang North Central'];
    assert.equal(wardTeam(...long), wardTeam(...long));
    assert.ok(wardTeam(...long).length <= 36);
  });
});

describe('location validation', () => {
  it('accepts a real ward', () => {
    assert.doesNotThrow(() =>
      assertLocation({ state: 'Benue', lga: 'Makurdi', ward: 'North Bank I' }));
  });

  it('refuses an invented ward, LGA and state in turn', () => {
    assert.throws(() => assertLocation({ state: 'Atlantis', lga: 'x', ward: 'y' }), /Unknown state/);
    assert.throws(() => assertLocation({ state: 'Benue', lga: 'Nowhere', ward: 'y' }), /Unknown LGA/);
    assert.throws(
      () => assertLocation({ state: 'Benue', lga: 'Makurdi', ward: 'Nowhere' }),
      /Unknown ward/,
    );
  });

  it('refuses a ward from the wrong LGA', () => {
    // The composite foreign key the dropped `nigeria_lgas` table enforced.
    assert.throws(
      () => assertLocation({ state: 'Benue', lga: 'Makurdi', ward: 'Gangare' }),
      /Unknown ward/,
    );
  });
});

describe('authority coverage', () => {
    it('accepts an LGA of the named state', () => {
        assert.doesNotThrow(() => assertCoverage({ coverageState: 'Benue', coverageLga: 'Makurdi' }));
        // Both halves of the ambiguous pair.
        assert.doesNotThrow(() => assertCoverage({ coverageState: 'Benue', coverageLga: 'Obi' }));
        assert.doesNotThrow(() => assertCoverage({ coverageState: 'Nasarawa', coverageLga: 'Obi' }));
    });

    it('refuses an LGA with no state', () => {
        // The `authorities_coverage_lga_needs_state` CHECK, carried over:
        // Appwrite has no CHECK and `coverageState` is not a required
        // column, so nothing but this stood between a contact and being
        // texted about the wrong Obi.
        assert.throws(() => assertCoverage({ coverageLga: 'Obi' }), /must name its state/);
        assert.throws(
            () => assertCoverage({ coverageState: '   ', coverageLga: 'Makurdi' }),
            /must name its state/,
        );
    });

    it('refuses a contact that covers nothing', () => {
        assert.throws(() => assertCoverage({}), /must cover an LGA/);
        assert.throws(() => assertCoverage({ coverageState: 'Benue' }), /must cover an LGA/);
    });

    it('refuses a state or LGA that is not on the list', () => {
        assert.throws(() => assertCoverage({ coverageState: 'Atlantis', coverageLga: 'Obi' }), /Unknown state/);
        // An LGA of a *different* state is the mistake the rule exists for.
        assert.throws(() => assertCoverage({ coverageState: 'Benue', coverageLga: 'Lafia' }), /Unknown LGA/);
    });

    it('is what the authorities rule asks for', () => {
        assert.equal(RULES.authorities.requiresCoverage, true);
        assert.ok(!RULES.authorities.requiresLocation);
    });
});

describe('alert targeting', () => {
    it('accepts an LGA of the named state', () => {
        assert.doesNotThrow(() => assertTarget({ targetState: 'Benue', targetLga: 'Makurdi' }));
    });

    it('accepts every LGA of a state', () => {
        for (const lga of ['All', 'all', '']) {
            assert.doesNotThrow(() => assertTarget({ targetState: 'Benue', targetLga: lga }), lga);
        }
    });

    it('accepts an alert with no target at all', () => {
        // "All LGAs", which is how a nationwide alert is stored.
        assert.doesNotThrow(() => assertTarget({ targetState: null, targetLga: 'All' }));
        assert.doesNotThrow(() => assertTarget({}));
    });

    it('refuses an LGA with no state', () => {
        // LGA names repeat across states — Obi is in Benue and in Nasarawa —
        // so one without a state reaches the wrong people or nobody. This is
        // the `alerts_target_lga_needs_state` check, carried over.
        assert.throws(() => assertTarget({ targetLga: 'Obi' }), /must name its state/);
    });

    it('refuses a state or LGA that is not on the list', () => {
        assert.throws(() => assertTarget({ targetState: 'Atlantis', targetLga: 'All' }), /Unknown state/);
        assert.throws(
            () => assertTarget({ targetState: 'Benue', targetLga: 'Nowhere' }),
            /Unknown LGA/,
        );
        // An LGA of a *different* state is the mistake the rule exists for.
        assert.throws(() => assertTarget({ targetState: 'Benue', targetLga: 'Lafia' }), /Unknown LGA/);
    });

    it('is what the alerts rule asks for', () => {
        // `requiresLocation` would send `assertLocation` looking for
        // `state`, `lga` and `ward`, which `alerts` does not have — that
        // refused every alert ever created.
        assert.equal(RULES.alerts.requiresTarget, true);
        assert.ok(!RULES.alerts.requiresLocation);
    });
});

describe('strip', () => {
  const rule = { serverOwned: ['status', 'userId'], immutable: ['ward'] };

  it('drops what the server owns and what Appwrite owns', () => {
    const out = strip(
      { $id: 'x', id: 'x', $createdAt: 't', status: 'approved', userId: 'them', title: 'ok' },
      rule,
      { keepImmutable: true },
    );
    assert.deepEqual(out, { title: 'ok' });
  });

  it('keeps immutable fields on create and drops them on update', () => {
    assert.deepEqual(
      strip({ ward: 'North Bank I' }, rule, { keepImmutable: true }),
      { ward: 'North Bank I' },
    );
    assert.deepEqual(strip({ ward: 'North Bank I' }, rule, { keepImmutable: false }), {});
  });
});
