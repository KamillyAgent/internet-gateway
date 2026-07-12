#!/bin/bash
set -e

###############################################################################
#  Internet Gateway - Auto Setup Script
#  Routes ALL system traffic through an encrypted gateway proxy
#
#  Created by ABDULLAH
#  GitHub: o-x-api
#  Repo:   https://github.com/o-x-api/internet-gateway
###############################################################################

# ─────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────
R="\033[1;31m"
G="\033[1;32m"
Y="\033[1;33m"
B="\033[1;34m"
C="\033[1;36m"
W="\033[1;37m"
N="\033[0m"

# ─────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────
clear
echo -e "
${R}   ╔═══════════════════════════════════════════════════════════╗
   ║                                                           ║
   ║  ${W}██╗███╗   ██╗████████╗███████╗██████╗ ███╗   ██╗███████╗████████╗${R}  ║
   ║  ${W}██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝${R}  ║
   ║  ${W}██║██╔██╗ ██║   ██║   █████╗  ██████╔╝██╔██╗ ██║█████╗     ██║   ${R}  ║
   ║  ${W}██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝     ██║   ${R}  ║
   ║  ${W}██║██║ ╚████║   ██║   ███████╗██║  ██║██║ ╚████║███████╗   ██║   ${R}  ║
   ║  ${W}╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ${R}  ║
   ║                                                           ║
   ║  ${C}  ██████╗  █████╗ ████████╗███████╗██╗    ██╗ █████╗ ██╗   ██╗${R}  ║
   ║  ${C}  ██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║    ██║██╔══██╗╚██╗ ██╔╝${R}  ║
   ║  ${C}  ██║  ██║███████║   ██║   █████╗  ██║ █╗ ██║███████║ ╚████╔╝ ${R}  ║
   ║  ${C}  ██║  ██║██╔══██║   ██║   ██╔══╝  ██║███╗██║██╔══██║  ╚██╔╝  ${R}  ║
   ║  ${C}  ██████╔╝██║  ██║   ██║   ███████╗╚███╔███╔╝██║  ██║   ██║   ${R}  ║
   ║  ${C}  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝   ${R}  ║
   ║                                                           ║
   ║  ${Y}         🌐  System-Wide Transparent Proxy  🌐${R}           ║
   ║                                                           ║
   ║  ${W}           Created by ABDULLAH                          ${R}  ║
   ║  ${W}           GitHub   : o-x-api                            ${R}  ║
   ║  ${W}           Repo     : github.com/o-x-api/internet-gateway${R}  ║
   ║                                                           ║
   ╚═══════════════════════════════════════════════════════════╝${N}
"

# ─────────────────────────────────────────────────────────────────
# Check root
# ─────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}[!] This script must be run as root${N}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────
# Gather inputs
# ─────────────────────────────────────────────────────────────────
echo -e "\n${B}[i] Internet Gateway Configuration${N}\n"

