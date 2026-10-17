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

/** Unique test identities per run (DB code caps are per email; leads de-duplicate on phone). */
export function uniqueEmail(prefix: string): string {
  return `${prefix}.${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}@example.org`;
}
export function uniquePhone(): string {
  // 10 digits starting 7–9, with enough variety to stay clear of the junk heuristics
  let d = String(7 + Math.floor(Math.random() * 3));
  while (d.length < 10) d += String(Math.floor(Math.random() * 10));
  return /(\d)\1{4}/.test(d) ? uniquePhone() : d;
}
/** Each test gets its own client IP so per-IP limits stay realistic without blocking repeated runs. */
export async function freshIp(page: Page) {
  const ip = `10.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.${1 + Math.floor(Math.random() * 250)}`;
  await page.setExtraHTTPHeaders({ "x-forwarded-for": ip });
}

/** Reads rows from the LOCAL database through PostgREST with the local secret key (assertions only). */
export async function dbSelect<T = Record<string, unknown>>(table: string, query: string): Promise<T[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, {
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}` },
  });
  if (!res.ok) throw new Error(`select ${table} failed ${res.status} ${await res.text()}`);
  return (await res.json()) as T[];
}

/** Types a code into the inline OTP boxes (Radix one-time-code field) inside `scope`. */
export async function typeCode(page: Page, scope: import("@playwright/test").Locator, code: string) {
  await scope.getByRole("textbox").first().click();
  await page.keyboard.type(code);
}

export function wrongCode(code: string): string {
  return code === "111111" ? "222222" : "111111";
}

/** Sets a web_settings flag in the LOCAL database and expires the settings cache (used to switch Witty on/off). */
export async function setSetting(baseURL: string, key: string, value: unknown) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/web_settings?key=eq.${encodeURIComponent(key)}`, {
    method: "PATCH",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}`, "content-type": "application/json", prefer: "return=minimal" },
    body: JSON.stringify({ value }),
  });
  if (!res.ok) throw new Error(`setSetting failed ${res.status} ${await res.text()}`);
  const key2 = process.env.WEB_INTERNAL_KEY ?? "dev-only-internal-key-0000000001";
  const r = await fetch(`${baseURL}/api/internal/revalidate`, {
    method: "POST",
    headers: { authorization: `Bearer ${key2}`, "content-type": "application/json" },
    body: JSON.stringify({ tags: ["settings"], expire_now: true }),
  });
  if (!r.ok) throw new Error(`revalidate failed ${r.status}`);
}

/** Inserts or updates a row in the LOCAL database through PostgREST (test fixtures only). */
export async function dbUpsert(table: string, row: Record<string, unknown>, onConflict: string) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?on_conflict=${onConflict}`, {
    method: "POST",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}`, "content-type": "application/json", prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`upsert ${table} failed ${res.status} ${await res.text()}`);
}

/** Staff sign-in with password + the email-code second factor (admin-auth.spec covers the flow itself). */
export async function adminSignIn(page: Page, email: string, password: string) {
  await ensureStaffUser(email, password);
  await page.goto("/admin/login");
  await page.getByLabel("Work email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/admin\/verify/);
  const sentAt = new Date();
  await page.getByRole("button", { name: "Send code" }).click();
  await expect(page.getByText(/We sent a 6-digit code/)).toBeVisible();
  await fillCode(page, await latestCode(email, sentAt));
  await page.getByRole("button", { name: "Verify" }).click();
  await expect(page.getByRole("heading", { name: "Website admin" })).toBeVisible();
}

/** Clears the LOCAL admin code log so repeated test runs stay under the hourly code cap. */
export async function resetAdminCodes() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/web_admin_codes?id=gte.0`, {
    method: "DELETE",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}` },
  });
  if (!res.ok) throw new Error(`reset admin codes failed ${res.status}`);
}

/** Updates rows in the LOCAL database through PostgREST (test fixtures only; refuses non-local, see secretKey). */
export async function dbPatch(table: string, filter: string, row: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${filter}`, {
    method: "PATCH",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}`, "content-type": "application/json", prefer: "return=minimal" },
    body: JSON.stringify(row),
  });
  if (!res.ok) throw new Error(`patch ${table} failed ${res.status} ${await res.text()}`);
}

/** Calls a function in the LOCAL database (as pg_cron would). */
export async function dbRpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: secretKey(), authorization: `Bearer ${secretKey()}`, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${fn} failed ${res.status} ${await res.text()}`);
  return (await res.json()) as T;
}
