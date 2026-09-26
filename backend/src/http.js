// Outbound HTTP with a hard timeout so a hung upstream (OneSignal, Resend,
// Supabase) can never stall a worker loop forever.
export const HTTP_TIMEOUT_MS = 15_000;

/** Wraps a fetch so every request aborts after `timeoutMs` (combined with any caller signal). */
export function withTimeout(fetchImpl = globalThis.fetch, timeoutMs = HTTP_TIMEOUT_MS) {
  return (input, init = {}) => {
    const timeout = AbortSignal.timeout(timeoutMs);
    const signal = init.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return fetchImpl(input, { ...init, signal });
  };
}
