/**
 * Everything the server runs on its own, behind one Function.
 *
 * ## Why this exists
 *
 * `on-write` (events), `drain` (every minute), `escalate` (every
 * minute) and `reconcile` (every five) are four Functions, and the
 * Cloud plan allows two in total against the seven this backend needs
 * (3 October 2026; see `docs/CLOUD-VERIFICATION.md`). The three
 * client-facing ones are in `client.js`; these four are here.
 *
 * ## Which one runs
 *
 * A Function may carry both `events` and a `schedule`, so the trigger
 * decides:
 *
 *   an event        → `on-write`, and nothing else
 *   a schedule/HTTP → the drain, then escalation, then — on every
 *                     fifth minute — the reconciling sweep
 *
 * Read from `x-appwrite-event`, which Appwrite sets only for an event
 * delivery, rather than from `x-appwrite-trigger`: a manual run for a
 * test is `http` and must do the scheduled work, and treating anything
 * that is not an event as a tick gets that right without a third case.
 *
 * ## The cadence
 *
 * One schedule, so the Function runs every minute and the sweep checks
 * the clock. `*(slash)5` became `minute % 5`, which keeps the original
 * cadence; running it more often would only cost reads, since the
 * sweep is idempotent by construction (outbox ids are deterministic).
 *
 * ## Order, and why one failure does not stop the rest
 *
 * The drain delivers what is queued, escalation queues what is overdue,
 * and the sweep repairs what was lost — so an escalation queued this
 * minute is delivered next minute, exactly as it was when these were
 * three Functions on their own schedules.
 *
 * Each is run independently and a thrown one is recorded rather than
 * raised. They were separate Functions a minute ago: a crash in the
 * sweep never stopped the drain, and it must not start now. The
 * response carries each one's summary or its error, so a run that
 * half-worked says so instead of looking like a clean failure.
 */
import onWrite from './on-write.js';
import { runDrain } from './drain.js';
import { runEscalate } from './escalate.js';
import { runReconcile } from './reconcile.js';

/** Minutes between reconciling sweeps, as its own cron said. */
export const RECONCILE_EVERY_MINUTES = 5;

export const isSweepMinute = (date = new Date()) =>
  date.getUTCMinutes() % RECONCILE_EVERY_MINUTES === 0;

/** The scheduled work for this tick, in the order it has to happen. */
export function tasksFor(date = new Date()) {
  const tasks = [
    ['drain', runDrain],
    ['escalate', runEscalate],
  ];
  if (isSweepMinute(date)) tasks.push(['reconcile', runReconcile]);
  return tasks;
}

export default async (context) => {
  const { req, res, log, error } = context;

  if (req.headers['x-appwrite-event']) return onWrite(context);

  const summary = {};
  let failed = 0;
  for (const [name, run] of tasksFor()) {
    try {
      summary[name] = (await run({ log, error })) ?? {};
    } catch (e) {
      // Not rethrown: these were four Functions a minute ago and a
      // crash in one never stopped the others. Recorded so a run that
      // half-worked cannot read as a clean one.
      failed += 1;
      summary[name] = { failed: true, error: String(e?.message ?? e) };
      error(`worker: ${name} threw: ${e?.stack ?? e}`);
    }
  }

  log(`worker ${JSON.stringify(summary)}`);
  // 500 when something threw, so a failing tick is visible in the
  // execution list rather than only in the logs.
  return res.json(summary, failed ? 500 : 200);
};
