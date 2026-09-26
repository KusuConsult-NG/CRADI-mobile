// Minimal structured logger (one JSON line per entry; Railway indexes these).
function write(level, msg, fields) {
  const line = JSON.stringify({ level, time: new Date().toISOString(), msg, ...fields });
  if (level === 'error' || level === 'warn') console.error(line);
  else console.log(line);
}

export const log = {
  info: (msg, fields = {}) => write('info', msg, fields),
  warn: (msg, fields = {}) => write('warn', msg, fields),
  error: (msg, fields = {}) => write('error', msg, fields),
};

export const silentLog = { info() {}, warn() {}, error() {} };

export function errMessage(err) {
  return err instanceof Error ? err.message : String(err);
}
