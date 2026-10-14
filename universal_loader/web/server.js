const http = require('http');
const https = require('https');
const net = require('net');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const { URL } = require('url');

// Cổng phục vụ HTTP/HTTPS và thư mục gốc chứa tài nguyên Web
const HTTP_PORT = parseInt(process.env.PORT || '8080', 10);
const HTTPS_PORT = parseInt(process.env.HTTPS_PORT || '8443', 10);
const WEB_ROOT = __dirname;

// Bảng ánh xạ phần mở rộng tệp sang định dạng MIME chuẩn
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.jar': 'application/java-archive',
  '.jad': 'text/vnd.sun.j2me.app-descriptor; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
};

// Thiết lập các tiêu đề COOP/COEP bắt buộc để bật SharedArrayBuffer cho WebAssembly Pthreads
function setIsolationHeaders(res) {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-cache');
}

// Cầu nối chuyển tiếp yêu cầu HTTP/HTTPS từ lõi J2ME (javax.microedition.io.HttpConnection)
function executeHttpProxyRequest(urlStr, method, rawHeaders, bodyBuf, redirectsLeft, callback) {
  let targetUrl;
  try {
    targetUrl = new URL(urlStr);
  } catch (err) {
    callback(err, null);
    return;
  }

  const isHttps = targetUrl.protocol === 'https:';
  const transport = isHttps ? https : http;
  const headers = {};
  if (rawHeaders && typeof rawHeaders === 'object') {
    for (const [k, v] of Object.entries(rawHeaders)) {
      const lower = k.toLowerCase();
      if (lower === 'host' || lower === 'connection' || lower === 'content-length') continue;
      headers[k] = v;
    }
  }

  const upperMethod = String(method || 'GET').toUpperCase();
  if ((bodyBuf && bodyBuf.length > 0) || upperMethod === 'POST' || upperMethod === 'PUT') {
    headers['Content-Length'] = String(bodyBuf ? bodyBuf.length : 0);
  }

  const proxyReq = transport.request(
    {
      protocol: targetUrl.protocol,
      hostname: targetUrl.hostname,
      port: targetUrl.port || (isHttps ? 443 : 80),
      path: targetUrl.pathname + targetUrl.search,
      method: method || 'GET',
      headers,
      timeout: 30000,
      rejectUnauthorized: false,
    },
    (proxyRes) => {
      const code = proxyRes.statusCode || 200;
      const loc = proxyRes.headers['location'];
      if ([301, 302, 303, 307, 308].includes(code) && loc && redirectsLeft > 0) {
        proxyRes.resume();
        const nextUrl = new URL(loc, targetUrl).toString();
        const nextMethod = code === 303 ? 'GET' : method;
        const nextBody = code === 303 ? Buffer.alloc(0) : bodyBuf;
        executeHttpProxyRequest(nextUrl, nextMethod, rawHeaders, nextBody, redirectsLeft - 1, callback);
        return;
      }

      const respChunks = [];
      proxyRes.on('data', (d) => respChunks.push(d));
      proxyRes.on('end', () => {
        const respBody = Buffer.concat(respChunks);
        console.log(`[HTTP-PROXY] ${method || 'GET'} ${urlStr} -> ${code} (${respBody.length}B)`);
        const statusLine = `HTTP/1.1 ${code} ${proxyRes.statusMessage || 'OK'}`;
        const headerLines = [statusLine];
        for (const [k, v] of Object.entries(proxyRes.headers)) {
          const lower = k.toLowerCase();
          if (lower === 'transfer-encoding' || lower === 'content-encoding' || lower === 'content-length') continue;
          if (Array.isArray(v)) {
            for (const item of v) headerLines.push(`${k}: ${item}`);
          } else if (v !== undefined) {
            headerLines.push(`${k}: ${v}`);
          }
        }
        headerLines.push(`Content-Length: ${respBody.length}`);
        callback(null, {
          head: headerLines.join('\r\n'),
          bodyBase64: respBody.toString('base64'),
        });
      });
    }
  );

  proxyReq.on('error', (err) => {
    console.log(`[HTTP-PROXY] ERROR ${urlStr}: ${err.message}`);
    callback(err, null);
  });

  if (bodyBuf && bodyBuf.length > 0) proxyReq.write(bodyBuf);
  proxyReq.end();
}

