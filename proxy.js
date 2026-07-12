const http = require("http");
const https = require("https");
const net = require("net");
const url = require("url");

const PORT = process.env.PORT || 8080;

const proxy = http.createServer();

proxy.on("request", (req, res) => {
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
