/**
 * Creates (or refreshes) the test people and test leads on the staging project for the browser tests.
 *   node e2e/seed.mjs
 * Needs SUPABASE_SERVICE_ROLE_KEY for staging. Refuses any project but staging. Safe to run again: people get fresh
 * passwords (written to e2e/.auth/passwords.json, never committed) and leads are sent once (the envelope ids repeat).
 */
import { randomBytes } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { envelopes, LEADS, PRODUCTION_REF, STAFF, STAGING_REF } from "./fixtures.mjs";

const url = process.env.E2E_SUPABASE_URL ?? `https://${STAGING_REF}.supabase.co`;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!key) throw new Error("Set SUPABASE_SERVICE_ROLE_KEY (staging).");
if (url.includes(PRODUCTION_REF) || !url.includes(STAGING_REF)) throw new Error(`Refusing to seed ${url}: staging only.`);

const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
const b2c = db.schema("b2c");

async function findUser(email) {
  for (let page = 1; page < 50; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => u.email === email);
    if (hit || data.users.length < 200) return hit ?? null;
  }
  return null;
}

const passwords = {};
for (const s of STAFF) {
  const password = `E2e-${randomBytes(12).toString("base64url")}`;
  let user = await findUser(s.email);
  if (user) {
    const { error } = await db.auth.admin.updateUserById(user.id, { password, email_confirm: true });
    if (error) throw error;
  } else {
    const { data, error } = await db.auth.admin.createUser({ email: s.email, password, email_confirm: true });
    if (error) throw error;
    user = data.user;
  }
  const { error } = await b2c.from("users").upsert({
    user_id: user.id, email: s.email, full_name: s.full_name, role: s.role, is_active: true, is_test_user: true,
    takes_leads: s.takes_leads, languages: ["English", "Hindi"], deactivated_at: null,
  }, { onConflict: "user_id" });
  if (error) throw error;
  if (s.takes_leads) {
    // works every day, all day, so allocation never waits for working hours during a test run
    const rows = [1, 2, 3, 4, 5, 6, 7].map((d) => ({ user_id: user.id, isodow: d, start_t: "00:00", end_t: "23:59" }));
    const wp = await b2c.from("work_patterns").upsert(rows, { onConflict: "user_id,isodow" });
    if (wp.error) throw wp.error;
  }
  passwords[s.key] = { email: s.email, password, user_id: user.id, role: s.role, home: s.home, name: s.full_name };
  console.log(`person  ${s.email.padEnd(26)} ${s.role}`);
}
mkdirSync(new URL("./.auth/", import.meta.url), { recursive: true });
writeFileSync(new URL("./.auth/passwords.json", import.meta.url), JSON.stringify(passwords, null, 2), { mode: 0o600 });

let applied = 0, duplicates = 0;
for (const lead of LEADS) {
  for (const env of envelopes(lead)) {
    const { data, error } = await b2c.rpc("handoff_receive", { p_env: env, p_via: "test" });
    if (error) throw new Error(`${env.id}: ${error.message}`);
    if (data?.status === "duplicate") duplicates++; else applied++;
  }
}
const { data: state, error } = await b2c.from("leads_state").select("lead_id, owner_id, status").gte("lead_id", 990101).lte("lead_id", 990130);
if (error) throw error;
const owners = Object.fromEntries(Object.values(passwords).map((p) => [p.user_id, p.name]));
const tally = {};
for (const s of state) {
  const k = s.owner_id ? owners[s.owner_id] ?? "someone else" : s.status === "pool" ? "Nurture Pool" : "unassigned";
  tally[k] = (tally[k] ?? 0) + 1;
}
console.log(`leads   ${LEADS.length} (${applied} envelopes applied, ${duplicates} already there)`);
console.log("where   " + Object.entries(tally).map(([k, v]) => `${k}: ${v}`).join(", "));