// Tiếp nhận yêu cầu JSON từ trình duyệt tại endpoint /http-proxy và chuyển tiếp ra mạng ngoài
function handleHttpProxy(req, res) {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    try {
      const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const bodyBuf = payload.bodyBase64 ? Buffer.from(payload.bodyBase64, 'base64') : Buffer.alloc(0);
      executeHttpProxyRequest(
        payload.url,
        payload.method || 'GET',
        payload.headers || {},
        bodyBuf,
        5,
        (err, result) => {
          setIsolationHeaders(res);
          res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
          if (err) {
            res.end(JSON.stringify({ ok: false, error: err.message }));
          } else {
            res.end(
              JSON.stringify({
                ok: true,
                head: result.head,
                bodyBase64: result.bodyBase64,
              })
            );
          }
        }
      );
    } catch (err) {
      setIsolationHeaders(res);
      res.writeHead(400, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: false, error: String(err) }));
    }
  });
}

// Xử lý phục vụ các tệp tĩnh của ứng dụng Web và định tuyến API proxy
function handleRequest(req, res) {
  setIsolationHeaders(res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, 'http://localhost');
  if (parsedUrl.pathname === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }
  if (parsedUrl.pathname === '/http-proxy' && req.method === 'POST') {
    handleHttpProxy(req, res);
    return;
  }

  let relPath = decodeURIComponent(parsedUrl.pathname);
  if (relPath === '/') relPath = '/index.html';

  let filePath = path.normalize(path.join(WEB_ROOT, relPath));
  if (!filePath.startsWith(WEB_ROOT)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  if (relPath === '/assets/DragonBoy.jar' && !fs.existsSync(filePath)) {
    const fallbackJar = path.resolve(WEB_ROOT, '..', 'core', 'test_assets', 'DragonBoy.jar');
    if (fs.existsSync(fallbackJar)) filePath = fallbackJar;
  }

  if ((relPath === '/assets/logo.png' || relPath === '/assets/trihienkun_logo_master.png') && !fs.existsSync(filePath)) {
    const fallbackLogo = path.resolve(WEB_ROOT, '..', '..', 'trihienkun_logo_master.png');
    if (fs.existsSync(fallbackLogo)) filePath = fallbackLogo;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found: ' + relPath);
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const mime = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': mime,
      'Content-Length': stats.size,
    });
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    fs.createReadStream(filePath).pipe(res);
  });
}

// Đóng gói khung dữ liệu nhị phân theo chuẩn giao thức WebSocket RFC 6455
function encodeWsFrame(opcode, payloadBuffer) {
  const len = payloadBuffer.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x80 | opcode;
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payloadBuffer]);
}

