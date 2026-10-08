import { describe, expect, it } from "vitest";
import {
  ALERT_LABEL, DIGEST_TYPES, DIGEST_TYPE_GROUPS, OUTLOOK_LABEL, POOL_GROUPS, POOL_GROUP_HINT, POOL_GROUP_LABEL, STREAM_LABEL,
  delta, digestTypeGroups, durationText, flowByDestination, gainText, insightHref, insightTitle, poolDecidesText, poolGroupLabel, poolPaidText, slaShare,
  type Insight, type PoolRow,
} from "./overview";
import { GOLIVE_LABEL, goliveBlocking, golivePasses } from "./routing";

describe("command center helpers", () => {
  it("compares with the same hours yesterday", () => {
    expect(delta(0, 0)).toBeNull();
    expect(delta(5, 0)).toEqual({ text: "+5 vs 0", tone: "up" });
    expect(delta(6, 4)).toEqual({ text: "+50% vs yesterday", tone: "up" });
    expect(delta(2, 4)).toEqual({ text: "-50% vs yesterday", tone: "down" });
    expect(delta(4, 4)?.tone).toBe("flat");
  });
  it("gives SLA compliance only once a deadline has passed", () => {
    expect(slaShare(0, 0)).toBeNull();
    expect(slaShare(3, 4)).toBe(0.75);
  });
  it("groups the flow by destination, largest first", () => {
    const rows = flowByDestination([
      { source: "witty", destination: "Acme", n: 3 },
      { source: "meta", destination: "B2C sales", n: 5 },
      { source: "meta", destination: "Acme", n: 4 },
    ]);
    expect(rows.map((r) => [r.destination, r.n])).toEqual([["Acme", 7], ["B2C sales", 5]]);
    expect(rows[0]?.sources.map((s) => s.source)).toEqual(["meta", "witty"]);
  });
});

describe("alert digest types (C87)", () => {
  it("lists the 29 types of admin_alerts.types (m28b seed + m31o merge) once each, never alert.metric", () => {
    expect(DIGEST_TYPES).toHaveLength(29);
    expect(new Set(DIGEST_TYPES).size).toBe(29);
    expect(DIGEST_TYPES).not.toContain("alert.metric");
    for (const t of DIGEST_TYPES) expect(t).toMatch(/^(alert\.[a-z_]+|routing\.error)$/);
    const seeded = ["alert.partner_auto_paused", "alert.ncpl_drop", "alert.model_fallback", "alert.sla_breach", "alert.reconciliation_items",
                    "alert.partner_bad_signature", "alert.notification_failed", "alert.ai_budget", "alert.ai_run_failed", "routing.error"];
    const merged = ["alert.partner_rejected", "alert.commission_dispute", "alert.consent_unsendable", "alert.consent_withdrawn", "alert.partner_recall_notice",
                    "alert.partner_optout_notice", "alert.push_collect_error", "alert.erasure_requested", "alert.ai_rollback", "alert.ai_review_worse",
                    "alert.schedule_failed", "alert.metric_invalid", "alert.push_failed", "alert.mapping_drift", "alert.programme_sheet_failed",
                    "alert.webhook_dead", "alert.intake_failed", "alert.partner_auth", "alert.capi_auth"];
    expect([...DIGEST_TYPES].sort()).toEqual([...seeded, ...merged].sort());
  });
  it("every digest type has an ALERT_LABEL, and the groups cover the list exactly once", () => {
    for (const t of DIGEST_TYPES) expect(ALERT_LABEL[t], t).toBeTruthy();
    expect(DIGEST_TYPE_GROUPS.flatMap((g) => g.types)).toEqual(DIGEST_TYPES);
  });
  it("labels the A3 alert and feed types the Command Center and the alert feed show", () => {
    for (const t of ["alert.consent_unsendable", "alert.consent_withdrawn", "alert.partner_recall_notice", "alert.partner_rejected", "alert.push_collect_error",
                     "alert.ncpl_drop", "alert.model_fallback", "alert.partner_auto_paused", "alert.ai_budget", "alert.ai_run_failed", "alert.ai_rollback",
                     "alert.ai_review_worse", "alert.schedule_failed", "alert.metric_invalid", "lead.reenquired", "lead.partner_barred"]) {
      expect(ALERT_LABEL[t], t).toBeTruthy();
    }
  });
  it("the form shows the known types and appends unknown saved ones under Other", () => {
    expect(digestTypeGroups(["alert.sla_breach"])).toBe(DIGEST_TYPE_GROUPS);
    const g = digestTypeGroups(["alert.sla_breach", "alert.custom_thing", "alert.custom_thing"]);
    expect(g.at(-1)).toEqual({ label: "Other", types: ["alert.custom_thing"] });
    expect(g.flatMap((x) => x.types)).toHaveLength(30);
  });
});

