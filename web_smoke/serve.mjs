// TEST HARNESS ONLY — static file server for build/web.
// `python3 -m http.server` does not always know application/wasm, which the
// Flutter bootstrap needs.
import http from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] || 'build/web');
const PORT = Number(process.env.WEB_PORT || 8080);

const TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.wasm': 'application/wasm',
    '.css': 'text/css; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.bin': 'application/octet-stream',
    '.symbols': 'text/plain; charset=utf-8',
};

http.createServer((req, res) => {
    const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    let file = path.join(ROOT, urlPath);
    if (!file.startsWith(ROOT)) {
        res.writeHead(403).end();
        return;
    }
    try {
        if (statSync(file).isDirectory()) file = path.join(file, 'index.html');
    } catch {
        file = path.join(ROOT, 'index.html'); // SPA fallback
    }
    let stat;
    try {
        stat = statSync(file);
    } catch {
        res.writeHead(404).end('not found');
        return;
    }
    res.writeHead(200, {
        'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
        'Content-Length': stat.size,
        'Cache-Control': 'no-store',
        // CanvasKit / skwasm want a cross-origin isolated context for threads;
        // not required, but keeps the console clean.
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'credentialless',
    });
    createReadStream(file).pipe(res);
}).listen(PORT, '127.0.0.1', () => console.log(`[serve] http://127.0.0.1:${PORT} → ${ROOT}`));