// Cầu nối chuyển tiếp luồng byte hai chiều giữa WebSocket trình duyệt và Socket TCP thuần của máy chủ game
function attachWebSocketRelay(server) {
  server.on('upgrade', (req, socket, head) => {
    const parsed = new URL(req.url, 'http://localhost');
    if (parsed.pathname !== '/ws-tcp') {
      socket.destroy();
      return;
    }

    const targetHost = parsed.searchParams.get('host');
    const targetPort = parseInt(parsed.searchParams.get('port') || '0', 10);
    const wsKey = req.headers['sec-websocket-key'];

    if (!targetHost || !targetPort || targetPort <= 0 || targetPort > 65535 || !wsKey) {
      socket.destroy();
      return;
    }

    console.log(`[WS-TCP] Connecting -> ${targetHost}:${targetPort}`);
    const tcpClient = net.createConnection({ host: targetHost, port: targetPort });
    tcpClient.setNoDelay(true);
    tcpClient.setKeepAlive(true, 60000);
    socket.setNoDelay(true);

    let handshakeDone = false;
    let wsCloseSent = false;
    let rxBuffer = head && head.length > 0 ? Buffer.from(head) : Buffer.alloc(0);

    function sendWsCloseAndEnd() {
      if (wsCloseSent) return;
      wsCloseSent = true;
      if (handshakeDone && !socket.destroyed) {
        socket.end(encodeWsFrame(0x08, Buffer.alloc(0)));
      } else if (!socket.destroyed) {
        socket.destroy();
      }
    }

    // Giải mã các khung WebSocket từ trình duyệt và ghi trực tiếp vào kết nối TCP đích
    function processWsFrames() {
      while (rxBuffer.length >= 2) {
        const firstByte = rxBuffer[0];
        const secondByte = rxBuffer[1];
        const opcode = firstByte & 0x0f;
        const isMasked = (secondByte & 0x80) !== 0;
        let payloadLen = secondByte & 0x7f;
        let offset = 2;

        if (payloadLen === 126) {
          if (rxBuffer.length < 4) return;
          payloadLen = rxBuffer.readUInt16BE(2);
          offset = 4;
        } else if (payloadLen === 127) {
          if (rxBuffer.length < 10) return;
          payloadLen = Number(rxBuffer.readBigUInt64BE(2));
          offset = 10;
        }

        const maskBytes = isMasked ? 4 : 0;
        if (rxBuffer.length < offset + maskBytes + payloadLen) return;

        const mask = isMasked ? rxBuffer.subarray(offset, offset + 4) : null;
        offset += maskBytes;
        const data = Buffer.from(rxBuffer.subarray(offset, offset + payloadLen));
        rxBuffer = rxBuffer.subarray(offset + payloadLen);

        if (mask) {
          for (let i = 0; i < data.length; i++) {
            data[i] ^= mask[i & 3];
          }
        }

        if (opcode === 0x08) {
          if (!tcpClient.destroyed) tcpClient.end();
          sendWsCloseAndEnd();
          return;
        } else if (opcode === 0x09) {
          if (!socket.destroyed) socket.write(encodeWsFrame(0x0a, data));
        } else if (opcode === 0x01 || opcode === 0x02 || opcode === 0x00) {
          if (!tcpClient.destroyed && data.length > 0) {
            console.log(`[WS-TCP] TX -> ${targetHost}:${targetPort} (${data.length}B)`);
            tcpClient.write(data);
          }
        }
      }
    }

    tcpClient.on('connect', () => {
      console.log(`[WS-TCP] Connected  <- ${targetHost}:${targetPort}`);
      const acceptKey = crypto
        .createHash('sha1')
        .update(wsKey + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
        .digest('base64');

      const responseHeaders = [
        'HTTP/1.1 101 Switching Protocols',
        'Upgrade: websocket',
        'Connection: Upgrade',
        `Sec-WebSocket-Accept: ${acceptKey}`,
        '\r\n',
      ].join('\r\n');

      socket.write(responseHeaders);
      handshakeDone = true;
      if (rxBuffer.length > 0) processWsFrames();
    });

    tcpClient.on('data', (chunk) => {
      if (handshakeDone && !socket.destroyed) {
        console.log(`[WS-TCP] RX <- ${targetHost}:${targetPort} (${chunk.length}B)`);
        socket.write(encodeWsFrame(0x02, chunk));
      }
    });

    tcpClient.on('end', () => {
      console.log(`[WS-TCP] Remote EOF <- ${targetHost}:${targetPort}`);
      sendWsCloseAndEnd();
    });

    tcpClient.on('error', (err) => {
      console.log(`[WS-TCP] TCP Error  <- ${targetHost}:${targetPort}: ${err.message}`);
      sendWsCloseAndEnd();
      if (!tcpClient.destroyed) tcpClient.destroy();
    });

    tcpClient.on('close', () => {
      sendWsCloseAndEnd();
    });

    socket.on('data', (chunk) => {
      rxBuffer = Buffer.concat([rxBuffer, chunk]);
      if (handshakeDone) processWsFrames();
    });

    socket.on('error', () => {
      if (!tcpClient.destroyed) tcpClient.destroy();
    });
    socket.on('close', () => {
      if (!tcpClient.destroyed) tcpClient.destroy();
    });
    socket.on('end', () => {
      if (!tcpClient.destroyed) tcpClient.end();
    });
  });
}

// Sinh chứng chỉ TLS X.509 v3 tự ký thuần Node.js (không phụ thuộc OpenSSL ngoài) để cấp Secure Context cho iOS Safari qua LAN
function generateSelfSignedTlsCredentials() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'der' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });

  function derLen(len) {
    if (len < 128) return Buffer.from([len]);
    const bytes = [];
    let n = len;
    while (n > 0) {
      bytes.unshift(n & 0xff);
      n >>= 8;
    }
    return Buffer.from([0x80 | bytes.length, ...bytes]);
  }
  function derTag(tag, content) {
    return Buffer.concat([Buffer.from([tag]), derLen(content.length), content]);
  }
  function derSeq(...items) {
    return derTag(0x30, Buffer.concat(items));
  }
  function derSet(...items) {
    return derTag(0x31, Buffer.concat(items));
  }
  function derOid(oidBytes) {
    return derTag(0x06, Buffer.from(oidBytes));
  }
  function derUtf8(str) {
    return derTag(0x0c, Buffer.from(str, 'utf8'));
  }
  function derUtcTime(date) {
    const s =
      date
        .toISOString()
        .replace(/[-:T]/g, '')
        .slice(2, 14) + 'Z';
    return derTag(0x17, Buffer.from(s, 'ascii'));
  }
  function derInt(buf) {
    let b = Buffer.isBuffer(buf) ? buf : Buffer.from([buf]);
    if (b[0] & 0x80) b = Buffer.concat([Buffer.from([0x00]), b]);
    return derTag(0x02, b);
  }

  // Định danh thuật toán ký số OID sha256WithRSAEncryption (1.2.840.113549.1.1.11)
  const algId = derSeq(
    derOid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]),
    Buffer.from([0x05, 0x00])
  );
  // Thông tin định danh chủ thể/nhà phát hành chứng chỉ CN=J5Hienloader Local LAN (OID 2.5.4.3)
  const name = derSeq(derSet(derSeq(derOid([0x55, 0x04, 0x03]), derUtf8('J5Hienloader Local LAN'))));
  const now = new Date(Date.now() - 86400000);
  const exp = new Date(Date.now() + 3650 * 86400000);
  const validity = derSeq(derUtcTime(now), derUtcTime(exp));
  const version = derTag(0xa0, derInt(2));
  const serial = derInt(crypto.randomBytes(8));

  const tbs = derSeq(version, serial, algId, name, validity, name, publicKey);
  const sig = crypto.sign('sha256', tbs, privateKey);
  const sigBitStr = derTag(0x03, Buffer.concat([Buffer.from([0x00]), sig]));
  const certDer = derSeq(tbs, algId, sigBitStr);
  const b64 = certDer.toString('base64').match(/.{1,64}/g).join('\n');
  const certPem = `-----BEGIN CERTIFICATE-----\n${b64}\n-----END CERTIFICATE-----\n`;

  return { key: privateKey, cert: certPem };
}

