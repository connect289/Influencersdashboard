import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import type { BrowserContext, Page } from "@playwright/test";
// @ts-expect-error plain JavaScript shared with the seed script
import { assertStagingKey } from "./fixtures.mjs";

export const STAGING_REF = "mplbspysxmtohnlwpbti"; // the same as e2e/fixtures.mjs: staging only

export type Person = { email: string; password: string; user_id: string; role: string; home: string; name: string };
export type Who = "admin" | "manager" | "asha" | "ravi" | "marketing";

export const people = (): Record<Who, Person> =>
  JSON.parse(readFileSync(new URL("./.auth/passwords.json", import.meta.url), "utf8"));

export const stateFile = (who: Who) => new URL(`./.auth/${who}.json`, import.meta.url).pathname;

export function service() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
  assertStagingKey(key);
  return createClient(`https://${STAGING_REF}.supabase.co`, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** The signed-in browser's Supabase session (user and session id), read from the @supabase/ssr cookie. */
export async function sessionOf(context: BrowserContext): Promise<{ sub: string; session_id: string }> {
  const name = `sb-${STAGING_REF}-auth-token`;
  const cookies = (await context.cookies()).filter((c) => c.name === name || c.name.startsWith(`${name}.`));
  cookies.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
  let raw = cookies.map((c) => c.value).join("");
  if (raw.startsWith("base64-")) raw = Buffer.from(raw.slice(7), "base64url").toString("utf8");
  const token = JSON.parse(raw).access_token as string;
  return JSON.parse(Buffer.from(token.split(".")[1] ?? "", "base64url").toString("utf8"));
}

/** Collects what goes wrong on a page: console errors, failed server actions and uncaught exceptions. */
export function watch(page: Page) {
  const problems: string[] = [];
  page.on("pageerror", (e) => problems.push(`exception: ${e.message}`));
  page.on("console", (m) => {
    if (m.type() !== "error") return;
    const t = m.text();
    if (/favicon|Download the React DevTools|\[Fast Refresh\]|webpack-hmr|_next\/webpack/i.test(t)) return;
    problems.push(`console: ${t.slice(0, 300)}`);
  });
  page.on("response", (r) => {
    if (r.status() >= 500) problems.push(`HTTP ${r.status()} ${r.url().slice(0, 200)}`);
  });
  return problems;
}
