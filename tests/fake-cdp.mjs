// A tiny stand-in for Chrome's DevTools endpoint, enough for cdp.mjs to reach Playwright:
// GET /json/list, GET /json/version, and one WebSocket reply to Target.createTarget.
// Usage: node fake-cdp.mjs <port-file> <tag-file>
// Writes the port it listens on to <port-file> and the URL cdp.mjs asked for to <tag-file>.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';

const [portFile, tagFile] = process.argv.slice(2);
const server = http.createServer((req, res) => {
  const port = server.address().port;
  res.setHeader('Content-Type', 'application/json');
  if (req.url === '/json/list') return res.end('[]');
  if (req.url === '/json/version') return res.end(JSON.stringify({ webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/browser/x` }));
  res.statusCode = 404; res.end('{}');
});
server.on('upgrade', (req, sock) => {
  const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  sock.on('data', buf => {
    if ((buf[0] & 0x0f) !== 1) return;            // text frames only
    let len = buf[1] & 0x7f, off = 2;
    if (len === 126) { len = buf.readUInt16BE(2); off = 4; }
    const mask = buf.subarray(off, off + 4); off += 4;
    const data = Buffer.from(buf.subarray(off, off + len).map((b, i) => b ^ mask[i % 4])).toString();
    const m = JSON.parse(data);
    fs.writeFileSync(tagFile, m.params.url);
    const reply = Buffer.from(JSON.stringify({ id: m.id, result: { targetId: 'T1' } }));
    const head = reply.length < 126 ? Buffer.from([0x81, reply.length]) : Buffer.from([0x81, 126, reply.length >> 8, reply.length & 0xff]);
    sock.write(Buffer.concat([head, reply]));
  });
  sock.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(portFile, String(server.address().port)));
setTimeout(() => process.exit(0), 30000).unref();