// Khởi tạo máy chủ HTTP và HTTPS kèm cầu nối WebSocket TCP Relay
const httpServer = http.createServer(handleRequest);
attachWebSocketRelay(httpServer);

let httpsServer = null;
try {
  const tlsCreds = generateSelfSignedTlsCredentials();
  httpsServer = https.createServer(tlsCreds, handleRequest);
  attachWebSocketRelay(httpsServer);
  httpsServer.listen(HTTPS_PORT, '0.0.0.0');
} catch (err) {
  console.error('[HTTPS] Không thể khởi tạo máy chủ HTTPS:', err.message);
}

httpServer.listen(HTTP_PORT, '0.0.0.0', () => {
  console.log('============================================================');
  console.log(' J5Hienloader Web (Wasm + Pthreads + TCP Relay Server)');
  console.log('============================================================');
  console.log(` Local URL (PC / ADB Reverse): http://localhost:${HTTP_PORT}`);
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const netInfo of nets[name] || []) {
      if (netInfo.family === 'IPv4' && !netInfo.internal) {
        console.log(` LAN HTTP  (Android/PC):       http://${netInfo.address}:${HTTP_PORT}`);
        if (httpsServer) {
          console.log(` LAN HTTPS (iOS Safari/PWA):   https://${netInfo.address}:${HTTPS_PORT}`);
        }
      }
    }
  }
  console.log('============================================================');
});

