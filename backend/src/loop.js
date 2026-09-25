import { errMessage, log as defaultLog } from './log.js';

/**
 * Runs `task` repeatedly, never overlapping. `task` may return true to run
 * again immediately (e.g. a full outbox batch), otherwise waits `intervalMs`.
 */
export function startLoop(name, task, intervalMs, { logger = defaultLog } = {}) {
  const state = { name, lastRunAt: null, lastSuccessAt: null, lastError: null, running: false };
  let timer = null;
  let stopped = false;
  let current = Promise.resolve();

  async function tick() {
    if (stopped) return;
    state.running = true;
    let again = false;
    try {
      again = (await task()) === true;
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
