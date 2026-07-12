const http = require("http");
const crypto = require("crypto");

const GATEWAY_KEY = process.env.INTERNET_GATEWAY_KEY || "";
const PORT = process.env.PORT || 3000;

function decrypt(payloadStr, password) {
  try {
    const parts = payloadStr.split(":");
    if (parts.length !== 2) return null;
    const iv = Buffer.from(parts[0], "hex");
    const ciphertext = Buffer.from(parts[1], "hex");
    const key = crypto.createHash("sha256").update(password).digest();
    const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);
    let decrypted = decipher.update(ciphertext, null, "utf8");
    decrypted += decipher.final("utf8");
    return decrypted;
  } catch { return null; }
}

function encryptUrl(url, password) {
  const key = crypto.createHash("sha256").update(password).digest();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
  let encrypted = cipher.update(url, "utf8");
  encrypted = Buffer.concat([encrypted, cipher.final()]);
  return iv.toString("hex") + ":" + encrypted.toString("hex");
}

const IGNORED_REQ_HEADERS = new Set([
  "host", "x-forwarded-dest", "connection", "content-length",
  "x-forwarded-for", "x-real-ip", "accept-encoding"
]);

const IGNORED_RESP_HEADERS = new Set([
  "content-encoding", "transfer-encoding", "content-length",
  "access-control-allow-origin", "access-control-allow-methods",
  "access-control-allow-headers", "access-control-allow-credentials"
]);

async function handleProxy(req, res) {
  const origin = req.headers.origin || "*";
  const corsHeaders = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": req.headers["access-control-request-headers"] || "*",
    "Access-Control-Allow-Credentials": "true",
  };

  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders); res.end(); return;
  }

  const path = req.url ? new URL(req.url, "http://localhost").pathname : "";

  if (path === "/encrypt" && req.method === "GET") {
    const url = req.headers["x-forwarded-dest"];
    if (!url) {
      res.writeHead(400, { "Content-Type": "application/json", ...corsHeaders });
      res.end(JSON.stringify({ error: "Missing x-forwarded-dest header" }));
      return;
    }
    if (!GATEWAY_KEY) {
      res.writeHead(500, { "Content-Type": "application/json", ...corsHeaders });
      res.end(JSON.stringify({ error: "INTERNET_GATEWAY_KEY not configured" }));
      return;
    }
    const encrypted = encryptUrl(url.startsWith("http") ? url : "https://" + url, GATEWAY_KEY);
    res.writeHead(200, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ encrypted }));
    return;
  }

  const encryptedDest = req.headers["x-forwarded-dest"];

  if ((path === "/" || path === "" || path === "/proxy") && !encryptedDest) {
    res.writeHead(200, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ status: "ok", message: "Internet Gateway Proxy is active" }));
    return;
  }

  if (!encryptedDest) {
    res.writeHead(400, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ error: "Missing x-forwarded-dest header" }));
    return;
  }

  if (!GATEWAY_KEY) {
    res.writeHead(500, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ error: "INTERNET_GATEWAY_KEY not configured" }));
    return;
  }

  const targetUrl = decrypt(encryptedDest, GATEWAY_KEY);
  if (!targetUrl) {
    res.writeHead(401, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ error: "Unauthorized: Invalid gateway key or corrupted payload" }));
    return;
  }

  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) {
    if (!IGNORED_REQ_HEADERS.has(k.toLowerCase())) headers[k] = v;
  }

  let body = null;
  if (req.method !== "GET" && req.method !== "HEAD") {
    try {
      body = await new Promise((resolve, reject) => {
        const chunks = [];
        req.on("data", c => chunks.push(c));
        req.on("end", () => resolve(Buffer.concat(chunks)));
        req.on("error", reject);
      });
    } catch (err) {
      res.writeHead(400, { "Content-Type": "application/json", ...corsHeaders });
      res.end(JSON.stringify({ error: err.message }));
      return;
    }
  }

  try {
    let responseStatus, responseHeaders = {}, responseBuffer;

    if (typeof globalThis.fetch === "function") {
      const opts = { method: req.method, headers };
      if (body && body.length > 0) opts.body = body;
      const response = await fetch(targetUrl, opts);
      responseStatus = response.status;
      for (const [k, v] of response.headers.entries()) {
        if (!IGNORED_RESP_HEADERS.has(k.toLowerCase())) responseHeaders[k] = v;
      }
      responseBuffer = Buffer.from(await response.arrayBuffer());
    } else {
      const https = require("https");
      const http = require("http");
      const url = new URL(targetUrl);
      const client = url.protocol === "https:" ? https : http;
      const res = await new Promise((resolve, reject) => {
        const r = client.request(url, { method: req.method, headers }, resolve);
        r.on("error", reject);
        if (body) r.write(body);
        r.end();
      });
      responseStatus = res.statusCode;
      for (const [k, v] of Object.entries(res.headers)) {
        if (v !== undefined && !IGNORED_RESP_HEADERS.has(k.toLowerCase())) {
          responseHeaders[k] = Array.isArray(v) ? v.join(", ") : String(v);
        }
      }
      responseBuffer = await new Promise((resolve, reject) => {
        const chunks = [];
        res.on("data", c => chunks.push(c));
        res.on("end", () => resolve(Buffer.concat(chunks)));
        res.on("error", reject);
      });
    }

    res.writeHead(responseStatus, { ...corsHeaders, ...responseHeaders });
    res.end(responseBuffer);
  } catch (err) {
    res.writeHead(502, { "Content-Type": "application/json", ...corsHeaders });
    res.end(JSON.stringify({ error: err.message, target: targetUrl }));
  }
}

const server = http.createServer(handleProxy);
server.listen(PORT, "0.0.0.0", () => {
  console.log(`Internet Gateway Proxy on port ${PORT}`);
  console.log(`Gateway Key configured: ${GATEWAY_KEY ? "YES" : "NO (set INTERNET_GATEWAY_KEY)"}`);
});

module.exports = handleProxy;
