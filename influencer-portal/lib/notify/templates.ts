// Transactional email bodies (sign-in). Business notification templates live in inf.notification_templates.
import type { EmailMessage } from "./types";

export function escapeHtml(s: string): string {
  return s.replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] ?? c,
  );
}

function layout(title: string, bodyHtml: string): string {
  return `<!doctype html><html><body style="margin:0;background:#F2F4F7;font-family:Arial,Helvetica,sans-serif;color:#0E2240">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" style="max-width:520px;background:#FFFFFF;border-radius:14px;padding:28px" cellpadding="0" cellspacing="0">
<tr><td style="font-size:20px;font-weight:bold;color:#0B2F5E;padding-bottom:4px">Eduwit <span style="color:#8A5A00">Creators</span></td></tr>
<tr><td style="font-size:18px;font-weight:bold;padding:16px 0 8px">${escapeHtml(title)}</td></tr>
<tr><td style="font-size:15px;line-height:1.5">${bodyHtml}</td></tr>
<tr><td style="font-size:12px;color:#5C6F87;padding-top:24px">Eduwit Learning Services · You received this because someone signed in to the Eduwit portal with your email. If it wasn't you, ignore this email and tell your Eduwit contact.</td></tr>
</table></td></tr></table></body></html>`;
}

export function staffCodeEmail(code: string, name: string): Omit<EmailMessage, "to"> {
  const safe = /^\d{6}$/.test(code) ? code : "------";
  return {
    subject: `${safe} is your Eduwit sign-in code`,
    html: layout(
      "Your sign-in code",
      `<p>Hi ${escapeHtml(name)},</p><p>Enter this code to finish signing in. It expires in 10 minutes and works once.</p>
<p style="font-size:32px;letter-spacing:6px;font-weight:bold;color:#0B2F5E;margin:20px 0">${safe}</p>`,
    ),
    text: `Hi ${name},\n\nYour Eduwit sign-in code is ${safe}. It expires in 10 minutes and works once.\n\nIf it wasn't you, ignore this email.`,
  };
}

export function passwordLinkEmail(link: string, name: string): Omit<EmailMessage, "to"> {
  return {
    subject: "Set your Eduwit portal password",
    html: layout(
      "Set your password",
      `<p>Hi ${escapeHtml(name)},</p><p>Use this link to set your password. It works once, for one hour.</p>
<p style="margin:20px 0"><a href="${escapeHtml(link)}" style="background:#0B2F5E;color:#FFFFFF;padding:12px 18px;border-radius:10px;text-decoration:none;font-weight:bold">Set password</a></p>`,
    ),
    text: `Hi ${name},\n\nSet your Eduwit portal password with this link (works once, for one hour):\n${link}\n`,
  };
}

export function agencyInviteEmail(loginUrl: string, name: string, agencyName: string): Omit<EmailMessage, "to"> {
  return {
    subject: `You've been added to ${agencyName} on Eduwit Creators`,
    html: layout(
      "You're invited",
      `<p>Hi ${escapeHtml(name)},</p><p>You've been added to <strong>${escapeHtml(agencyName)}</strong> on the Eduwit creator portal, where you can manage the creators who link their accounts to your agency.</p>
<p>Sign in with this email address; we'll email you a code each time.</p>
<p style="margin:20px 0"><a href="${escapeHtml(loginUrl)}" style="background:#0B2F5E;color:#FFFFFF;padding:12px 18px;border-radius:10px;text-decoration:none;font-weight:bold">Sign in</a></p>`,
    ),
    text: `Hi ${name},\n\nYou've been added to ${agencyName} on the Eduwit creator portal. Sign in with this email address (we'll email you a code):\n${loginUrl}\n`,
  };
}
