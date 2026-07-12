# Internet Gateway

Railway-deployed forward proxy for routing traffic through a whitelisted domain (`*.railway.app`).

**Setup scripts & VPS modules:** [o-x-api/internet-gateway-setup](https://github.com/o-x-api/internet-gateway-setup)

---

## Deploy to Railway

```bash
railway login
railway up
```

Railway auto-detects the Node.js app and deploys it. Your proxy will be at `https://your-project.up.railway.app`.

## Usage

Set the Railway URL as your proxy on the VPS:

```bash
export HTTP_PROXY=https://your-project.up.railway.app
export HTTPS_PROXY=https://your-project.up.railway.app
```

Or use the setup script: `bash <(curl -sSL https://raw.githubusercontent.com/o-x-api/internet-gateway-setup/main/Setup/setup.sh)`

## Endpoints

The proxy supports standard HTTP proxy protocol:
- **HTTP GET/POST/PUT/etc**: Full URL in request line (`GET https://example.com/ HTTP/1.1`)
- **CONNECT**: HTTPS tunneling
