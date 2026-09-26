// Entry point: wires config, Supabase, OneSignal, Resend, the outbox worker,
// the escalation cron and the HTTP API.
import { createClient } from '@supabase/supabase-js';
import { loadConfig } from './config.js';
import { createEmailHandler, createRateLimiter, createResendSender } from './email/service.js';
import { runEscalations } from './escalations.js';
import { log } from './log.js';
import { withTimeout } from './http.js';
import { loopHealth, startLoop } from './loop.js';
import { createOneSignal } from './onesignal.js';
import { BATCH_SIZE, createHandlers, runOutboxBatch } from './outbox.js';
import { createRepo } from './repo.js';
import { createAuthoritySms } from './sms/authorities.js';
import { createSmsProvider } from './sms/providers.js';
import { createHttpServer } from './server.js';

const { config, missing, status, warnings } = loadConfig();
for (const w of warnings) log.warn(w.event, { hint: w.hint });

if (missing.length) {
  log.error('config.missing_required', {
    missing,
    hint: 'Set these in Railway > service > Variables. Worker, cron and /email are disabled; /health reports unhealthy.',
  });
}
if (!status.onesignal) log.warn('config.onesignal_missing', { hint: 'ONESIGNAL_APP_ID / ONESIGNAL_REST_API_KEY unset; pushes are skipped.' });
if (!status.sms) {
  log.warn('config.sms_missing', {
    provider: config.smsProvider ?? null,
    hint: "SMS_PROVIDER unset/unknown or its credentials incomplete ('termii': TERMII_API_KEY + SMS_SENDER_ID; 'twilio': TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM); authority SMS are skipped.",
  });
}
if (!status.resend) log.warn('config.resend_missing', { hint: 'RESEND_API_KEY unset; POST /email returns 503.' });

const supabase = status.supabase
  ? createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: withTimeout() },
    })
  : null;
const repo = supabase ? createRepo(supabase) : null;

const push = createOneSignal({
  appId: config.oneSignalAppId,
  apiKey: config.oneSignalRestApiKey,
  androidChannelId: config.oneSignalAndroidChannelId,
});

const loops = [];
if (repo) {
  const authoritySms = createAuthoritySms({ repo, sms: createSmsProvider(config) });
  const handlers = createHandlers({ repo, push, authoritySms });
  loops.push(
    startLoop(
      'outbox',
      async ({ isStopped }) =>
        (await runOutboxBatch({ repo, handlers, limit: BATCH_SIZE, shouldStop: isStopped })) >= BATCH_SIZE,
      config.workerPollMs,
    ),
    startLoop('escalations', async () => void (await runEscalations({ repo, push })), config.escalationPollMs),
  );
}

const limiter = createRateLimiter();
setInterval(() => limiter.sweep(), 10 * 60_000).unref();

const handleEmail = repo
  ? createEmailHandler({
      verifyToken: async (token) => {
        const { data, error } = await supabase.auth.getUser(token);
        if (error) return null;
        return data?.user ?? null;
      },
      getProfile: (id) => repo.getProfile(id),
      sendEmail: status.resend
        ? createResendSender({ apiKey: config.resendApiKey, fromEmail: config.fromEmail, fromName: config.fromName })
        : null,
      limiter,
    })
  : async () => ({ status: 503, body: { success: false, error: 'Service not configured' } });

function health() {
  const ok = missing.length === 0;
  return {
    status: ok ? 200 : 503,
    body: {
      ok,
      config: { ...status },
      workers: Object.fromEntries(
        loops.map((l) => [l.state.name, loopHealth(l.state)]),
      ),
    },
  };
}

const server = createHttpServer({ health, handleEmail, corsOrigins: config.corsOrigins });
server.listen(config.port, () => {
  log.info('server.listening', { port: config.port, config: status, workerPollMs: config.workerPollMs, escalationPollMs: config.escalationPollMs });
});

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info('server.shutdown', { signal });
  server.close();
  const force = setTimeout(() => process.exit(0), 10_000);
  force.unref();
  await Promise.allSettled(loops.map((l) => l.stop()));
  process.exit(0);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('unhandledRejection', (err) => log.error('process.unhandled_rejection', { error: String(err?.message ?? err) }));
