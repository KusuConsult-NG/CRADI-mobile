// Environment configuration. Parsing is pure so it can be unit-tested.

const REQUIRED = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];

function intOr(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(value) {
  const s = typeof value === 'string' ? value.trim() : '';
  return s.length ? s : undefined;
}

/** True when SMS_PROVIDER names a provider whose credentials are all set. */
export function smsConfigured(config) {
  if (config.smsProvider === 'termii') return Boolean(config.termiiApiKey && config.smsSenderId);
  if (config.smsProvider === 'twilio') return Boolean(config.twilioAccountSid && config.twilioAuthToken && config.twilioFrom);
  return false;
}

export function loadConfig(env = process.env) {
  const config = {
    supabaseUrl: str(env.SUPABASE_URL),
    supabaseServiceRoleKey: str(env.SUPABASE_SERVICE_ROLE_KEY),
    oneSignalAppId: str(env.ONESIGNAL_APP_ID),
    oneSignalRestApiKey: str(env.ONESIGNAL_REST_API_KEY),
    oneSignalAndroidChannelId: str(env.ONESIGNAL_ANDROID_CHANNEL_ID),
    resendApiKey: str(env.RESEND_API_KEY),
    fromEmail: str(env.FROM_EMAIL) ?? 'noreply@cradi.ng',
    fromName: str(env.FROM_NAME) ?? 'EWER Alert System',
    smsProvider: str(env.SMS_PROVIDER)?.toLowerCase(),
    termiiApiKey: str(env.TERMII_API_KEY),
    smsSenderId: str(env.SMS_SENDER_ID),
    twilioAccountSid: str(env.TWILIO_ACCOUNT_SID),
    twilioAuthToken: str(env.TWILIO_AUTH_TOKEN),
    twilioFrom: str(env.TWILIO_FROM),
    port: intOr(env.PORT, 8080),
    workerPollMs: intOr(env.WORKER_POLL_MS, 5000),
    escalationPollMs: intOr(env.ESCALATION_POLL_MS, 60000),
    corsOrigins: (env.CORS_ORIGINS ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  };

  const warnings = [];
  // OneSignal rejects every push that names an unknown channel id, so a typo
  // here would silently break all Android pushes. Ignore it instead.
  if (config.oneSignalAndroidChannelId && !UUID_RE.test(config.oneSignalAndroidChannelId)) {
    warnings.push({
      event: 'config.onesignal_channel_invalid',
      hint: 'ONESIGNAL_ANDROID_CHANNEL_ID is not a UUID; it is ignored and pushes use the default channel.',
    });
    config.oneSignalAndroidChannelId = undefined;
  }

  const missing = REQUIRED.filter((k) => !str(env[k]));
  const status = {
    supabase: Boolean(config.supabaseUrl && config.supabaseServiceRoleKey),
    onesignal: Boolean(config.oneSignalAppId && config.oneSignalRestApiKey),
    resend: Boolean(config.resendApiKey),
    sms: smsConfigured(config),
  };
  return { config, missing, status, warnings };
}
