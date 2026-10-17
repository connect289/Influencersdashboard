import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { allowedVars, channelLocked, channelOn, EVENT_KEYS, EVENTS, eventsFor } from "./catalogue";

const migrations = join(import.meta.dirname, "..", "..", "supabase", "migrations");

describe("event catalogue", () => {
  it("lists every event the database emits", () => {
    const sql = readdirSync(migrations)
      .filter((f) => f.endsWith(".sql"))
      .map((f) => readFileSync(join(migrations, f), "utf8"))
      .join("\n");
    const emitted = new Set([...sql.matchAll(/notify[a-z_]*\([^;]*?'([a-z]+\.[a-z_]+)'/g)].map((m) => m[1] ?? ""));
    // Staff-notify helpers also take a permission key ("deal.write"); those are not events.
    const missing = [...emitted].filter((e) => !(EVENT_KEYS as string[]).includes(e) && !(e in PERMISSIONS));
    expect(missing).toEqual([]);
  });

  it("covers the spec 14 minimum catalogue", () => {
    for (const k of [
      "campaign.invited",
      "application.accepted",
      "contract.sent",
      "contract.updated",
      "contract.change_requested",
      "contract.ready",
      "contract.creator_signed",
      "contract.active",
      "contract.expiring",
      "brief.published",
      "brief.updated",
      "deliverable.due",
      "deliverable.overdue",
      "deliverable.changes_requested",
      "deliverable.approved",
      "deliverable.verified",
      "deliverable.metrics_due",
      "lead.new",
      "lead.enrolled",
      "lead.clawed_back",
      "ledger.payable",
      "payout.paid",
      "kyc.action_needed",
      "announcement",
      "fraud.flagged",
      "staff.negotiation_pending",
      "staff.review_pending",
    ])
      expect(EVENT_KEYS).toContain(k);
  });

  it("keeps contract and payout events mandatory", () => {
    for (const k of ["contract.sent", "contract.ready", "contract.active", "payout.paid", "ledger.payable"] as const)
      expect(EVENTS[k].mandatory).toBe(true);
  });

  it("gives templates the common variables plus the event's own", () => {
    expect(allowedVars("payout.paid")).toEqual(["name", "title", "body", "link", "amount", "utr"]);
    expect(allowedVars("nope.event")).toEqual(["name", "title", "body", "link"]);
  });

  it("lists events per audience", () => {
    expect(eventsFor("creator")).toContain("payout.paid");
    expect(eventsFor("creator")).not.toContain("fraud.flagged");
    expect(eventsFor("staff")).toContain("fraud.flagged");
    expect(eventsFor("agency")).toContain("contract.sent");
  });
});

describe("channel preferences", () => {
  it("locks mandatory events and in-app on", () => {
    const off = [{ event: "payout.paid", channel: "email" as const, enabled: false }];
    expect(channelOn("payout.paid", "email", off)).toBe(true);
    expect(
      channelOn("thread.message", "in_app", [{ event: "thread.message", channel: "in_app", enabled: false }]),
    ).toBe(true);
    // A mandatory event's other channels are the person's choice (off unless switched on).
    expect(channelOn("kyc.reviewed", "whatsapp", [])).toBe(false);
    expect(channelOn("kyc.reviewed", "whatsapp", [{ event: "kyc.reviewed", channel: "whatsapp", enabled: true }])).toBe(
      true,
    );
    expect(channelLocked("kyc.reviewed", "email")).toBe(true);
    expect(channelLocked("kyc.reviewed", "whatsapp")).toBe(false);
    expect(channelLocked("lead.enrolled", "email")).toBe(false);
    expect(channelLocked("lead.enrolled", "in_app")).toBe(true);
  });

  it("uses the person's choice, else the catalogue default", () => {
    expect(channelOn("lead.new", "email", [])).toBe(false);
    expect(channelOn("lead.enrolled", "whatsapp", [])).toBe(true);
    expect(
      channelOn("lead.enrolled", "whatsapp", [{ event: "lead.enrolled", channel: "whatsapp", enabled: false }]),
    ).toBe(false);
    expect(channelOn("lead.new", "email", [{ event: "lead.new", channel: "email", enabled: true }])).toBe(true);
  });
});
