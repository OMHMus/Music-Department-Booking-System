// Sends band invitation emails for the Sexey's Music practice room booking.
//
// Called by the booking page (signed-in band leader) with { member_id }.
// The database function band_invite_email() checks the caller leads the
// band and the invite is still open, so this can't be used to email anyone
// else. Emails go through Brevo (https://www.brevo.com, free plan).
//
// Secrets to set in Supabase (Edge Functions -> Secrets):
//   BREVO_API_KEY       your Brevo API key
//   BREVO_SENDER_EMAIL  a sender address you have verified in Brevo
// Optional:
//   SITE_URL            booking site link (defaults to the GitHub Pages site)
//
// Until the two Brevo secrets are set, it answers { sent:false,
// reason:"not_configured" } and the page falls back to opening the
// pupil's own email app instead.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SITE = Deno.env.get("SITE_URL") ?? "https://omhmus.github.io/Music-Department-Booking-System/";
const ALLOWED = ["https://omhmus.github.io"];

function cors(req: Request) {
  const origin = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED.includes(origin) ? origin : ALLOWED[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

const esc = (s: string) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function buildEmail(d: { band: string; inviter: string; has_account: boolean }) {
  const subject = `${d.inviter} is inviting you to join the band ${d.band}`;
  const steps = d.has_account
    ? [`Log in to the Sexey's practice room booking site.`, `Open <b>My bands</b> and accept (or decline) the invitation.`]
    : [
        `Go to the Sexey's practice room booking site and create an account with this school email address.`,
        `Complete the registration (induction and Practice Room Agreement) and wait for a member of the Music staff to approve you.`,
        `Log in, open <b>My bands</b> and accept the invitation.`,
      ];
  const stepsText = d.has_account
    ? `1. Log in to the Sexey's practice room booking site.\n2. Open My bands and accept (or decline) the invitation.`
    : `1. Go to the booking site and create an account with this school email address.\n2. Complete the registration and wait for a member of the Music staff to approve you.\n3. Log in, open My bands and accept the invitation.`;
  const html = `<!doctype html><html><body style="margin:0;background:#F6F3EF;font-family:Montserrat,Helvetica,Arial,sans-serif;color:#2B1B1C">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F3EF;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #E4DAD1">
<tr><td style="background:#8B292B;color:#ffffff;padding:18px 24px;border-bottom:3px solid #C8A877">
<div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#E9D6B3;font-weight:bold">Sexey's School · Music Department</div>
<div style="font-family:Georgia,serif;font-size:22px;margin-top:4px">Practice Room Booking</div></td></tr>
<tr><td style="padding:24px">
<p style="font-size:17px;margin:0 0 16px"><b>${esc(d.inviter)}</b> is inviting you to join the band <b>${esc(d.band)}</b>.</p>
<p style="margin:0 0 8px">Bands can book practice rooms to rehearse together once every member has accepted.</p>
<ol style="padding-left:20px;margin:0 0 20px">${steps.map((s) => `<li style="margin:0 0 6px">${s}</li>`).join("")}</ol>
<p style="margin:0 0 20px"><a href="${SITE}" style="display:inline-block;background:#8B292B;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 22px;border-radius:999px">${d.has_account ? "Open the booking site" : "Create your account"}</a></p>
<p style="font-size:13px;color:#6F5E5D;margin:0">If you weren't expecting this, you can ignore this email or decline in My bands.</p>
</td></tr></table></td></tr></table></body></html>`;
  const text = `${d.inviter} is inviting you to join the band ${d.band}.\n\n${stepsText}\n\n${SITE}\n\nIf you weren't expecting this, you can ignore this email.`;
  return { subject, html, text };
}

Deno.serve(async (req) => {
  const headers = { ...cors(req), "Content-Type": "application/json" };
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return reply({ sent: false, reason: "method_not_allowed" }, 405);

  const key = Deno.env.get("BREVO_API_KEY");
  const sender = Deno.env.get("BREVO_SENDER_EMAIL");
  if (!key || !sender) return reply({ sent: false, reason: "not_configured" });

  let memberId: number;
  try {
    memberId = Number((await req.json()).member_id);
    if (!Number.isInteger(memberId)) throw new Error();
  } catch {
    return reply({ sent: false, reason: "bad_request" }, 400);
  }

  // Act as the signed-in pupil so the database checks apply to them
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? req.headers.get("apikey") ?? "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, anon, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

  const { data, error } = await sb.rpc("band_invite_email", { p_member: memberId });
  if (error) return reply({ sent: false, reason: "refused", message: error.message });

  const mail = buildEmail(data);
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": key, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      sender: { name: "Sexey's Music Department", email: sender },
      to: [{ email: data.to }],
      replyTo: data.inviter_email ? { email: data.inviter_email, name: data.inviter } : undefined,
      subject: mail.subject,
      htmlContent: mail.html,
      textContent: mail.text,
    }),
  });
  if (!res.ok) {
    console.error("Brevo error", res.status, await res.text());
    await sb.rpc("band_invite_email_failed", { p_member: memberId });
    return reply({ sent: false, reason: "send_failed" });
  }
  return reply({ sent: true, to: data.to });
});
