import { expect, type Page } from "@playwright/test";

/** Local test infrastructure: Mailpit (captured email) and the local Supabase Auth admin API. Never production. */
const MAILPIT = process.env.MAILPIT_URL ?? "http://127.0.0.1:54324";
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321";

function secretKey(): string {
  const k = process.env.SUPABASE_SECRET_KEY;
  if (!k) throw new Error("SUPABASE_SECRET_KEY is required for e2e (local stack only)");
  if (!SUPABASE_URL.includes("127.0.0.1") && !SUPABASE_URL.includes("localhost"))
    throw new Error("e2e refuses to run against a non-local Supabase");
  return k;
}

export async function latestCode(to: string, after: Date): Promise<string> {
  for (let i = 0; i < 40; i++) {
    const res = await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${to}"`)}`);
    const j = (await res.json()) as { messages: { ID: string; Created: string; Subject: string }[] };
    const m = j.messages?.find((x) => new Date(x.Created) >= new Date(after.getTime() - 2000));
    const code = m?.Subject.match(/\b(\d{6})\b/)?.[1];
    if (code) return code;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`no code email for ${to}`);
}

export async function ensureStaffUser(email: string, password: string): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}`, "content-type": "application/json" },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  if (!res.ok && res.status !== 422) throw new Error(`create user failed ${res.status} ${await res.text()}`);
}

export async function fillCode(page: Page, code: string) {
  const first = page.getByRole("textbox").first();
  await first.click();
  await page.keyboard.type(code);
  await expect(page.locator('input[name="code"]')).toHaveValue(code);
}
