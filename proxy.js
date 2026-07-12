const http = require("http");
const https = require("https");
const net = require("net");
const os = require("os");

const PORT = process.env.PORT || 8080;

const proxy = http.createServer();

proxy.on("request", (req, res) => {
  const path = req.url.split("?")[0];

  if (path === "/" || path === "") {
    const uptime = Math.floor(process.uptime());
    const h = `<html><head><title>Internet Gateway - Active</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0d1117;color:#c9d1d9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:20px;box-sizing:border-box}.card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:40px;max-width:500px;width:100%;text-align:center}h1{color:#58a6ff;margin:0 0 8px;font-size:24px}.status{color:#3fb950;font-size:14px;margin-bottom:24px}.info{text-align:left;background:#0d1117;border-radius:8px;padding:16px;font-size:13px;line-height:1.8}.info span{color:#8b949e}.badge{display:inline-block;background:#1f6feb22;color:#58a6ff;border:1px solid #1f6feb44;border-radius:20px;padding:4px 12px;font-size:12px;margin-top:20px}</style></head><body>
<div class="card"><h1>Internet Gateway</h1>
<div class="status">● Proxy Active</div>
<div class="info">
<span>Host:</span> ${os.hostname()}<br>
<span>Uptime:</span> ${Math.floor(uptime / 60)}m ${uptime % 60}s<br>
<span>Node:</span> ${process.version}<br>
<span>Port:</span> ${PORT}<br>
<span>Platform:</span> railway.app<br>
</div>
<div class="badge">Forward Proxy — CONNECT + HTTP</div>
<div style="margin-top:16px;font-size:12px;color:#8b949e">Created by <a href="https://github.com/o-x-api" style="color:#58a6ff;text-decoration:none">@o-x-api</a></div>
</div></body></html>`;
    res.writeHead(200, { "content-type": "text/html; charset=utf-8", "content-length": Buffer.byteLength(h) });
    res.end(h);
    return;
  }

  if (path === "/raw") {
    const dest = req.headers["x-raw-dest"];
    if (!dest) {
      res.writeHead(400, { "content-type": "text/plain" });
      res.end("Missing x-raw-dest header");
      return;
    }
    const u = new URL(dest);
    const mod = u.protocol === "http:" ? http : https;
    const chunks = [];
    req.on("data", c => chunks.push(c));
    req.on("end", () => {
      const opts = {
        method: "GET",
        hostname: u.hostname,
        port: parseInt(u.port) || (u.protocol === "http:" ? 80 : 443),
        path: u.pathname + u.search,
        headers: {},
        rejectUnauthorized: false,
      };
      const SKIP = new Set(["host", "x-raw-dest", "content-length", "transfer-encoding", "accept-encoding"]);
      for (const [k, v] of Object.entries(req.headers)) {
        if (!SKIP.has(k.toLowerCase())) opts.headers[k] = v;
      }
      if (body.length) opts.headers["content-length"] = body.length;
      const proxyReq = mod.request(opts, (proxyRes) => {
        const respHeaders = {};
        for (const [k, v] of Object.entries(proxyRes.headers)) {
          const lk = k.toLowerCase();
          if (lk !== "transfer-encoding" && lk !== "content-encoding" && lk !== "content-length") {
            respHeaders[k] = v;
          }
        }
        res.writeHead(proxyRes.statusCode, respHeaders);
        proxyRes.pipe(res);
      });
      proxyReq.on("error", (e) => {
        res.writeHead(502, { "content-type": "text/plain" });
        res.end("Raw Proxy Error: " + e.message);
      });
      if (body.length) proxyReq.write(body);
      proxyReq.end();
    });
    return;
  }

  const targetUrl = req.url.startsWith("http") ? req.url : "http://" + (req.headers.host || "localhost") + req.url;
  const u = new URL(targetUrl);
  const mod = u.protocol === "http:" ? http : https;

  const opts = {
    method: req.method,
    hostname: u.hostname,
    port: parseInt(u.port) || (u.protocol === "http:" ? 80 : 443),
    path: u.pathname + u.search,
    headers: { ...req.headers },
    rejectUnauthorized: false,
  };

  delete opts.headers["proxy-connection"];

  const proxyReq = mod.request(opts, (proxyRes) => {
    const respHeaders = {};
    for (const [k, v] of Object.entries(proxyRes.headers)) {
      const lk = k.toLowerCase();
      if (lk !== "transfer-encoding" && lk !== "content-encoding" && lk !== "content-length") {
        respHeaders[k] = v;
      }
    }
    res.writeHead(proxyRes.statusCode, respHeaders);
    proxyRes.pipe(res);
  });

  proxyReq.on("error", (e) => {
    res.writeHead(502, { "content-type": "text/plain" });
    res.end("Proxy Error: " + e.message);
  });

  req.pipe(proxyReq);
});

proxy.on("connect", (req, client) => {
  const [hostname, port] = req.url.split(":");
  const targetPort = parseInt(port) || 443;

  const dest = net.connect(targetPort, hostname, () => {
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
    client.pipe(dest).pipe(client);
  });

  dest.on("error", () => client.end());
  client.on("error", () => dest.end());
});

proxy.listen(PORT, "0.0.0.0", () => console.log("Forward proxy on 0.0.0.0:" + PORT));
