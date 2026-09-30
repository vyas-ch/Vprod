import http from 'node:http';
import { createReadStream } from 'node:fs';
import { stat, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const types = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.svg':'image/svg+xml', '.webp':'image/webp', '.png':'image/png', '.ico':'image/x-icon', '.mp4':'video/mp4', '.webm':'video/webm', '.txt':'text/plain; charset=utf-8', '.xml':'application/xml; charset=utf-8', '.woff2':'font/woff2' };
const security = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; font-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'none'",
  'X-Content-Type-Options':'nosniff',
  'Referrer-Policy':'strict-origin-when-cross-origin',
  'Permissions-Policy':'camera=(), microphone=(), geolocation=()',
  'X-Frame-Options':'DENY'
};

export function createServer(publicRoot = path.join(here, 'public')) {
  const root = path.resolve(publicRoot);
  const canonicalRoot = realpath(root);
  return http.createServer(async (req, res) => {
    for (const [key, value] of Object.entries(security)) res.setHeader(key, value);
    function fail(code, text) { res.writeHead(code, { 'Content-Type':'text/plain; charset=utf-8', 'Cache-Control':'no-store' }); res.end(req.method === 'HEAD' ? undefined : text); }
    if (!['GET', 'HEAD'].includes(req.method)) { res.setHeader('Allow', 'GET, HEAD'); return fail(405, 'Methode niet toegestaan.'); }
    let pathname;
    try { pathname = decodeURIComponent((req.url || '/').split('?')[0]); } catch { return fail(400, 'Ongeldig verzoek.'); }
    if (!pathname.startsWith('/') || pathname.includes('\\') || pathname.includes('\0') || pathname.split('/').some(part => part.startsWith('.'))) return fail(404, 'Niet gevonden.');
    if (pathname === '/') pathname = '/index.html';
    const filename = path.resolve(root, '.' + pathname);
    if (!filename.startsWith(root + path.sep)) return fail(404, 'Niet gevonden.');
    let info;
    try {
      const actual = await realpath(filename);
      if (!actual.startsWith((await canonicalRoot) + path.sep)) return fail(404, 'Niet gevonden.');
      info = await stat(actual);
      if (!info.isFile()) return fail(404, 'Niet gevonden.');
    } catch { return fail(404, 'Niet gevonden.'); }
    const ext = path.extname(filename);
    if (!types[ext]) return fail(404, 'Niet gevonden.');
    const headers = { 'Content-Type':types[ext], 'Content-Length':info.size, 'Cache-Control':pathname.startsWith('/assets/') ? 'public, max-age=86400' : 'no-cache', 'Accept-Ranges':'bytes', 'Last-Modified':info.mtime.toUTCString() };
    let start = 0; let end = info.size - 1; let status = 200;
    if (req.headers.range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
      if (!match || (!match[1] && !match[2]) || !info.size) { res.setHeader('Content-Range', `bytes */${info.size}`); return fail(416, 'Ongeldig bereik.'); }
      if (!match[1]) { const length = Number(match[2]); start = Math.max(0, info.size - length); }
      else { start = Number(match[1]); if (match[2]) end = Math.min(Number(match[2]), end); }
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= info.size) { res.setHeader('Content-Range', `bytes */${info.size}`); return fail(416, 'Ongeldig bereik.'); }
      status = 206; headers['Content-Range'] = `bytes ${start}-${end}/${info.size}`; headers['Content-Length'] = end - start + 1;
    }
    res.writeHead(status, headers);
    if (req.method === 'HEAD' || info.size === 0) return res.end();
    const stream = createReadStream(filename, { start, end });
    stream.on('error', () => res.destroy());
    res.on('close', () => stream.destroy());
    stream.pipe(res);
  });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const host = process.env.HOST || '127.0.0.1';
  const port = Number(process.env.PORT || 4173);
  const server = createServer();
  server.listen(port, host, () => console.log(`V Production: http://${host}:${port}`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
