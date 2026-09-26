// Stopping a run cleanly. A killed --apply run must still save the state file
// and neutralise the side effects of what it already wrote, so SIGINT/SIGTERM
// ask the run to stop and then run the same (memoised) finish step as the
// runner's `finally` block: it runs exactly once whichever path gets there
// first.

export const SIGNAL_EXIT_CODES = { SIGINT: 130, SIGTERM: 143 };

export class StopRequested extends Error {
  constructor(signal) {
    super(`stopped by ${signal}`);
    this.signal = signal;
  }
}

/** Wrap an async function so every call after the first returns the first call's promise. */
export function onceAsync(fn) {
  let promise = null;
  const wrapped = () => {
    promise ??= Promise.resolve().then(fn);
    return promise;
  };
  Object.defineProperty(wrapped, 'started', { get: () => promise !== null });
  return wrapped;
}

/** A promise with its resolve function exposed. */
export function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
}

/**
 * On SIGINT/SIGTERM: set `stop.signal` (write loops check it via
 * throwIfStopped and unwind), wait up to `graceMs` for the runner to reach its
 * `finally` (`unwound`), run `finish` (shared with that `finally`), then exit
 * with 130/143. A second signal exits at once.
 * Returns a function that removes the handlers.
 */
export function installStopHandlers({
  stop, finish, unwound, graceMs = 30_000, proc = process, exit = (code) => proc.exit(code), log = console.error,
}) {
  const handler = async (signal) => {
    if (stop.signal) {
      log(`\n${signal} again: exiting now. Re-run with --apply to neutralise the remaining side effects.`);
      exit(SIGNAL_EXIT_CODES[signal] ?? 1);
      return;
    }
    stop.signal = signal;
    log(`\n${signal} received: stopping after the current request, then saving state and neutralising side effects (press again to exit now)…`);
    let timer;
    const grace = new Promise((r) => { timer = setTimeout(r, graceMs); });
    await Promise.race([unwound, grace]);
    clearTimeout(timer);
    try {
      await finish();
    } catch (e) {
      log(`!! Cleanup after ${signal} failed: ${e.message}. Re-run with --apply to neutralise side effects.`);
    }
    exit(SIGNAL_EXIT_CODES[signal] ?? 1);
  };
  const signals = Object.keys(SIGNAL_EXIT_CODES);
  signals.forEach((s) => proc.on(s, handler));
  return () => signals.forEach((s) => proc.off(s, handler));
}

/** Throw StopRequested once a signal asked the run to stop. */
export function throwIfStopped(stop) {
  if (stop.signal) throw new StopRequested(stop.signal);
}
