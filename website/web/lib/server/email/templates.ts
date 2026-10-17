import { COMPANY } from "@/content/site";

/** Transactional email templates (plain, accessible HTML + text). No marketing content (D-017). */
export interface Rendered {
  subject: string;
  text: string;
  html: string;
}

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function layout(title: string, bodyHtml: string): string {
  return `<!doctype html><html lang="en-IN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${esc(title)}</title></head>
<body style="margin:0;background:#f6f8fc;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#0a1a30">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;border:1px solid #e3e8f0">
<tr><td style="padding:24px 28px 8px"><span style="font-size:22px;font-weight:700;color:#062f5b">Edu</span><span style="font-size:22px;font-weight:700;color:#c48000">wit</span></td></tr>
<tr><td style="padding:8px 28px 24px;font-size:15px;line-height:1.6">${bodyHtml}</td></tr>
<tr><td style="padding:16px 28px 24px;border-top:1px solid #e3e8f0;font-size:12px;line-height:1.5;color:#5b6b82">
${esc(COMPANY.name)} · ${esc(COMPANY.address.line1)}, ${esc(COMPANY.address.locality)}, ${esc(COMPANY.address.city)} ${esc(COMPANY.address.postalCode)} · ${esc(COMPANY.phone)}</td></tr>
</table></td></tr></table></body></html>`;
}

/** 6-digit verification code (students: gate/forms/sign-in; staff: second factor). */
export function verificationCodeEmail(code: string, purpose: "verify" | "signin" | "admin", minutes = 10): Rendered {
  const intro =
    purpose === "admin"
      ? "Use this code to finish signing in to the Eduwit website admin."
      : purpose === "signin"
        ? "Use this code to sign in to Eduwit."
        : "Use this code to verify your email address on Eduwit.";
  const subject = `${code} is your Eduwit verification code`;
  const text = `${intro}\n\n${code}\n\nThe code expires in ${minutes} minutes. If you did not ask for it, you can ignore this email.\n\n${COMPANY.name}`;
  const html = layout(
    subject,
    `<p style="margin:0 0 16px">${esc(intro)}</p>
<p style="margin:0 0 16px;font-size:32px;letter-spacing:8px;font-weight:700;font-family:Consolas,Menlo,monospace;color:#062f5b" aria-label="${code.split("").join(" ")}">${esc(code)}</p>
<p style="margin:0 0 8px">The code expires in ${minutes} minutes.</p>
<p style="margin:0;color:#5b6b82">If you did not ask for it, you can ignore this email — someone may have typed your address by mistake.</p>`,
  );
  return { subject, text, html };
}
