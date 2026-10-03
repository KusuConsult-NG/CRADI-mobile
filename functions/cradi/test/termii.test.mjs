import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  SMS_TIMEOUT_MS,
  authoritySmsText,
  isPermanentSmsError,
  isSmsAccountError,
  normalisePhone,
  smsBudget,
  termiiSender,
} from '../src/lib/termii.js';

/**
 * The SMS module had no unit tests, which is how a port of a working
 * Railway worker lost the one thing its author had written a comment
 * about: Termii wants the recipient as bare digits, and the port sent
 * `+234…`. The stand-in in `e2e-sms.mjs` could not catch it, because it
 * was written from the same assumption as the sender.
 */

/** Captures what the sender would have sent, and answers with [response]. */
function capture(response = { ok: true, body: { message_id: 'm1' } }) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return {
      ok: response.ok,
      status: response.status ?? (response.ok ? 200 : 400),
      json: async () => response.body,
    };
  };
  return { calls, fetchImpl };
}

describe('the Termii payload', () => {
  it('sends the number without its +, which is what Termii accepts', async () => {
    const { calls, fetchImpl } = capture();
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await send('+2348031234567', 'hello');

    assert.equal(calls[0].body.to, '2348031234567');
    assert.ok(!String(calls[0].body.to).includes('+'));
  });

  it('is the shape the provider documents', async () => {
    const { calls, fetchImpl } = capture();
    const send = await termiiSender({ apiKey: 'secret', senderId: 'EWER', fetchImpl });
    const id = await send('+2348031234567', 'hello');

    assert.equal(id, 'm1');
    assert.match(calls[0].url, /\/api\/sms\/send$/);
    assert.equal(calls[0].init.method, 'POST');
    assert.deepEqual(calls[0].body, {
      to: '2348031234567',
      from: 'EWER',
      sms: 'hello',
      type: 'plain',
      channel: 'generic',
      api_key: 'secret',
    });
  });

  it('gives up rather than holding the whole drain open', async () => {
    const { calls, fetchImpl } = capture();
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await send('+2348031234567', 'hello');

    // `fetch` has no default timeout, and the drain is a scheduled
    // Function with a budget: one hung socket would take every other
    // queued notification down with it.
    assert.ok(calls[0].init.signal, 'no abort signal');
    assert.equal(SMS_TIMEOUT_MS, 15_000);
  });
});

describe('what Termii calls a failure', () => {
  it('treats a 200 carrying an error as a failure, not a send', async () => {
    // Termii answers 200 with `code: 'error'` as often as it answers a
    // 4xx. A 200 that did not send must not be recorded as sent.
    const { fetchImpl } = capture({
      ok: true,
      body: { code: 'error', message: 'Invalid phone number' },
    });
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await assert.rejects(send('+2348031234567', 'hi'), (e) => {
      assert.match(e.message, /Invalid phone number/);
      assert.equal(e.status, 400, 'classified as the refusal it is');
      return true;
    });
  });

  it('treats a 200 with no message id as a failure', async () => {
    const { fetchImpl } = capture({ ok: true, body: { balance: 3 } });
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await assert.rejects(send('+2348031234567', 'hi'));
  });

  it('carries the status through, so the caller can tell what kind it is', async () => {
    const { fetchImpl } = capture({
      ok: false,
      status: 402,
      body: { message: 'Insufficient balance' },
    });
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await assert.rejects(send('+2348031234567', 'hi'), (e) => {
      assert.equal(e.status, 402);
      return true;
    });
  });

  it('a dead socket has no status, so nothing can call it permanent', async () => {
    const fetchImpl = async () => {
      throw new Error('The operation was aborted due to timeout');
    };
    const send = await termiiSender({ apiKey: 'k', senderId: 'EWER', fetchImpl });
    await assert.rejects(send('+2348031234567', 'hi'), (e) => {
      assert.equal(e.status, undefined);
      assert.equal(isPermanentSmsError(e), false);
      return true;
    });
  });
});

