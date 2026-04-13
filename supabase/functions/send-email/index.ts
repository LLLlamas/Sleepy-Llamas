// supabase/functions/send-email/index.ts
//
// Sleepy Llamas — Gmail SMTP relay Edge Function
// -----------------------------------------------
// Called by Postgres triggers (sl_notify_owner_of_request, etc.) via pg_net.
// Accepts a generic payload (sender / to / subject / htmlContent) and relays
// through Gmail SMTP using a Google App Password.
//
// Auth: x-edge-secret header must match EDGE_SHARED_SECRET env var.
// verify_jwt is disabled (see supabase/config.toml) because pg_net
// cannot attach JWTs.
//
// Required Supabase secrets (set via `supabase secrets set ...`):
//   GMAIL_USER           — e.g. sleepyllamasdoula@gmail.com
//   GMAIL_APP_PASSWORD   — 16-char Google App Password (NOT the login pw)
//   EDGE_SHARED_SECRET   — high-entropy random string, same value in
//                          app_config.email_fn_secret in Postgres

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

type Addr = { name?: string; email: string };
type Payload = {
  sender: Addr;
  to: Addr[];
  subject: string;
  htmlContent: string;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Constant-time string compare to prevent timing-based secret leaks.
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function formatAddress(a: Addr): string {
  const email = (a.email || "").trim();
  const name = (a.name || "").trim();
  if (!email) return "";
  if (!name) return email;
  const escaped = name.replace(/"/g, '\\"');
  return `"${escaped}" <${email}>`;
}

function isValidEmail(s: string): boolean {
  return typeof s === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

Deno.serve(async (req: Request) => {
  // 1. Method check
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  // 2. Shared secret check
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET") || "";
  const providedSecret = req.headers.get("x-edge-secret") || "";
  if (!expectedSecret) {
    console.error("send-email: EDGE_SHARED_SECRET env var is not set");
    return jsonResponse({ ok: false, error: "server_misconfigured" }, 500);
  }
  if (!safeEqual(providedSecret, expectedSecret)) {
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  // 3. Parse + validate body
  let body: Payload;
  try {
    body = await req.json() as Payload;
  } catch (_e) {
    return jsonResponse({ ok: false, error: "invalid_json" }, 400);
  }

  if (!body || typeof body !== "object") {
    return jsonResponse({ ok: false, error: "empty_body" }, 400);
  }
  if (!body.subject || typeof body.subject !== "string") {
    return jsonResponse({ ok: false, error: "missing_subject" }, 400);
  }
  if (!body.htmlContent || typeof body.htmlContent !== "string") {
    return jsonResponse({ ok: false, error: "missing_html" }, 400);
  }
  if (!Array.isArray(body.to) || body.to.length === 0) {
    return jsonResponse({ ok: false, error: "missing_to" }, 400);
  }
  for (const t of body.to) {
    if (!t || !isValidEmail(t.email)) {
      return jsonResponse({ ok: false, error: "invalid_recipient" }, 400);
    }
  }
  if (!body.sender || !isValidEmail(body.sender.email)) {
    return jsonResponse({ ok: false, error: "invalid_sender" }, 400);
  }

  // 4. Build SMTP client
  const gmailUser = Deno.env.get("GMAIL_USER") || "";
  const gmailPass = Deno.env.get("GMAIL_APP_PASSWORD") || "";
  if (!gmailUser || !gmailPass) {
    console.error("send-email: GMAIL_USER or GMAIL_APP_PASSWORD is not set");
    return jsonResponse({ ok: false, error: "smtp_not_configured" }, 500);
  }

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: {
        username: gmailUser,
        password: gmailPass,
      },
    },
  });

  // 5. Send — Gmail rewrites From: to the authenticated user regardless,
  // so we set From as the Gmail address with the caller's display name.
  // Reply-To points to the caller's sender address.
  const fromDisplay = (body.sender.name || "").trim();
  const fromAddr = formatAddress({
    name: fromDisplay || undefined,
    email: gmailUser,
  });
  const replyToAddr = formatAddress(body.sender);
  const toAddrs = body.to.map(formatAddress).filter(Boolean).join(", ");

  try {
    await client.send({
      from: fromAddr,
      replyTo: replyToAddr || undefined,
      to: toAddrs,
      subject: body.subject,
      content: "This email requires an HTML-capable reader.",
      html: body.htmlContent,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("send-email: SMTP send failed:", msg);
    try { await client.close(); } catch (_) { /* ignore */ }
    return jsonResponse({ ok: false, error: "smtp_send_failed", detail: msg }, 502);
  }

  try { await client.close(); } catch (_) { /* ignore */ }
  return jsonResponse({ ok: true });
});
