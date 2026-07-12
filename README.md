# Internet Gateway

Vercel-deployed proxy with `/encrypt` and `/raw` endpoints for routing outbound traffic through a whitelisted domain.

**Setup scripts & VPS modules:** [o-x-api/internet-gateway-setup](https://github.com/o-x-api/internet-gateway-setup)

---

## Deploy to Vercel

1. Fork/clone this repo
2. Deploy to Vercel (connect your GitHub repo or use `vercel --prod`)
3. Set `INTERNET_GATEWAY_KEY` environment variable in Vercel dashboard (any random string — must match the one you give to `setup.sh`)

## Bypass Vercel Security (Required)

Vercel's edge firewall blocks automated tools like `curl` by default. To make the proxy work, you must create a bypass rule:

### 1. Disable Vercel Firewall for your project

1. Go to your Vercel project dashboard → **Firewall**
2. Click **Add Rule**
3. **Condition**: `Request Path` → `Starts with` → `/`
4. **Action**: `Bypass`
5. Click **Save Rule**
6. Click **Review Changes** → **Publish**

Ensure this rule sits at the **very top** of your rule list so it triggers before any other security restrictions.

### 2. Check Deployment Protection

1. Go to **Settings** → **Deployment Protection**
2. If **Vercel Authentication** or **Password Protection** is enabled, disable it
3. Or use a **Protection Bypass for Automation** token and pass it as a header

### 3. Verify

After publishing the bypass rule, test with:

```bash
curl -s -A "Mozilla/5.0" https://your-project.vercel.app/
```

Should return `{"status":"ok","message":"Internet Gateway Proxy is active"}`

---

## Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/` | GET | Status check |
| `/encrypt` | GET | Encrypt a URL with `x-forwarded-dest` header, returns `{encrypted}` |
| `/raw` | POST | Accept raw target URL in `x-raw-dest` header (base64url), encrypts server-side and fetches |

**Setup scripts:** [o-x-api/internet-gateway-setup](https://github.com/o-x-api/internet-gateway-setup)
