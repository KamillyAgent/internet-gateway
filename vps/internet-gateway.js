/**
 * Gateway Proxy: Transparent & Undetectable Network Interceptor
 *
 * Patches Node.js http/https/fetch/undici to redirect blocked outbound requests
 * through an external gateway. To hide target URLs from platform-level inspection,
 * the target URL is AES-256-CBC encrypted using the shared key.
 */
"use strict";

const https = require("https");
const http = require("http");
const crypto = require("crypto");

const log = (...args) => console.error(...args);

let GATEWAY_URL = process.env.INTERNET_GATEWAY || process.env.CLOUDFLARE_PROXY_URL;
if (
  GATEWAY_URL &&
  !GATEWAY_URL.startsWith("http://") &&
  !GATEWAY_URL.startsWith("https://")
) {
  GATEWAY_URL = `https://${GATEWAY_URL}`;
}

const GATEWAY_KEY = process.env.INTERNET_GATEWAY_KEY || process.env.CLOUDFLARE_PROXY_SECRET || "";
const DOMAINS_RAW = (process.env.INTERNET_GATEWAY_DOMAINS || process.env.CLOUDFLARE_PROXY_DOMAINS || "").trim();
// PROXY_ALL only when INTERNET_GATEWAY_DOMAINS is explicitly set to "*".
// When unset, use DEFAULT_DOMAINS (safe default) to avoid intercepting
// n8n's own startup and internal network calls, which would break startup.
const PROXY_ALL = DOMAINS_RAW === "*";

const DEFAULT_DOMAINS = [
  "api.telegram.org", "discord.com", "discordapp.com",
  "gateway.discord.gg", "status.discord.com", "web.whatsapp.com",
  "graph.facebook.com", "graph.instagram.com",
  "api.twitter.com", "api.x.com", "upload.twitter.com",
  "api.linkedin.com", "www.linkedin.com",
  "open.tiktokapis.com", "oauth.reddit.com",
  "youtube.com", "www.youtube.com",
  "api.openai.com",
  "api.resend.com", "api.sendgrid.com", "api.mailgun.net",
  "googleapis.com", "google.com", "googleusercontent.com", "gstatic.com",
];

let TARGET_DOMAINS;
if (PROXY_ALL) {
  TARGET_DOMAINS = [];
} else {
  const extra = DOMAINS_RAW.split(",").map((d) => d.trim()).filter(Boolean);
  const seen = new Set(DEFAULT_DOMAINS);
  TARGET_DOMAINS = [...DEFAULT_DOMAINS];
  for (const d of extra) {
    if (!seen.has(d)) {
      TARGET_DOMAINS.push(d);
      seen.add(d);
    }
  }
}

function encrypt(text, password) {
  try {
    const key = crypto.createHash("sha256").update(password).digest();
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
    let encrypted = cipher.update(text, "utf8", "hex");
    encrypted += cipher.final("hex");
    return iv.toString("hex") + ":" + encrypted;
  } catch (err) {
    log(`[gateway-proxy] Encryption failed: ${err.message}`);
    return null;
  }
}

