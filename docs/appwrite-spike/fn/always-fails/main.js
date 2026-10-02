/** Fails every time, to find out whether Appwrite retries an event Function. */
export default async ({ req, res, log, error }) => {
  const evt = req.headers['x-appwrite-event'] ?? '(none)';
  log(`attempt at ${new Date().toISOString()} for ${evt}`);
  error('deliberate failure');
  throw new Error('deliberate failure');
};
