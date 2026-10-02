import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { escalationTimeoutMinutes, positiveInt } from '../src/lib/settings.js';
import { smsBudget } from '../src/lib/termii.js';

/**
 * `app_settings` keys are row *values* in the `key` column, not column
 * names — so the camel/snake translation the rest of the migration did
 * does not apply to them, and reading one under the wrong spelling finds
 * nothing and falls back silently. Nothing failed, the admin panel's
 * setting simply did nothing. These tests pin the spellings against the
 * ones Postgres used and the panel still writes.
 */
describe('app_settings keys', () => {
    it('reads the escalation timeout under its stored key', () => {
        assert.equal(escalationTimeoutMinutes({ escalation_timeout_minutes: '45' }), 45);
    });

    it('defaults to 30 minutes, as Postgres did', () => {
        assert.equal(escalationTimeoutMinutes({}), 30);
    });

    it('does not answer to the camelCase spelling', () => {
        // The bug: this is what the Function read, so the stored value was
        // never seen and every report escalated on the fallback.
        assert.equal(escalationTimeoutMinutes({ escalationTimeoutMinutes: '45' }), 30);
    });

    it('falls back on a value that is not a positive integer', () => {
        for (const value of ['0', '-5', 'soon', '', null, undefined]) {
            assert.equal(escalationTimeoutMinutes({ escalation_timeout_minutes: value }), 30, String(value));
        }
    });

    it('reads both SMS budgets under their stored keys', () => {
        const budget = smsBudget({
            max_sms_per_alert_event: '7',
            max_sms_per_lga_per_day: '9',
        });
        assert.equal(budget.perEvent, 7);
        assert.equal(budget.perLgaDay, 9);
    });

    it('defaults the SMS budgets when the keys are absent', () => {
        const budget = smsBudget({});
        assert.equal(budget.perEvent, 20);
        assert.equal(budget.perLgaDay, 50);
    });
});

describe('positiveInt', () => {
    it('takes a positive integer and nothing else', () => {
        assert.equal(positiveInt('12', 3), 12);
        assert.equal(positiveInt('0', 3), 3);
        assert.equal(positiveInt('-1', 3), 3);
        assert.equal(positiveInt('x', 3), 3);
        assert.equal(positiveInt(undefined, 3), 3);
    });
});
