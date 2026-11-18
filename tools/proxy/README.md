# Avida Claude proxy (Cloudflare Worker)

The app never holds the Anthropic API key. It calls this Worker with a shared app token; the Worker adds the
key (stored as a Cloudflare secret) and forwards the request to `https://api.anthropic.com/v1/messages`.

What it enforces:
- Only `POST /v1/messages`.
- The `x-avida-token` header must match the `APP_TOKEN` secret (constant-time check).
- Only models in `ALLOWED_MODELS` (default `claude-haiku-5-5`), `max_tokens` ≤ `MAX_TOKENS_CAP` (default 4096),
  no streaming, body ≤ 64 KB. This limits what a leaked app token can cost you.
- Request and response bodies are never logged.

The app token ships inside the app, so treat it as a speed bump, not real security: anyone with the app binary
could extract it. Set a monthly spend limit on your Anthropic account (step 7) and rotate the token if it leaks.

## Deploy, step by step

You need Node.js 18+ (`node -v`) and a free Cloudflare account.

1. **Go to this folder**
   ```bash
   cd tools/proxy
   ```

2. **Log in to Cloudflare** (opens a browser):
   ```bash
   npx wrangler login
   ```

3. **Deploy the Worker.** Wrangler prints the URL, e.g. `https://avida-claude-proxy.<your-subdomain>.workers.dev`.
   ```bash
   npx wrangler deploy
   ```
   Until the secrets below are set, every request returns a 500 "missing secret" error. That's expected.

4. **Add your Anthropic API key as a secret.** Paste the key when prompted; it isn't echoed or saved anywhere
   in the repo. Get a key at console.anthropic.com → API Keys.
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   ```

5. **Create the app token and add it as a secret.** Generate a random token, copy the output, then paste it
   when prompted:
   ```bash
   openssl rand -hex 32
   ```
   ```bash
   npx wrangler secret put APP_TOKEN
   ```
   Secrets apply immediately; no redeploy needed.

6. **Test it** (replace the URL and token):
   ```bash
   curl -s https://avida-claude-proxy.YOUR-SUBDOMAIN.workers.dev/v1/messages -H "content-type: application/json" -H "x-avida-token: YOUR_APP_TOKEN" -d '{"model":"claude-haiku-5-5","max_tokens":256,"messages":[{"role":"user","content":"Say hello in five words."}]}'
   ```
   You should get a JSON message with a `content` array. Without the token you get a 401.

7. **Set a spend limit** at console.anthropic.com → Settings → Limits, so a leaked token can't run up a bill.

8. **Point the app at it.** From the repo root, copy the example config into the app folder and fill in the URL
   (with `/v1/messages`) and the token:
   ```bash
   cp config/LLMConfig.example.json Avida/LLMConfig.json
   ```
   `Avida/LLMConfig.json` is gitignored. Rebuild the app; Xcode bundles the file automatically.

## Day-to-day

- **Rotate the app token:** run step 5 again with a new token, then update `Avida/LLMConfig.json` and rebuild.
- **Rotate the API key:** create a new key in the Anthropic console, run step 4 again, then delete the old key.
- **Logs:** `npx wrangler tail` shows requests and status codes (no bodies).
- **Local testing:** copy `.dev.vars.example` to `.dev.vars` (gitignored), fill it in, and run `npx wrangler dev`.
- **Allow another model or a bigger cap:** edit `[vars]` in `wrangler.toml` and run `npx wrangler deploy`.
