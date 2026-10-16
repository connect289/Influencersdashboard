#!/usr/bin/env node
// Mock B2B sender (Phase 1 plan, exit test): plays the contract's webhook checks against the B2C CRM's /v1/handoffs.
// Uses only test leads (phones 9190000000NN) and lead ids from 990000 up. Run against a local or staging deployment:
//   B2C_URL=http://localhost:3000 B2B_SIGNING_SECRET=whsec_... npm run mock-b2b
import { createHmac } from "node:crypto";

const url = (process.env.B2C_URL ?? "http://localhost:3000").replace(/\/+$/, "") + "/v1/handoffs";
const secret = process.env.B2B_SIGNING_SECRET;
if (!secret) {
  console.error("Set B2B_SIGNING_SECRET (the same value the B2C deployment uses).");
  process.exit(2);
}
const run = Date.now().toString(36);
const leadId = 990000 + Math.floor(Math.random() * 9000);
const phone = "9190000000" + String(leadId % 100).padStart(2, "0");

function sign(body, ts, key = secret) {
  return "sha256=" + createHmac("sha256", key).update(`${ts}.${body}`, "utf8").digest("hex");
}
async function post(env, { ts = Math.floor(Date.now() / 1000), key = secret, tamper = false } = {}) {
  const body = JSON.stringify(env);
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", "x-eduwit-event": env.type, "x-eduwit-timestamp": String(ts), "x-eduwit-signature": sign(body, String(ts), key) },
    body: tamper ? body.replace("}", ' }') : body,
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}
const envelope = (type, data, id = `mock-${run}-${type}`) => ({ id, type, occurred_at: new Date().toISOString(), lead_id: leadId, test: true, contract_version: 3, data });
const record = (version) => ({
  id: leadId, cycle_no: 1, is_test: true, deleted: false, merged_into_id: null, held_by_b2c: true, contract_version: 3, created_at: new Date().toISOString(),
  student: { name: "Mock Test Student", phone, preferred_language: "english", city: "Pune" },
  interest: { course: "Online MBA", other_courses: [] }, consent: { state: "none", partner_share_given: false },
  allocation: { destination: "in_house", b2c_lane: "sales", reason: "no_partner_capacity", allocation_id: 1, reference: "EDW-MOCK" },
  version,
});

const checks = [];
async function check(name, fn) {
  try {
    const ok = await fn();
    checks.push([name, ok === true, ok === true ? "" : JSON.stringify(ok)]);
  } catch (e) {
    checks.push([name, false, String(e)]);
  }
}

await check("ping accepted", async () => (await post(envelope("ping", {}))).status === 200 || "status");
await check("bad signature refused (401)", async () => (await post(envelope("ping", {}, `mock-${run}-bad`), { key: secret + "x" })).status === 401);
await check("tampered body refused (401)", async () => (await post(envelope("ping", {}, `mock-${run}-tamper`), { tamper: true })).status === 401);
await check("stale timestamp refused (401)", async () => (await post(envelope("ping", {}, `mock-${run}-old`), { ts: Math.floor(Date.now() / 1000) - 600 })).status === 401);
await check("lead record stored", async () => {
  const r = await post(envelope("b2c.lead_upserted", { version: 1, seq: 1, origin: "mock", record: record(1) }));
  return r.status === 200 || r;
});
const handoff = envelope("b2c.lead_handed_off", { b2c_lane: "sales", reason: "no_partner_capacity", allocation_id: 1, reference: "EDW-MOCK", handling: {}, test: true });
await check("hand-off applied", async () => {
  const r = await post(handoff);
  return (r.status === 200 && r.body?.result?.status !== "error") || r;
});
await check("same envelope id processed once", async () => {
  const r = await post(handoff);
  return (r.status === 200 && r.body?.result?.status === "duplicate") || r;
});

for (const [name, ok, detail] of checks) console.log(`${ok ? "ok  " : "FAIL"}  ${name}${detail ? "  " + detail : ""}`);
console.log(`\nTest lead ${leadId} (${phone}). Remove it afterwards in the Workspace (Leads → tick → Delete → test).`);
process.exit(checks.every(([, ok]) => ok) ? 0 : 1);