describe("insight cards (C91)", () => {
  const rec: Insight = { source: "recommendation", id: 1, kind: "effort_weights", title: "Raise the first-call weight", gain_pct: 5.25, occurred_at: "2026-10-07T10:00:00Z", partner_id: null };
  it("links recommendations to the AI screen, anomalies to their partner, otherwise to the AI screen", () => {
    expect(insightHref(rec)).toBe("/ai");
    expect(insightHref({ ...rec, source: "anomaly", kind: "alert.partner_auto_paused", partner_id: 7 })).toBe("/partners/7");
    expect(insightHref({ ...rec, source: "anomaly", kind: "alert.model_fallback", partner_id: null })).toBe("/ai");
  });
  it("titles an anomaly with its alert label and formats the simulated gain", () => {
    expect(insightTitle(rec)).toBe("Raise the first-call weight");
    expect(insightTitle({ ...rec, source: "anomaly", kind: "alert.partner_auto_paused", title: "alert.partner_auto_paused" })).toBe("Partner paused automatically");
    expect(insightTitle({ ...rec, source: "anomaly", kind: "alert.unknown_thing", title: "alert.unknown_thing" })).toBe("alert.unknown_thing");
    expect(gainText(5.25)).toBe("+5.3%");
    expect(gainText(-1)).toBe("−1%");
    expect(gainText(0)).toBe("0%");
  });
});

describe("outlook, pool groups and the go-live checklist", () => {
  it("OUTLOOK_LABEL covers every route_outlook value (CONTRACT 1.3)", () => {
    for (const o of ["none", "not_passed", "b2c_sales", "b2c_nurture", "b2c", "b2c_held", "with_partner", "consent_pending", "consent_request", "partners"]) {
      expect(OUTLOOK_LABEL[o], o).toBeTruthy();
    }
  });
  it("POOL_GROUPS and the labels and hints cover pool_lead's groups (m31f) exactly", () => {
    const groups = ["test", "opted_out", "held", "awaiting_consent", "waiting_inactivity", "chatting", "too_old", "routing_off", "due"];
    expect([...POOL_GROUPS].sort()).toEqual([...groups].sort());
    for (const g of groups) {
      expect(POOL_GROUP_LABEL[g as (typeof POOL_GROUPS)[number]], g).toBeTruthy();
      expect(POOL_GROUP_HINT[g as (typeof POOL_GROUPS)[number]], g).toBeTruthy();
    }
    expect(POOL_GROUP_LABEL.awaiting_consent).toBe("Awaiting partner-sharing consent");
    expect(POOL_GROUP_LABEL.waiting_inactivity).toBe("Waiting for 18 h of inactivity");
    expect(poolGroupLabel("waiting_inactivity", 24)).toBe("Waiting for 24 h of inactivity");
    expect(poolGroupLabel("waiting_inactivity", null)).toBe("Waiting for 18 h of inactivity");
    expect(poolGroupLabel("chatting", 24)).toBe(POOL_GROUP_LABEL.chatting);
  });
  it("labels the A3 stream events", () => {
    for (const t of ["lead.recalled", "lead.requalified", "lead.reenquired", "lead.partner_lost", "lead.partner_revived", "lead.partner_barred", "lead.consent_requested", "lead.consent_answered"]) {
      expect(STREAM_LABEL[t], t).toBeTruthy();
    }
  });
  it("the checklist uses W1's rules: a blocking item that neither passes nor is acknowledged blocks", () => {
    const items = [
      { key: "consent_texts_approved", ok: false, blocking: true, why: "2 texts unapproved" },
      { key: "witty_w1_consent_line", ok: false, blocking: true, acknowledgeable: true, acked: true, ack: { reason: "W1 goes live on Monday", by: "admin", at: "2026-10-07T10:00:00Z" }, why: null },
      { key: "b2c_endpoint_subscribed", ok: true, blocking: true, why: null },
      { key: "witty_w2_consent_request", ok: false, blocking: true, acknowledgeable: true, acked: false, why: "w2_consent_request missing" },
      { key: "live_partner", ok: false, blocking: false, why: "no live partner" },
    ];
    expect(goliveBlocking(items).map((i) => i.key)).toEqual(["consent_texts_approved", "witty_w2_consent_request"]);
    expect(items.map(golivePasses)).toEqual([false, true, true, false, false]);
    for (const i of items) expect(GOLIVE_LABEL[i.key], i.key).toBeTruthy();
  });
});

