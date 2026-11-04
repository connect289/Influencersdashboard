// The sign-in code email: plain, short, no tracking, the wordmark only (spec §12 brand). Pure, so it is unit-tested.

export function codeEmail(
  code: string,
  minutes: number,
  oneHost: string,
): { subject: string; text: string; html: string } {
  if (!/^\d{6}$/.test(code)) throw new Error("a sign-in code is 6 digits");
  const spaced = `${code.slice(0, 3)} ${code.slice(3)}`;
  const text = [
    `Your Eduwit One sign-in code is ${spaced}.`,
    "",
    `It works once, for ${minutes} minutes, on the browser where you asked for it.`,
    "If you did not try to sign in, you can ignore this email; someone who knows your Google password would still need this code.",
    "",
    oneHost,
  ].join("\n");
  const html = [
    '<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#0B1F33;max-width:480px">',
    '<p style="font-weight:600;color:#072E59;margin:0 0 16px">Eduwit <span style="color:#8A4B00">One</span></p>',
    "<p>Your sign-in code is</p>",
    `<p style="font-size:28px;font-weight:700;letter-spacing:4px;margin:8px 0 16px">${spaced}</p>`,
    `<p>It works once, for ${minutes} minutes, on the browser where you asked for it.</p>`,
    '<p style="color:#475569;font-size:13px">If you did not try to sign in, you can ignore this email.</p>',
    "</div>",
  ].join("");
  return { subject: `Eduwit One sign-in code: ${spaced}`, text, html };
}