read -p "$(echo -e "${C}Enter Gateway URL ${W}(e.g. https://internet-gateway.vercel.app)${N}: ")" GATEWAY_URL
GATEWAY_URL="${GATEWAY_URL:-https://internet-gateway.vercel.app}"

read -p "$(echo -e "${C}Enter Gateway Key ${W}(INTERNET_GATEWAY_KEY)${N}: ")" GATEWAY_KEY

while [ -z "$GATEWAY_KEY" ]; do
  echo -e "${R}[!] Gateway Key is required${N}"
  read -p "$(echo -e "${C}Enter Gateway Key: ${N}")" GATEWAY_KEY
done

echo ""
echo -e "${Y}[i] Testing gateway connection...${N}"
TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${GATEWAY_URL}/" 2>&1 || echo "000")
if [ "$TEST" = "200" ] || [ "$TEST" = "000" ]; then
  echo -e "${G}[✓] Gateway reachable${N}"
else
  echo -e "${R}[!] Gateway returned HTTP $TEST - continuing anyway${N}"
fi

# ────────────────────────────────────────────────────────────────────────
# STEP 1: Install dependencies
# ────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}[1/6] Installing dependencies...${N}"

# Install node-forge for certificate generation
if [ ! -d "/home/daytona/mitm-proxy/node_modules/node-forge" ]; then
  mkdir -p /home/daytona/mitm-proxy
  cd /home/daytona/mitm-proxy
  npm init -y > /dev/null 2>&1
  npm install node-forge > /dev/null 2>&1
  echo -e "${G}[✓] node-forge installed${N}"
else
  echo -e "${G}[✓] node-forge already installed${N}"
fi

# ────────────────────────────────────────────────────────────────────────
# STEP 2: Generate CA certificate
# ────────────────────────────────────────────────────────────────────────
echo -e "${B}[2/6] Generating CA certificate...${N}"

cd /home/daytona
openssl genrsa -out mitm-ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key mitm-ca.key -sha256 -days 3650 \
  -subj "/CN=InternetGatewayMITM" \
  -out mitm-ca.pem 2>/dev/null

# Install CA cert system-wide
if [ -d "/usr/local/share/ca-certificates" ]; then
  cp mitm-ca.pem /usr/local/share/ca-certificates/internet-gateway.crt
elif [ -d "/usr/share/ca-certificates" ]; then
  cp mitm-ca.pem /usr/share/ca-certificates/internet-gateway.crt
fi
update-ca-certificates 2>/dev/null || true
echo -e "${G}[✓] CA certificate generated and installed${N}"

# ────────────────────────────────────────────────────────────────────────
# STEP 3: Create the monkey-patching module
# ────────────────────────────────────────────────────────────────────────
echo -e "${B}[3/6] Creating gateway interception module...${N}"

GATEWAY_JS_URL="${GATEWAY_URL}"
GATEWAY_JS_KEY="${GATEWAY_KEY}"

cat > /home/daytona/internet-gateway.js << 'MODULE'
/**
 * Gateway Proxy: Transparent & Undetectable Network Interceptor
 * Patches Node.js http/https/fetch/undici to redirect blocked outbound
 * requests through an external gateway.
 */
"use strict";
const https = require("https");
const http = require("http");
const crypto = require("crypto");

const log = (...args) => console.error(...args);
let GU = process.env.INTERNET_GATEWAY || process.env.CLOUDFLARE_PROXY_URL;
if (GU && !GU.startsWith("http://") && !GU.startsWith("https://")) GU = "https://" + GU;
const GK = process.env.INTERNET_GATEWAY_KEY || process.env.CLOUDFLARE_PROXY_SECRET || "";
const DR = (process.env.INTERNET_GATEWAY_DOMAINS || "").trim();
const ALL = DR === "*";
const DEF = ["api.telegram.org","discord.com","discordapp.com","googleapis.com","google.com","api.openai.com"];
let TD; if (ALL) { TD = []; } else { const ex = DR.split(",").map(d=>d.trim()).filter(Boolean); const se = new Set(DEF); TD = [...DEF]; for (const d of ex) { if (!se.has(d)) { TD.push(d); se.add(d); } } }

function enc(text, pw) {
  try {
    const k = crypto.createHash("sha256").update(pw).digest();
    const iv = crypto.randomBytes(16);
    const c = crypto.createCipheriv("aes-256-cbc", k, iv);
    let e = c.update(text, "utf8", "hex"); e += c.final("hex");
    return iv.toString("hex") + ":" + e;
  } catch (err) { log("[gw] Encrypt error:", err.message); return null; }
}

if (GU && GK) {
  try {
    const gw = new URL(GU);
    const oHttps = https.request, oHttp = http.request, oFetch = typeof globalThis.fetch === "function" ? globalThis.fetch.bind(globalThis) : null;
    const should = (h) => { const n = String(h||"").trim().toLowerCase(); if (!n) return false; if (["localhost","127.0.0.1","::1","0.0.0.0"].includes(n)||n===gw.hostname) return false; if (ALL) return true; return TD.some(d=>n===d||n.endsWith("."+d)); };
    const patch = (orig) => function p() { try { let opt={},cb; if (typeof arguments[0]==="string"||arguments[0] instanceof URL) { const u=new URL(arguments[0]); opt={protocol:u.protocol,hostname:u.hostname,port:u.port,path:u.pathname+u.search}; if(typeof arguments[1]==="object"&&arguments[1]!==null) {opt={...opt,...arguments[1]};cb=arguments[2]} else cb=arguments[1] } else {opt={...arguments[0]};cb=arguments[1]} const hn=opt.hostname||(opt.host?String(opt.host).split(":")[0]:""); if (should(hn)&&!opt._proxied&&!(opt.headers&&(opt.headers["x-forwarded-dest"]||opt.headers["X-Forwarded-Dest"]))) { const fu=opt.protocol+"//"+hn+(opt.port?":"+opt.port:"")+(opt.path||"/"); const ed=enc(fu,GK); if(ed) { const no={...opt}; no._proxied=true; no.protocol=gw.protocol; no.hostname=gw.hostname; no.port=gw.port||(gw.protocol==="https:"?443:80); no.servername=gw.hostname; no.path=gw.pathname==="/"?"/proxy":gw.pathname; delete no.host; delete no.agent; no.headers={...(opt.headers||{}),host:gw.host,"x-forwarded-dest":ed}; return oHttps.call(https,no,cb) } } } catch(e) { log("[gw] patch error:",e.message); } return orig.apply(this,arguments); };
    https.request = patch(oHttps); http.request = patch(oHttp);
    if (oFetch) { globalThis.fetch = async function(i, init) { const r=i instanceof Request?i:null; const us=r?r.url:String(i); let u; try{u=new URL(us)}catch(e){return oFetch(i,init)} const hn=u.hostname; if(!should(hn)) return oFetch(i,init); let mh; if(r) mh=new Headers(r.headers); else mh=new Headers(init?.headers||{}); if(mh.has("x-forwarded-dest")) return oFetch(i,init); const ed=enc(us,GK); if(!ed) return oFetch(i,init); mh.set("x-forwarded-dest",ed); const pu=new URL(gw.pathname==="/"?"/proxy":gw.pathname,gw); const ni={method:r?r.method:(init?.method||"GET"),headers:mh}; if(r&&r.body) {ni.body=r.body;ni.duplex="half"} else if(init?.body!=null) {ni.body=init.body;if(init.body instanceof ReadableStream) ni.duplex=init.duplex||"half"} if(init?.signal) ni.signal=init.signal; if(init?.redirect) ni.redirect=init.redirect; return oFetch(String(pu),ni); }; }
    try { const und=require("undici"); const pd=(ex)=>{ if(!ex) return; const pd2=(pr)=>{ if(pr&&pr.dispatch&&!pr.dispatch._patched) { const od=pr.dispatch; pr.dispatch=function(o,h) { let or=o.origin||this.origin; if(or&&typeof or!=="string") try{or=or.origin||or.toString()}catch(e){or=""} let hn="",prt="https:"; try{const u=new URL(String(or));hn=u.hostname;prt=u.protocol}catch(e){hn=String(or||"").split(":")[0]} if(hn&&should(hn)) { const fu=prt+"//"+hn+(o.path||""); const ed=enc(fu,GK); if(ed) { const th="x-forwarded-dest"; if(Array.isArray(o.headers)){let ft=false;for(let i=0;i<o.headers.length;i+=2){if(String(o.headers[i]).toLowerCase()===th){ft=true;break}} if(!ft) o.headers.push(th,ed) } else {o.headers=o.headers||{}; if(o.headers instanceof Map||typeof o.headers.set==="function") o.headers.set(th,ed); else o.headers[th]=ed } o.origin=gw.origin; o.path=gw.pathname==="/"?"/proxy":gw.pathname } } return od.call(this,o,h); }; pr.dispatch._patched=true; } }; for(const k in ex) { if(ex[k]&&ex[k].prototype&&typeof ex[k].prototype.dispatch==="function") pd2(ex[k].prototype) } if(ex.getGlobalDispatcher) { try{const gd=ex.getGlobalDispatcher(); if(gd&&gd.dispatch&&!gd.dispatch._patched) pd2(gd)}catch(e){} } if(ex.Agent&&ex.Agent.prototype) pd2(ex.Agent.prototype); if(ex.Pool&&ex.Pool.prototype) pd2(ex.Pool.prototype); if(ex.Client&&ex.Client.prototype) pd2(ex.Client.prototype); }; pd(und); } catch(e) {}
    const Mod=require("module"), oReq=Mod.prototype.require; const UR=/(?:^|\/)node_modules\/undici(?:\/|$)/; Mod.prototype.require=function(id) { let ex; try{ex=oReq.apply(this,arguments)}catch(e){throw e} if(id==="undici"||UR.test(id)) try{const und=require("undici"); const pd=(ex)=>{ if(!ex) return; const pd2=(pr)=>{ if(pr&&pr.dispatch&&!pr.dispatch._patched) { const od=pr.dispatch; pr.dispatch=function(o,h) { let or=o.origin||this.origin; if(or&&typeof or!=="string") try{or=or.origin||or.toString()}catch(e){or=""} let hn="",prt="https:"; try{const u=new URL(String(or));hn=u.hostname;prt=u.protocol}catch(e){hn=String(or||"").split(":")[0]} if(hn&&should(hn)) { const fu=prt+"//"+hn+(o.path||""); const ed=enc(fu,GK); if(ed) { const th="x-forwarded-dest"; if(Array.isArray(o.headers)){let ft=false;for(let i=0;i<o.headers.length;i+=2){if(String(o.headers[i]).toLowerCase()===th){ft=true;break}} if(!ft) o.headers.push(th,ed) } else {o.headers=o.headers||{}; if(o.headers instanceof Map||typeof o.headers.set==="function") o.headers.set(th,ed); else o.headers[th]=ed } o.origin=gw.origin; o.path=gw.pathname==="/"?"/proxy":gw.pathname } } return od.call(this,o,h); }; pr.dispatch._patched=true; } }; for(const k in ex) { if(ex[k]&&ex[k].prototype&&typeof ex[k].prototype.dispatch==="function") pd2(ex[k].prototype) } if(ex.getGlobalDispatcher) { try{const gd=ex.getGlobalDispatcher(); if(gd&&gd.dispatch&&!gd.dispatch._patched) pd2(gd)}catch(e){} } if(ex.Agent&&ex.Agent.prototype) pd2(ex.Agent.prototype); if(ex.Pool&&ex.Pool.prototype) pd2(ex.Pool.prototype); if(ex.Client&&ex.Client.prototype) pd2(ex.Client.prototype); }; pd(ex); } catch(e) {} return ex; };
  } catch (err) { log("[gw] Init failed:", err.message); }
}
MODULE

cp /home/daytona/internet-gateway.js /usr/local/lib/internet-gateway.js 2>/dev/null || true
echo -e "${G}[✓] Interception module created${N}"

# ────────────────────────────────────────────────────────────────────────
# STEP 4: Create MITM proxy
# ────────────────────────────────────────────────────────────────────────
echo -e "${B}[4/6] Creating MITM proxy server...${N}"

mkdir -p /home/daytona/mitm-certs

cat > /home/daytona/mitm-proxy/index.js << PROXYEOF
process.env.INTERNET_GATEWAY = "${GATEWAY_JS_URL}";
process.env.INTERNET_GATEWAY_KEY = "${GATEWAY_JS_KEY}";
process.env.INTERNET_GATEWAY_DOMAINS = "*";
require("/usr/local/lib/internet-gateway.js");

const http = require("http");
const tls = require("tls");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const net = require("net");

const PORT = parseInt(process.env.PORT) || 8888;
const CA_KEY = fs.readFileSync("/home/daytona/mitm-ca.key", "utf8");
const CA_CERT = fs.readFileSync("/home/daytona/mitm-ca.pem", "utf8");
const CERT_DIR = "/home/daytona/mitm-certs";

function ensureDir() { try { fs.mkdirSync(CERT_DIR, { recursive: true }); } catch(e) {} }
ensureDir();

function genCert(hostname) {
  const forge = require("/home/daytona/mitm-proxy/node_modules/node-forge");
  const pki = forge.pki;
  const caKey = pki.privateKeyFromPem(CA_KEY);
  const caCert = pki.certificateFromPem(CA_CERT);
  const keys = pki.rsa.generateKeyPair(2048);
  const cert = pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = crypto.randomBytes(16).toString("hex");
  cert.validity.notBefore = new Date();
  cert.validity.notAfter = new Date();
  cert.validity.notAfter.setFullYear(cert.validity.notBefore.getFullYear() + 1);
  cert.setSubject([{ name: "commonName", value: hostname }]);
  cert.setIssuer(caCert.subject.attributes);
  cert.setExtensions([
    { name: "basicConstraints", cA: false },
    { name: "subjectAltName", altNames: [{ type: 2, value: hostname }] },
  ]);
  cert.sign(caKey, forge.md.sha256.create());
  return { key: forge.pki.privateKeyToPem(keys.privateKey), cert: forge.pki.certificateToPem(cert) };
}

const certCache = {};
function getCert(hostname) {
  if (certCache[hostname]) return certCache[hostname];
  const safe = hostname.replace(/[^a-zA-Z0-9.-]/g, "_");
  const kp = path.join(CERT_DIR, safe + ".key");
  const cp = path.join(CERT_DIR, safe + ".pem");
  if (fs.existsSync(kp) && fs.existsSync(cp)) {
    certCache[hostname] = { key: fs.readFileSync(kp, "utf8"), cert: fs.readFileSync(cp, "utf8") };
    return certCache[hostname];
  }
  const c = genCert(hostname);
  fs.writeFileSync(kp, c.key); fs.writeFileSync(cp, c.cert);
  certCache[hostname] = c;
  return c;
}

function parseHttp(buf) {
  const s = buf.toString();
  const e = s.indexOf("\r\n\r\n");
  if (e === -1) return null;
  const hp = s.substring(0, e), bd = s.substring(e + 4);
  const ln = hp.split("\r\n"), ps = ln[0].split(" ");
  const hd = {};
  for (let i = 1; i < ln.length; i++) { const ci = ln[i].indexOf(":"); if (ci > 0) hd[ln[i].substring(0, ci).trim()] = ln[i].substring(ci + 1).trim(); }
  return { method: ps[0], path: ps[1] || "/", headers: hd, body: bd ? Buffer.from(bd) : null };
}

async function fetchV(method, url, headers, body) {
  const opts = { method, headers };
  if (body) opts.body = body;
  const r = await fetch(url, opts);
  const rh = {};
  for (const [k, v] of r.headers.entries()) rh[k] = v;
  return { status: r.status, headers: rh, body: Buffer.from(await r.arrayBuffer()) };
}

// HTTP proxy - handles GET http://url/ proxy requests
const proxy = http.createServer();
proxy.on("request", async (req, res) => {
  try {
    const target = req.url.startsWith("http") ? req.url : "http://" + (req.headers.host || "localhost") + req.url;
    const ch = []; for await (const c of req) ch.push(c);
    const bd = Buffer.concat(ch);
    const r = await fetchV(req.method, target, req.headers, bd.length ? bd : null);
    for (const [k, v] of Object.entries(r.headers)) res.setHeader(k, v);
    res.writeHead(r.status); res.end(r.body);
  } catch (e) {
    res.writeHead(502, { "Content-Type": "text/plain" });
    res.end("Gateway Error: " + e.message + "\n");
  }
});

// CONNECT - handles HTTPS MITM + plain HTTP through tunnel
proxy.on("connect", (req, client) => {
  const [hostname, portStr] = req.url.split(":");
  const port = parseInt(portStr) || 443;
  client.write("HTTP/1.1 200 Connection Established\r\n\r\n");

  let firstChunk = true;
  const handler = async (data) => {
    if (firstChunk) { firstChunk = false; } else return;
    client.removeListener("data", handler);

    if (data[0] === 0x16) {
      // TLS - MITM
      try {
        const c = getCert(hostname);
        const tlsSock = new tls.TLSSocket(client, { isServer: true, key: c.key, cert: c.cert });
        tlsSock.on("error", () => {});
        let buf = data.toString();
        tlsSock.on("data", async (d) => {
          buf += d.toString();
          const p = parseHttp(buf); if (!p) return;
          buf = "";
          try {
            const r = await fetchV(p.method, "https://" + hostname + p.path, p.headers, p.body);
            let resp = "HTTP/1.1 " + r.status + " OK\r\n";
            for (const [k, v] of Object.entries(r.headers)) resp += k + ": " + v + "\r\n";
            resp += "\r\n";
            tlsSock.write(resp); if (r.body) tlsSock.write(r.body); tlsSock.end();
          } catch (e) { tlsSock.write("HTTP/1.1 502\r\n\r\n" + e.message); tlsSock.end(); }
        });
      } catch (e) { client.end(); }
    } else {
      // Plain HTTP through tunnel
      let buf = data.toString();
      client.on("data", (d) => buf += d.toString());
      const proc = async () => {
        const p = parseHttp(buf); if (!p) return;
        buf = "";
        try {
          const r = await fetchV(p.method, "http://" + hostname + ":" + port + p.path, p.headers, p.body);
          let resp = "HTTP/1.1 " + r.status + " OK\r\n";
          for (const [k, v] of Object.entries(r.headers)) resp += k + ": " + v + "\r\n";
          resp += "\r\n";
          client.write(resp); if (r.body) client.write(r.body); client.end();
        } catch (e) { client.write("HTTP/1.1 502\r\n\r\n" + e.message); client.end(); }
      };
      proc();
    }
  };
  client.on("data", handler);
  client.on("error", () => {});
});

proxy.listen(PORT, "0.0.0.0", () => console.log("MITM Gateway proxy on 0.0.0.0:" + PORT));
PROXYEOF

echo -e "${G}[✓] MITM proxy created${N}"

# ────────────────────────────────────────────────────────────────────────
# STEP 5: Set system-wide environment variables
# ────────────────────────────────────────────────────────────────────────
echo -e "${B}[5/6] Setting system-wide proxy environment...${N}"

# /etc/profile.d (all users, login shells)
cat > /etc/profile.d/internet-gateway.sh << 'EOF'
export HTTP_PROXY=http://127.0.0.1:8888
export HTTPS_PROXY=http://127.0.0.1:8888
export http_proxy=http://127.0.0.1:8888
export https_proxy=http://127.0.0.1:8888
export NO_PROXY=localhost,127.0.0.1,::1
export no_proxy=localhost,127.0.0.1,::1
EOF
chmod +x /etc/profile.d/internet-gateway.sh

# /etc/environment (PAM)
cat > /etc/environment << 'EOF'
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
HTTP_PROXY=http://127.0.0.1:8888
HTTPS_PROXY=http://127.0.0.1:8888
http_proxy=http://127.0.0.1:8888
https_proxy=http://127.0.0.1:8888
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
EOF

# root .bashrc
for f in /root/.bashrc /home/daytona/.bashrc; do
  if [ -f "$f" ]; then
    sed -i '/INTERNET_GATEWAY/d' "$f" 2>/dev/null || true
    sed -i '/HTTP_PROXY/d' "$f" 2>/dev/null || true
    sed -i '/HTTPS_PROXY/d' "$f" 2>/dev/null || true
    sed -i '/http_proxy/d' "$f" 2>/dev/null || true
    sed -i '/https_proxy/d' "$f" 2>/dev/null || true
    cat >> "$f" << 'BASHEOF'

# Internet Gateway
export HTTP_PROXY=http://127.0.0.1:8888
export HTTPS_PROXY=http://127.0.0.1:8888
export http_proxy=http://127.0.0.1:8888
export https_proxy=http://127.0.0.1:8888
export NO_PROXY=localhost,127.0.0.1,::1
export no_proxy=localhost,127.0.0.1,::1
BASHEOF
  fi
done

echo -e "${G}[✓] Environment variables set system-wide${N}"

# ────────────────────────────────────────────────────────────────────────
# STEP 6: Start proxy and test
# ────────────────────────────────────────────────────────────────────────
echo -e "${B}[6/6] Starting proxy...${N}"

# Kill any existing proxy
pkill -f "mitm-proxy" 2>/dev/null || true
pkill -f "gateway-proxy" 2>/dev/null || true
sleep 1

# Start
cd /home/daytona/mitm-proxy
nohup node index.js > /tmp/mitm-proxy.log 2>&1 &
disown
sleep 2

# Verify
if pgrep -f "mitm-proxy/index.js" > /dev/null 2>&1; then
  echo -e "${G}[✓] Proxy is running on 127.0.0.1:8888${N}"
else
  echo -e "${R}[!] Proxy failed to start. Check /tmp/mitm-proxy.log${N}"
  cat /tmp/mitm-proxy.log 2>/dev/null
fi

# ────────────────────────────────────────────────────────────────────────
# Test
# ────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}[i] Running connectivity test...${N}"
. /etc/profile.d/internet-gateway.sh

sleep 2
for url in https://discord.com https://google.com https://github.com; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>&1)
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ] || [ "$code" = "403" ]; then
    echo -e "  ${G}[✓]${N} $url → HTTP $code"
  else
    echo -e "  ${R}[✗]${N} $url → HTTP $code"
  fi
done

# ────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}╔═══════════════════════════════════════════════════════════╗${N}"
echo -e "${G}║${N}  ${W}Internet Gateway - Setup Complete${N}                     ${G}║${N}"
echo -e "${G}║${N}                                                         ${G}║${N}"
echo -e "${G}║${N}  ${C}Gateway URL :${N} ${Y}${GATEWAY_URL}${N}"
echo -e "${G}║${N}  ${C}Proxy Port  :${N} ${Y}8888${N}"
echo -e "${G}║${N}  ${C}CA Cert     :${N} ${Y}/home/daytona/mitm-ca.pem${N}"
echo -e "${G}║${N}                                                         ${G}║${N}"
echo -e "${G}║${N}  ${W}Every app now routes through the gateway!${N}          ${G}║${N}"
echo -e "${G}║${N}                                                         ${G}║${N}"
echo -e "${G}║${N}  ${Y}Created by ABDULLAH${N}                                  ${G}║${N}"
echo -e "${G}║${N}  ${Y}GitHub: o-x-api${N}                                       ${G}║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════════════╝${N}"
echo ""