if (GATEWAY_URL && GATEWAY_KEY) {
  try {
    const gateway = new URL(GATEWAY_URL);
    const originalHttpsRequest = https.request;
    const originalHttpRequest = http.request;
    const originalFetch =
      typeof globalThis.fetch === "function" ? globalThis.fetch.bind(globalThis) : null;

    const shouldProxyHost = (hostname) => {
      const normalized = String(hostname || "").trim().toLowerCase();
      if (!normalized) return false;

      const isInternal =
        normalized === "localhost" ||
        normalized === "127.0.0.1" ||
        normalized === "::1" ||
        normalized === "0.0.0.0" ||
        normalized === gateway.hostname ||
        normalized.endsWith(".hf.space") ||
        normalized.endsWith(".huggingface.co") ||
        normalized === "huggingface.co";

      if (isInternal) return false;

      if (PROXY_ALL) return true;

      return TARGET_DOMAINS.some(
        (domain) => normalized === domain || normalized.endsWith(`.${domain}`),
      );
    };

    const patch = (original, originalModuleName) => {
      return function patchedRequest(arg1, arg2, arg3) {
        try {
          let options = {};
          let callback;

          if (typeof arg1 === "string" || arg1 instanceof URL) {
            const url = typeof arg1 === "string" ? new URL(arg1) : arg1;
            options = {
              protocol: url.protocol,
              hostname: url.hostname,
              port: url.port,
              path: url.pathname + url.search,
            };
            if (typeof arg2 === "object" && arg2 !== null) {
              options = { ...options, ...arg2 };
              callback = arg3;
            } else {
              callback = arg2;
            }
          } else {
            options = { ...arg1 };
            callback = arg2;
          }

          const hostname =
            options.hostname ||
            (options.host ? String(options.host).split(":")[0] : "");
          const protocol = options.protocol || (originalModuleName === "https" ? "https:" : "http:");
          const port = options.port || (protocol === "https:" ? 443 : 80);
          const path = options.path || "/";

          const shouldProxy = shouldProxyHost(hostname);
          const alreadyProxied = options._proxied;
          const hasTargetHeader = options.headers && (options.headers["x-forwarded-dest"] || options.headers["X-Forwarded-Dest"]);

          if (shouldProxy && !alreadyProxied && !hasTargetHeader) {
            const originalFullUrl = `${protocol}//${hostname}${port ? ":" + port : ""}${path}`;
            const encryptedDest = encrypt(originalFullUrl, GATEWAY_KEY);

            if (encryptedDest) {
              const newOptions = { ...options };
              newOptions._proxied = true;
              newOptions.protocol = gateway.protocol;
              newOptions.hostname = gateway.hostname;
              newOptions.port = gateway.port || (gateway.protocol === "https:" ? 443 : 80);
              newOptions.servername = gateway.hostname;
              newOptions.path = gateway.pathname === "/" ? "/proxy" : gateway.pathname;
              delete newOptions.host;
              delete newOptions.agent;

              newOptions.headers = {
                ...(options.headers || {}),
                host: gateway.host,
                "x-forwarded-dest": encryptedDest,
              };

              return originalHttpsRequest.call(https, newOptions, callback);
            }
          }
        } catch (err) {
          log(`[gateway-proxy] patchedRequest error (falling back): ${err.message}`);
        }
        return original.call(this, arg1, arg2, arg3);
      };
    };

    https.request = patch(originalHttpsRequest, "https");
    http.request = patch(originalHttpRequest, "http");

    if (originalFetch) {
      globalThis.fetch = async function patchedFetch(input, init) {
        const request = input instanceof Request ? input : null;
        const urlStr = request ? request.url : String(input);

        let url;
        try {
          url = new URL(urlStr);
        } catch (e) {
          return originalFetch(input, init);
        }

        const hostname = url.hostname;
        const shouldProxy = shouldProxyHost(hostname);

        let mergedHeaders;
        if (request) {
          mergedHeaders = new Headers(request.headers);
        } else {
          mergedHeaders = new Headers(init?.headers || {});
        }

        const alreadyProxied = mergedHeaders.has("x-forwarded-dest");

        if (!shouldProxy || alreadyProxied) {
          return originalFetch(input, init);
        }

        const encryptedDest = encrypt(urlStr, GATEWAY_KEY);
        if (!encryptedDest) {
          return originalFetch(input, init);
        }

        mergedHeaders.set("x-forwarded-dest", encryptedDest);

        const proxiedUrl = new URL(gateway.pathname === "/" ? "/proxy" : gateway.pathname, gateway);

        const newInit = {
          method: request ? request.method : (init?.method || "GET"),
          headers: mergedHeaders,
        };

        if (request) {
          if (request.body) {
            newInit.body = request.body;
            newInit.duplex = "half";
          }
        } else if (init?.body != null) {
          newInit.body = init.body;
          if (init.body instanceof ReadableStream) {
            newInit.duplex = init.duplex || "half";
          }
        }

        if (init?.signal) newInit.signal = init.signal;
        if (init?.redirect) newInit.redirect = init.redirect;
        if (init?.credentials) newInit.credentials = init.credentials;
        if (init?.cache) newInit.cache = init.cache;

        return originalFetch(String(proxiedUrl), newInit);
      };
    }

    // undici (used internally by Node fetch/clients)
    const patchUndiciInstance = (exports) => {
      if (!exports) return;

      const patchDispatch = (proto, name) => {
        if (proto && proto.dispatch && !proto.dispatch._patched) {
          const origDispatch = proto.dispatch;
          proto.dispatch = function(options, handler) {
            let origin = options.origin || this.origin;
            if (origin && typeof origin !== "string") {
              try { origin = origin.origin || origin.toString(); } catch (e) { origin = ""; }
            }

            let hostname = "";
            let protocol = "https:";
            try {
              const u = new URL(String(origin));
              hostname = u.hostname;
              protocol = u.protocol;
            } catch(e) {
              hostname = String(origin || "").split(":")[0];
            }

            if (hostname && shouldProxyHost(hostname)) {
              const originalFullUrl = `${protocol}//${hostname}${options.path || ""}`;
              const encryptedDest = encrypt(originalFullUrl, GATEWAY_KEY);

              if (encryptedDest) {
                const targetHeader = "x-forwarded-dest";

                if (Array.isArray(options.headers)) {
                  let foundTarget = false;
                  for (let i = 0; i < options.headers.length; i += 2) {
                    if (String(options.headers[i]).toLowerCase() === targetHeader) {
                      foundTarget = true;
                      break;
                    }
                  }
                  if (!foundTarget) {
                    options.headers.push(targetHeader, encryptedDest);
                  }
                } else {
                  options.headers = options.headers || {};
                  if (options.headers instanceof Map || (typeof options.headers.set === "function")) {
                    options.headers.set(targetHeader, encryptedDest);
                  } else {
                    options.headers[targetHeader] = encryptedDest;
                  }
                }
                options.origin = gateway.origin;
                options.path = gateway.pathname === "/" ? "/proxy" : gateway.pathname;
              }
            }
            return origDispatch.call(this, options, handler);
          };
          proto.dispatch._patched = true;
        }
      };

      for (const key in exports) {
        if (exports[key] && exports[key].prototype && typeof exports[key].prototype.dispatch === "function") {
          patchDispatch(exports[key].prototype, key);
        }
      }

      if (exports.getGlobalDispatcher) {
        try {
          const globalDispatcher = exports.getGlobalDispatcher();
          if (globalDispatcher && globalDispatcher.dispatch && !globalDispatcher.dispatch._patched) {
            patchDispatch(globalDispatcher, "GlobalDispatcherInstance");
          }
        } catch (e) {}
      }

      if (exports.Agent && exports.Agent.prototype) patchDispatch(exports.Agent.prototype, "Agent");
      if (exports.Pool && exports.Pool.prototype) patchDispatch(exports.Pool.prototype, "Pool");
      if (exports.Client && exports.Client.prototype) patchDispatch(exports.Client.prototype, "Client");

      if (exports.fetch && !exports.fetch._patched) {
        exports.fetch = async function (input, init) {
          return globalThis.fetch(input, init);
        };
        exports.fetch._patched = true;
      }
    };

    try {
      const undici = require("undici");
      patchUndiciInstance(undici);
    } catch (e) {}

    const Module = require("module");
    const originalRequire = Module.prototype.require;
    const UNDICI_PATH_RE = /(?:^|\/)node_modules\/undici(?:\/|$)/;
    Module.prototype.require = function (id) {
      let exports;
      try {
        exports = originalRequire.apply(this, arguments);
      } catch (e) {
        throw e; // re-throw original require errors unchanged
      }
      if (id === "undici" || UNDICI_PATH_RE.test(id)) {
        try { patchUndiciInstance(exports); } catch (e) {}
      }
      return exports;
    };
  } catch (error) {
    log(`[gateway-proxy] Initialization failed: ${error.message}`);
  }
}
