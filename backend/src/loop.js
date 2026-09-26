import { errMessage, log as defaultLog } from './log.js';

export const STALE_INTERVALS = 5;

/**
 * Health of a loop for /health. A loop is unhealthy if its last tick failed or
 * if it has not completed a tick for more than STALE_INTERVALS × its interval
 * (e.g. a tick hung on a request, or the timer chain died).
 */
export function loopHealth(state, now = Date.now()) {
  const last = Date.parse(state.lastRunAt ?? state.startedAt);
  const stale = !Number.isFinite(last) || now - last > STALE_INTERVALS * state.intervalMs;
  return {
    lastRunAt: state.lastRunAt,
    lastSuccessAt: state.lastSuccessAt,
    stale,
    healthy: !state.lastError && !stale,
  };
}

/**
 * Runs `task` repeatedly, never overlapping. `task` may return true to run
 * again immediately (e.g. a full outbox batch), otherwise waits `intervalMs`.
 * `task` receives { isStopped }: a long task should check it between units of
 * work so stop() resolves quickly on shutdown.
 */
export function startLoop(name, task, intervalMs, { logger = defaultLog } = {}) {
  const state = {
    name,
    intervalMs,
    startedAt: new Date().toISOString(),
    lastRunAt: null,
    lastSuccessAt: null,
    lastError: null,
    running: false,
  };
  let timer = null;
  let stopped = false;
  let current = Promise.resolve();
  const ctx = { isStopped: () => stopped };

  async function tick() {
    if (stopped) return;
    state.running = true;
    let again = false;
    try {
      again = (await task(ctx)) === true;
      state.lastSuccessAt = new Date().toISOString();
      state.lastError = null;
    } catch (err) {
      state.lastError = errMessage(err);
      logger.error(`${name}.tick_failed`, { error: state.lastError });
    } finally {
      state.lastRunAt = new Date().toISOString();
      state.running = false;
    }
    if (!stopped) timer = setTimeout(run, again ? 0 : intervalMs);
  }

  function run() {
    current = tick();
  }

  timer = setTimeout(run, 0);

  return {
    state,
    async stop() {
      stopped = true;
      if (timer) clearTimeout(timer);
      await current;
    },
  };
}