describe("pool rows", () => {
  const now = Date.parse("2026-10-08T06:00:00Z");
  const row = (p: Partial<PoolRow>): PoolRow => ({
    id: 1, name: "A", source: "witty", course: "MBA", status: "UNQUALIFIED", created_at: "2026-10-07T20:00:00Z", last_seen: null, group: "due", class: "qualified",
    class_reason: null, not_qualified: [], missing: [], paid: false, paid_platform: null, import_id: null, outlook: "partners", outlook_reason: null, outlook_lane: null,
    wait: null, decide_after: null, ...p,
  });
  it("counts down a stored wait and says 'queued' while a consent request waits for the hourly budget", () => {
    expect(poolDecidesText(row({ group: "waiting_inactivity", decide_after: "2026-10-08T09:30:00Z", wait: { kind: "inactivity", why: "unqualified", until: "2026-10-08T09:30:00Z", last_inbound: null, hours: 18 } }), now)).toBe("in 4 h");
    expect(poolDecidesText(row({ group: "chatting", decide_after: "2026-10-08T06:20:00Z", wait: { kind: "chatting", why: null, until: "2026-10-08T06:20:00Z", last_inbound: null } }), now)).toBe("in 20 min");
    expect(poolDecidesText(row({ group: "chatting", decide_after: "2026-10-08T05:00:00Z", wait: { kind: "chatting", why: null, until: "2026-10-08T05:00:00Z", last_inbound: null } }), now)).toBe("now");
    expect(poolDecidesText(row({ group: "awaiting_consent", decide_after: "2026-10-10T06:00:00Z", wait: { kind: "consent", why: null, until: "2026-10-10T06:00:00Z", last_inbound: null, status: "sent" } }), now)).toBe("answer due in 2 days");
    expect(poolDecidesText(row({ group: "awaiting_consent", decide_after: "2026-10-08T06:15:00Z", wait: { kind: "consent", why: null, until: "2026-10-08T06:15:00Z", last_inbound: null, status: "queued" } }), now)).toBe("queued: waits for the hourly request budget");
    expect(poolDecidesText(row({ group: "awaiting_consent", decide_after: "2026-10-09T06:00:00Z", wait: { kind: "consent", why: null, until: "2026-10-09T06:00:00Z", last_inbound: null, status: "unsendable" } }), now)).toBe("request could not be sent; in 24 h");
  });
  it("says what has to happen first when nothing is stored", () => {
    expect(poolDecidesText(row({ group: "due" }), now)).toBe("next run, within a minute");
    expect(poolDecidesText(row({ group: "routing_off" }), now)).toBe("when automatic routing is on");
    expect(poolDecidesText(row({ group: "held" }), now)).toBe("when released");
    expect(poolDecidesText(row({ group: "opted_out" }), now)).toBe("never");
    expect(poolDecidesText(row({ group: "test" }), now)).toBe("by hand only (sandbox)");
  });
  it("names the paid platform", () => {
    expect(poolPaidText(row({ paid: false, paid_platform: "meta" }))).toBeNull();
    expect(poolPaidText(row({ paid: true, paid_platform: "meta" }))).toBe("Paid · Meta ads");
    expect(poolPaidText(row({ paid: true, paid_platform: "google" }))).toBe("Paid · Google ads");
    expect(poolPaidText(row({ paid: true, paid_platform: null }))).toBe("Paid");
  });
  it("formats durations", () => {
    expect(durationText(20_000)).toBe("under a minute");
    expect(durationText(25 * 60_000)).toBe("25 min");
    expect(durationText(17.6 * 3_600_000)).toBe("18 h");
    expect(durationText(72 * 3_600_000)).toBe("3 days");
  });
});
