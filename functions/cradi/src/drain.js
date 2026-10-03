/**
 * The outbox drain: scheduled, every minute.
 *
 * This is what replaces the Railway worker's loop. Phase 6 watched a
 * scheduled Function fire on the minute, so the home is real — with one
 * caveat for self-hosting: it needs the `schedule-functions` and
 * `schedule-executions` services. A stack without them fires nothing and
 * looks exactly like "Appwrite cron does not work".
 *
 *   schedule: * * * * *
 *   scopes:   documents.read, documents.write, users.write, messages.write
 */
import { getSettings } from './lib/settings.js';
import { handler } from './lib/http.js';
import { createHandlers } from './lib/handlers.js';
import {
  BATCH_SIZE,
  PermanentEventError,
  claim,
  markFailed,
  markProcessed,
  payloadOf,
} from './lib/outbox.js';
import { notifyApproved, termiiSender } from './lib/termii.js';

/**
 * A run must finish inside its schedule, or the next one starts while
 * this one is still going — which is survivable (see `outbox.js` on the
 * missing atomic claim) but wastes the budget twice. The batch is capped
 * and the clock is watched.
 */
const RUN_BUDGET_MS = 45_000;

/**
 * The body of this Function, exported so `worker.js` can run it beside
 * the others. The plan allows two Functions and this design has seven,
 * so the three scheduled ones share one entrypoint — see `worker.js`.
 */
export async function runDrain({ log, error }) {
  const started = Date.now();
  const settings = await getSettings();
  const sms = smsSender(log);
  const handlers = createHandlers({ settings, sms, log });

  const events = await claim(BATCH_SIZE);
  const summary = { claimed: events.length, processed: 0, failed: 0, left: 0 };

  for (const [i, event] of events.entries()) {
    if (Date.now() - started > RUN_BUDGET_MS) {
      // Leaving the rest is safe: a claimed document comes back when its
      // backoff expires, which is the same property the Railway worker
      // relied on when it was shut down mid-batch.
      summary.left = events.length - i;
      log(`drain: out of budget, ${summary.left} left for the next run`);
      break;
    }
    const outcome = await processOne(event, handlers, { log, error });
    summary[outcome] += 1;
  }

  if (summary.claimed) log(`drain ${JSON.stringify(summary)}`);
  return summary;
}

export default handler(runDrain);

/** Processes one claimed event and records the outcome. Never throws. */
export async function processOne(event, handlers, { log = () => {}, error = () => {} } = {}) {
  const run = Object.hasOwn(handlers, event.eventType)
    ? handlers[event.eventType]
    : null;
  try {
    if (!run) {
      // An unknown type is marked processed, not retried: nothing about
      // waiting will teach this deployment what it means, and leaving it
      // due would make it the head of the queue forever.
      log(`drain: unknown event type ${event.eventType}`);
      await markProcessed(event.$id, 'unknown event');
      return 'processed';
    }
    const note = await run(event, payloadOf(event));
    await markProcessed(event.$id, note ?? null);
    return 'processed';
  } catch (e) {
    if (e instanceof PermanentEventError) {
      log(`drain: permanent failure on ${event.$id}: ${e.message}`);
      await safe(() => markProcessed(event.$id, e.message), error, event.$id);
      return 'processed';
    }
    error(`drain: ${event.eventType} ${event.$id} attempt ${event.attempts}: ${e?.message ?? e}`);
    await safe(() => markFailed(event.$id, e?.message ?? String(e)), error, event.$id);
    return 'failed';
  }
}

async function safe(fn, error, id) {
  try {
    await fn();
  } catch (e) {
    // The claim already pushed availableAt forward, so a failed
    // bookkeeping write costs a retry, not a stuck document.
    error(`drain: bookkeeping failed for ${id}: ${e?.message ?? e}`);
  }
}

/** Null when Termii is not configured, which turns SMS off rather than failing. */
function smsSender(log) {
  const apiKey = process.env.TERMII_API_KEY;
  const senderId = process.env.TERMII_SENDER_ID;
  if (!apiKey || !senderId) return null;
  const send = termiiSender({ apiKey, senderId });
  return (report, settings) => notifyApproved(report, { settings, send, log });
}