describe('which failures are the number\'s fault', () => {
  const refusal = (status, detail) => Object.assign(new Error(detail), { status, detail });

  it('a refused number is permanent: retrying fails the same way forever', () => {
    for (const detail of [
      'Invalid phone number',
      'invalid destination',
      'Number blacklisted',
      'Recipient is on DND',
      'do-not-disturb',
    ]) {
      assert.equal(isPermanentSmsError(refusal(400, detail)), true, detail);
    }
  });

  it('an unpaid or misconfigured account is NOT permanent', () => {
    // The failure this rule exists for. Termii says "Invalid API key"
    // with a 401, and a substring match on `invalid` would mark every
    // authority in an LGA `rejected` over an unpaid bill — after which
    // nothing retries them, ever.
    for (const status of [401, 402, 403]) {
      const e = refusal(status, 'Invalid API key');
      assert.equal(isSmsAccountError(e), true, String(status));
      assert.equal(isPermanentSmsError(e), false, String(status));
    }
  });

  it('a rate limit or a timeout is not permanent', () => {
    assert.equal(isPermanentSmsError(refusal(429, 'Too many requests')), false);
    assert.equal(isPermanentSmsError(refusal(408, 'Request timeout')), false);
  });

  it('an outage is not permanent', () => {
    assert.equal(isPermanentSmsError(refusal(500, 'Invalid phone number')), false);
    assert.equal(isPermanentSmsError(refusal(503, 'Service unavailable')), false);
  });

  it('an unexplained 4xx is not permanent either', () => {
    assert.equal(isPermanentSmsError(refusal(400, 'Something went wrong')), false);
  });
});

describe('the message a local authority receives', () => {
  const report = {
    hazardType: 'Flooding',
    severity: 'high',
    ward: 'North Bank I',
    lga: 'Makurdi',
    description: 'River over the road at the market end.',
  };

  it('names the hazard, the severity and where', () => {
    const text = authoritySmsText(report);
    assert.equal(
      text,
      'EWER ALERT: HIGH Flooding reported in North Bank I, Makurdi. ' +
        'River over the road at the market end. - verified by community monitors.',
    );
  });

  it('never exceeds the segment budget, and keeps the ending', () => {
    const text = authoritySmsText({ ...report, description: 'x'.repeat(1000) });
    assert.ok(text.length <= 320, `length ${text.length}`);
    assert.match(text, / - verified by community monitors\.$/);
    assert.match(text, /^EWER ALERT: HIGH Flooding reported in North Bank I, Makurdi\./);
  });

  it('shortens the description before it drops the ending', () => {
    // The description is what gives way, with an ellipsis so the reader
    // can see it was cut; the hazard, the place and the provenance are
    // the parts an authority acts on and they survive.
    const text = authoritySmsText({ ...report, ward: 'North Bank I'.padEnd(230, 'x') });
    assert.equal(text.length, 320);
    assert.match(text, / - verified by community monitors\.$/);
    assert.match(text, /\.\.\. - verified/, 'the description was cut, visibly');
  });

  it('honours the cap even when the place alone overruns it', () => {
    // A hard slice, ending mid-word. Nigeria has no 200-character ward
    // name, so this is about the cap being a cap: a message over 320
    // is billed as extra segments, which is a cost the budget counts in
    // messages.
    const text = authoritySmsText({ ...report, ward: 'W'.repeat(200), lga: 'L'.repeat(60) });
    assert.equal(text.length, 320);
  });
});

describe('phone numbers', () => {
  it('reads the spellings a Nigerian contact is stored in', () => {
    for (const [raw, expected] of [
      ['08031234567', '+2348031234567'],
      ['+234 803 123 4567', '+2348031234567'],
      ['2348031234567', '+2348031234567'],
      ['8031234567', '+2348031234567'],
      ['+234 (0)803 123 4567', '+2348031234567'],
      ['002348031234567', '+2348031234567'],
      ['803-123-4567', '+2348031234567'],
    ]) {
      assert.equal(normalisePhone(raw), expected, raw);
    }
  });

  it('refuses what is not a number rather than texting it', () => {
    for (const raw of [
      '',
      '12345',
      'not a phone',
      null,
      undefined,
      '+2349', // too short — the old port passed this straight through
      '+234803123456789', // too long
      '+15551234567', // another country
      '+2340031234567', // no subscriber number starts with 0
    ]) {
      assert.equal(normalisePhone(raw), null, String(raw));
    }
  });
});

describe('the caps', () => {
  it('defaults to the documented budget', () => {
    assert.deepEqual(smsBudget({}), { perEvent: 20, perLgaDay: 50 });
  });

  it('reads the stored strings, because app_settings.value is a string column', () => {
    assert.deepEqual(
      smsBudget({ max_sms_per_alert_event: '2', max_sms_per_lga_per_day: '7' }),
      { perEvent: 2, perLgaDay: 7 },
    );
  });

  it('falls back rather than letting a bad value mean "no messages"', () => {
    assert.deepEqual(smsBudget({ max_sms_per_alert_event: '0', max_sms_per_lga_per_day: 'x' }), {
      perEvent: 20,
      perLgaDay: 50,
    });
  });
});
