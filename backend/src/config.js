// Environment configuration. Parsing is pure so it can be unit-tested.

const REQUIRED = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];

function intOr(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

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

  const missing = REQUIRED.filter((k) => !str(env[k]));
  const status = {
    supabase: Boolean(config.supabaseUrl && config.supabaseServiceRoleKey),
    onesignal: Boolean(config.oneSignalAppId && config.oneSignalRestApiKey),
    resend: Boolean(config.resendApiKey),
    sms: smsConfigured(config),
  };
  return { config, missing, status };
}
