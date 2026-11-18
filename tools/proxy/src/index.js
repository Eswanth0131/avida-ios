// Avida → Claude proxy (Cloudflare Worker).
//
// Accepts POST /v1/messages from the Avida app, checks the shared app token,
// adds the Anthropic API key from a Worker secret, and forwards to the Claude API.
// The API key never leaves Cloudflare: it is not in the app or the repo.
//
// Secrets (set with `npx wrangler secret put <NAME>`):
//   ANTHROPIC_API_KEY  your Anthropic API key
//   APP_TOKEN          long random string; the app sends it as the x-avida-token header
// Vars (wrangler.toml):
//   ALLOWED_MODELS     comma-separated model IDs the app may use
//   MAX_TOKENS_CAP     largest max_tokens a request may ask for
//
// Request and response bodies are never logged.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MAX_BODY_BYTES = 64 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/messages") {
      return error(404, "not_found_error", "Not found.");
    }
    if (request.method !== "POST") {
      return error(405, "invalid_request_error", "Use POST.", { Allow: "POST" });
    }
    if (!env.ANTHROPIC_API_KEY || !env.APP_TOKEN) {
      return error(500, "api_error", "Proxy is missing its ANTHROPIC_API_KEY or APP_TOKEN secret.");
    }
    if (!(await tokensMatch(request.headers.get("x-avida-token") ?? "", env.APP_TOKEN))) {
      return error(401, "authentication_error", "Missing or invalid app token.");
    }

    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_BODY_BYTES) {
      return error(413, "request_too_large", "Request body too large.");
    }
    const body = await request.text();
    if (new TextEncoder().encode(body).length > MAX_BODY_BYTES) {
      return error(413, "request_too_large", "Request body too large.");
    }

    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      return error(400, "invalid_request_error", "Body must be JSON.");
    }

    // Limits so a leaked app token can't be used for arbitrary, expensive requests.
    const allowedModels = (env.ALLOWED_MODELS ?? "claude-haiku-5-5").split(",").map((m) => m.trim());
    if (!allowedModels.includes(payload.model)) {
      return error(400, "invalid_request_error", `Model not allowed by this proxy: ${payload.model}`);
    }
    const cap = Number(env.MAX_TOKENS_CAP ?? 4096);
    if (typeof payload.max_tokens !== "number" || payload.max_tokens < 1 || payload.max_tokens > cap) {
      return error(400, "invalid_request_error", `max_tokens must be between 1 and ${cap}.`);
    }
    if (payload.stream) {
      return error(400, "invalid_request_error", "Streaming is not supported by this proxy.");
    }

    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": ANTHROPIC_VERSION,
        },
        body,
      });
    } catch {
      return error(502, "api_error", "Couldn't reach the Claude API.");
    }

    // Pass Claude's status and JSON body straight through (including its error objects).
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        "content-type": upstream.headers.get("content-type") ?? "application/json",
        "cache-control": "no-store",
      },
    });
  },
};

/** Same JSON shape as Claude API errors, so the app parses one format. */
function error(status, type, message, extraHeaders = {}) {
  return new Response(JSON.stringify({ type: "error", error: { type, message } }), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...extraHeaders },
  });
}

/** Constant-time comparison of the provided token with the secret (hashing first equalizes lengths). */
async function tokensMatch(provided, expected) {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  return provided.length > 0 && crypto.subtle.timingSafeEqual(a, b);
}
