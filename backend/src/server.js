import { createServer } from 'node:http';
import { errMessage, log as defaultLog } from './log.js';

export const MAX_BODY_BYTES = 64 * 1024;

export function corsHeadersFor(origin, allowed) {
  if (!origin || !allowed?.length) return {};
  if (allowed.includes('*')) return { 'Access-Control-Allow-Origin': '*' };
  if (allowed.includes(origin)) return { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' };
  return {};
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('Payload too large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function send(res, status, body, headers = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    ...headers,
    ...(payload ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(payload);
}

/**
 * deps: { health() -> { status, body }, handleEmail({authorization, body}) -> { status, body }, corsOrigins, logger }
 */
export function createHttpServer({ health, handleEmail, corsOrigins = [], logger = defaultLog }) {
  return createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const cors = corsHeadersFor(req.headers.origin, corsOrigins);
    try {
      if (url.pathname === '/health' || url.pathname === '/') {
        if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, { success: false, error: 'Method not allowed' });
        const h = health();
        return send(res, h.status, req.method === 'HEAD' ? undefined : h.body);
      }

      if (url.pathname === '/email') {
        if (req.method === 'OPTIONS') {
          return send(res, 204, undefined, {
            ...cors,
            ...(cors['Access-Control-Allow-Origin']
              ? {
                  'Access-Control-Allow-Methods': 'POST, OPTIONS',
                  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
                  'Access-Control-Max-Age': '3600',
                }
              : {}),
          });
        }
        if (req.method !== 'POST') return send(res, 405, { success: false, error: 'Method not allowed' }, cors);

        let body;
        try {
          const raw = await readBody(req);
          body = raw ? JSON.parse(raw) : {};
        } catch (err) {
          const status = err?.status === 413 ? 413 : 400;
          return send(res, status, { success: false, error: status === 413 ? 'Payload too large' : 'Invalid JSON' }, cors);
        }
        const result = await handleEmail({ authorization: req.headers.authorization, body });
        return send(res, result.status, result.body, cors);
      }

      return send(res, 404, { success: false, error: 'Not found' }, cors);
    } catch (err) {
      logger.error('http.unhandled', { path: url.pathname, error: errMessage(err) });
      if (!res.headersSent) send(res, 500, { success: false, error: 'Internal error' }, cors);
      else res.end();
    }
  });
}
