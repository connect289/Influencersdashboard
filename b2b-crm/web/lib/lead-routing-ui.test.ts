import { describe, expect, it } from "vitest";
import {
  allocationStatusText, BARRED_SENTENCE, barText, consentBlockReason, consentPanel, drawerBadges, friendlyRouteError, graceCountdown, holdText, lostDialogCopy,
  LOST_SUCCESS_TOAST, nurtureSummary, outlookText, providersSentence, reenquiriesTitle, remainingText, routingActionState, waitText,
} from "./lead-routing-ui";
import type { AllocationRow, LeadRouting } from "./routing-data";

const NOW = Date.parse("2026-10-08T06:00:00Z");
const hours = (h: number) => new Date(NOW + h * 3_600_000).toISOString();

function allocation(p: Partial<AllocationRow>): AllocationRow {
  return {
    id: 1, lead_id: 7, cycle_no: 1, reference: "EDW-1", status: "accepted", destination_type: "partner", partner_id: 3, partner_name: "Acme Edtech", mode: "commission_first",
    reason: null, cause: null, b2c_lane: null, outcome: null, outcome_at: null, created_at: hours(-48), updated_at: hours(-48), attempt_no: 1, is_test: false, segment: "mba|PG|Online",
    segment_exact: null, interest_rank: 1, programme_id: null, stage: "A", score_inr: 12000, ncpl_inr: null, cpe_net_inr: 12000, p_enroll: null, effort_factor: null, sla_factor: null,
    model_version: null, origin: "auto", override: false, paid: false, paid_platform: null, campaign_id: null, pushed_at: hours(-48), accepted_at: hours(-47), engine_decision_id: 1,
    lost_at: null, lost_grace_until: null, lost_revived_at: null, lost_count: 0, lost_detail: null, recall_reason: null,
    ...p,
  } as AllocationRow;
}

/** A qualified, routable lead with nothing special going on. */
function routing(p: Partial<LeadRouting> = {}): LeadRouting {
  return {
    readiness: { ready: true, missing: [], is_test: false, class: "qualified", paid: null, wait: null },
    interest: { course_key: "mba", specialization: null, level: "PG", mode: "Online", university_id: null, university_text: null, segment: "mba|PG|Online", rank: 1 },
    consent: false, routing_live: true, not_passed: null, flags: [], decisions: [], allocations: [], notifications: [],
    bar: null, other_providers: [], hold: null, outlook: { outlook: "partners", reason: null, lane: null },
    consent_detail: {
      partner_consent: { given: false, at: null, version: null, source: null, refused: false, refused_at: null, last_state: null, stamp_uncovered: false, open_request: null, expired_request: null, last_request: null },
      state: "none", ledger: [], requests: [],
    },
    reenquiries: [], reenquiries_open: 0, interests: [], lost_grace: null, reroute: null, nurture_watch: null, wait: null, golive: [],
    attribution: { paid: false, platform: "none", signal: null, label: null, campaign_id: null, origin: null },
    is_test: false,
    ...p,
  };
}

const sellingHold = (): LeadRouting["hold"] => ({ kind: "selling", open: true, allocation_id: 9, lane: "sales", reason: "manual" });
const bar = (reason: "duplicate" | "lost", providers: NonNullable<LeadRouting["bar"]>["providers"] = []): LeadRouting["bar"] =>
  ({ reason, barred_at: "2026-10-03T05:00:00Z", lead_id: 7, allocation_id: 11, providers, set_by: reason === "lost" ? "grace" : "engine", via: "lead" });
const given = (): LeadRouting["consent_detail"] => ({
  partner_consent: { given: true, at: hours(-3), version: "wa_partner_consent:v1", source: "b2c_crm", refused: false, refused_at: null, last_state: "given", stamp_uncovered: false, open_request: null, expired_request: null,
                     last_request: { id: 5, status: "answered", answer: "yes", answered_at: hours(-3), created_at: hours(-5), expires_at: hours(43) } },
  state: "given", ledger: [], requests: [],
});

describe("routingActionState: Send to partners (PART 6.3, R2)", () => {
  it("hides Send to partners for a barred lead and gives the exact sentence", () => {
    const s = routingActionState(routing({ hold: { kind: "barred", open: true, allocation_id: 9, lane: "sales", reason: "duplicate_cascade" }, bar: bar("duplicate"), consent_detail: given(), consent: true }));
    expect(s.sendToPartners.show).toBe(false);
    expect(s.barred).toBe(true);
    expect(s.barredNote).toBe("This lead is partner-barred for ever: it can only be worked by B2C");
    expect(BARRED_SENTENCE).toBe(s.barredNote);
  });

  it("shows it for a B2C-held lead with consent, disabled with a reason without consent", () => {
    const withConsent = routingActionState(routing({ hold: sellingHold(), consent: true, consent_detail: given() }));
    expect(withConsent.sendToPartners).toEqual({ show: true, disabledWhy: null });
    const without = routingActionState(routing({ hold: sellingHold() }));
    expect(without.sendToPartners.show).toBe(true);
    expect(without.sendToPartners.disabledWhy).toContain("has not consented");
    const uncovered = routing({ hold: sellingHold() });
    uncovered.consent_detail = { ...uncovered.consent_detail, state: "stamp_uncovered" };
    expect(routingActionState(uncovered).sendToPartners.disabledWhy).toBe("The consent stamp does not cover admission partners: ask for consent first");
    expect(consentBlockReason("requested")).toContain("wait for the student's answer");
  });

  it("hides it when B2C does not hold the lead, for a closed hold, and for test leads (sandbox instead)", () => {
    expect(routingActionState(routing()).sendToPartners.show).toBe(false);
    expect(routingActionState(routing({ hold: { ...sellingHold()!, open: false } })).sendToPartners.show).toBe(false);
    const test = routingActionState(routing({ is_test: true, hold: sellingHold(), consent: true, consent_detail: given() }));
    expect(test.sendToPartners.show).toBe(false);
    expect(test.test).toEqual({ sandbox: false, b2cTest: false }); // held = already routed
    const freshTest = routingActionState(routing({ is_test: true }));
    expect(freshTest.test).toEqual({ sandbox: true, b2cTest: true });
    expect(routingActionState(routing()).test).toEqual({ sandbox: false, b2cTest: false });
  });

  it("offers Pass to CRM only for an open not_passed row", () => {
    const np = { lead_id: 7, reason: "junk", lead_status: "JUNK", requested_course: null, lead_source: null, decided_at: hours(-1), passed_at: null, pass_note: null, times: 1 };
    expect(routingActionState(routing({ not_passed: np })).passToCrm).toBe(true);
    expect(routingActionState(routing({ not_passed: { ...np, passed_at: hours(-0.5) } })).passToCrm).toBe(false);
  });
});

describe("routingActionState: Re-route follows reroute_check (PART 6.2, D20)", () => {
  const accepted = allocation({ id: 21, status: "accepted", partner_name: "Acme Edtech" });

  it("is disabled with the 'lost, in grace' why", () => {
    const why = "lost, in grace: it returns to the partner on activity, or moves to B2C nurture with a partner bar after the grace";
    const s = routingActionState(routing({
      allocations: [accepted],
      reroute: { allowed: false, why, lost_in_grace: true, first_attempt_at: hours(-20), breaches: [], allocation_id: 21, status: "accepted" },
      lost_grace: { allocation_id: 21, reference: "EDW-21", partner_id: 3, lost_at: hours(-30), grace_until: hours(138), lost_reason: "not interested", revived: false, revived_at: null, in_grace: true, lost_count: 1 },
    }));
    expect(s.reroute).toEqual({ show: true, enabled: false, why, allocationId: 21, partner: "Acme Edtech" });
    expect(s.lost.show).toBe(false); // already in the grace
  });

  it("is disabled after a contact without a breach, enabled after a breach, enabled before the first attempt", () => {
    const contacted = routingActionState(routing({
      allocations: [accepted],
      reroute: { allowed: false, why: "the partner has already contacted the student and breached no SLA: a re-route needs a breach first", lost_in_grace: false, first_attempt_at: hours(-20), breaches: [], allocation_id: 21, status: "accepted" },
    }));
    expect(contacted.reroute.enabled).toBe(false);
    expect(contacted.reroute.why).toContain("needs a breach first");

    const breached = routingActionState(routing({
      allocations: [accepted],
      reroute: { allowed: true, why: null, lost_in_grace: false, first_attempt_at: hours(-20), breaches: [{ sla: "first_attempt", status: "breached", due_at: hours(-40), met_at: null }], allocation_id: 21, status: "accepted" },
    }));
    expect(breached.reroute).toEqual({ show: true, enabled: true, why: "Allowed: an SLA was breached", allocationId: 21, partner: "Acme Edtech" });

    const fresh = routingActionState(routing({ allocations: [accepted], reroute: { allowed: true, why: null, lost_in_grace: false, first_attempt_at: null, breaches: [], allocation_id: 21, status: "accepted" } }));
    expect(fresh.reroute.enabled).toBe(true);
    expect(fresh.reroute.why).toBe("Allowed: the partner has not contacted the student yet");
    expect(fresh.lost).toEqual({ show: true, allocationId: 21, partner: "Acme Edtech" });
  });

  it("is hidden without an open partner allocation; lost is hidden while the push is queued", () => {
    expect(routingActionState(routing()).reroute.show).toBe(false);
    const queued = routingActionState(routing({ allocations: [allocation({ id: 22, status: "queued" })], reroute: { allowed: true, why: null, lost_in_grace: false, first_attempt_at: null, breaches: [], allocation_id: 22, status: "queued" } }));
    expect(queued.lost.show).toBe(false);
    expect(queued.reroute.show).toBe(true);
  });
});

describe("consentPanel (PART 7, D7, D9)", () => {
  const base = routing();
  const pc = base.consent_detail.partner_consent;

  it("requested: countdown from expires_at, Witty channel, no ask, refusal allowed, YES needs the setting", () => {
    const r = routing({ consent_detail: { ...base.consent_detail, state: "requested", partner_consent: { ...pc, open_request: { id: 5, status: "requested", channel: "witty", context: "decision", created_at: hours(-1), expires_at: hours(47), programme: "MBA" } } } });
    const p = consentPanel(r, { now: NOW });
    expect(p.label).toBe("Consent requested, waiting for the answer");
    expect(p.request).toMatchObject({ id: 5, open: true, channelLabel: "Witty", countdown: "1 d 23 h left", programme: "MBA" });
    expect(p.canAsk).toBe(false);
    expect(p.askWhy).toBe("A request is already open");
    expect(p.canRecordNo).toBe(true);
    expect(p.canRecordYes).toBe(false);
    expect(p.yesWhy).toContain("consent_admin_yes");
    expect(consentPanel(r, { now: NOW, adminYes: true }).canRecordYes).toBe(true);
  });

  it("queued: 'queued' instead of a countdown, B2C number", () => {
    const r = routing({ consent_detail: { ...base.consent_detail, state: "queued", partner_consent: { ...pc, open_request: { id: 6, status: "queued", channel: "b2c_crm", context: "decision", created_at: hours(-1), expires_at: null, programme: null } } } });
    const p = consentPanel(r, { now: NOW });
    expect(p.request).toMatchObject({ open: true, channelLabel: "B2C number", countdown: "queued", statusLabel: "Queued" });
    expect(p.tone).toBe("info");
  });

  it("expired: the expired request is shown closed, asking again is allowed, a NO can still be recorded", () => {
    const r = routing({ consent_detail: { ...base.consent_detail, state: "expired", partner_consent: { ...pc, expired_request: { id: 4, channel: "b2c_crm", context: "decision", created_at: hours(-50), expires_at: hours(-2), closed_at: hours(-2), programme: "MBA" } } } });
    const p = consentPanel(r, { now: NOW, adminYes: true });
    expect(p.request).toMatchObject({ id: 4, open: false, countdown: "expired", statusLabel: "Expired" });
    expect(p.canAsk).toBe(true);
    expect(p.canRecordNo).toBe(true);
    expect(p.canRecordYes).toBe(true);
  });

  it("refused: no second refusal; asking again is allowed", () => {
    const r = routing({ consent_detail: { ...base.consent_detail, state: "refused", partner_consent: { ...pc, refused: true, refused_at: hours(-3), last_state: "refused", last_request: { id: 3, status: "answered", answer: "no", answered_at: hours(-3), created_at: hours(-4), expires_at: hours(44) } } } });
    const p = consentPanel(r, { now: NOW, adminYes: true });
    expect(p.label).toBe("Student said NO to sharing");
    expect(p.tone).toBe("danger");
    expect(p.canRecordNo).toBe(false);
    expect(p.noWhy).toBe("A refusal is already recorded");
    expect(p.canAsk).toBe(true);
    expect(p.canRecordYes).toBe(true);
  });

  it("stamp_uncovered: the label names the admission partners and asking is allowed", () => {
    const r = routing({ consent_detail: { ...base.consent_detail, state: "stamp_uncovered", partner_consent: { ...pc, stamp_uncovered: true } } });
    const p = consentPanel(r, { now: NOW });
    expect(p.label).toBe("Consent stamp does not cover admission partners");
    expect(p.stampUncovered).toBe(true);
    expect(p.tone).toBe("warning");
    expect(p.canAsk).toBe(true);
    expect(p.noWhy).toContain("no consent request to answer");
  });

  it("given: no ask, no YES, a withdrawal (NO) is still possible; test and barred leads are not asked", () => {
    const p = consentPanel(routing({ consent: true, consent_detail: given() }), { now: NOW, adminYes: true });
    expect(p.given).toMatchObject({ version: "wa_partner_consent:v1", source: "b2c_crm" });
    expect(p.canAsk).toBe(false);
    expect(p.canRecordYes).toBe(false);
    expect(p.canRecordNo).toBe(true);
    expect(consentPanel(routing({ is_test: true }), { now: NOW }).askWhy).toBe("Test leads are not asked");
    expect(consentPanel(routing({ bar: bar("duplicate") }), { now: NOW }).canAsk).toBe(false);
  });
});

describe("drawerBadges (PART 5.4, D1, D38)", () => {
  it("names the bar with its reason and date, or the partner that lost it", () => {
    const dup = drawerBadges(routing({ bar: bar("duplicate", [{ partner_id: 3, partner_name: "Acme Edtech" }]) }), {}, NOW);
    expect(dup[0]).toMatchObject({ key: "bar", tone: "danger", text: "Partner-barred (duplicate, 3 Oct)" });
    expect(barText(bar("lost", [{ partner_id: 3, partner_name: "Acme Edtech" }])!)).toBe("Partner-barred (lost by Acme Edtech, 3 Oct)");
  });

  it("writes the providers sentence with and without a date", () => {
    expect(providersSentence([
      { partner_id: 3, partner_name: "Acme Edtech", first_had_at: "2026-09-12T04:00:00Z" },
      { partner_id: 4, partner_name: "Beta Learning", first_had_at: null },
    ])).toBe("Already with other providers: Acme Edtech since 12 Sep, Beta Learning date not given");
    expect(providersSentence([])).toBeNull();
    const badges = drawerBadges(routing({ other_providers: [{ partner_id: 4, partner_name: "Beta Learning", first_had_at: null, existing_record_id: "L-1", claimed_at: hours(-2) }] }), {}, NOW);
    expect(badges.find((b) => b.key === "providers")?.text).toBe("Already with other providers: Beta Learning date not given");
  });

  it("shows Paid from the attribution label, lost in grace with the countdown, and the consent state", () => {
    const r = routing({
      attribution: { paid: true, platform: "meta", signal: "meta_lead_form", label: "Meta Lead Ads", campaign_id: "c1", origin: null },
      lost_grace: { allocation_id: 21, reference: "EDW-21", partner_id: 3, lost_at: hours(-30), grace_until: hours(138), lost_reason: "not interested", revived: false, revived_at: null, in_grace: true, lost_count: 1 },
    });
    r.consent_detail = { ...r.consent_detail, state: "stamp_uncovered" };
    const keys = drawerBadges(r, {}, NOW).map((b) => [b.key, b.text]);
    expect(keys).toEqual([
      ["paid", "Paid: Meta Lead Ads"],
      ["lost_grace", "Lost, in grace · 5 d 18 h left"],
      ["consent", "Consent stamp does not cover admission partners"],
    ]);
  });

  it("falls back to the column stamp when routing did not load", () => {
    expect(drawerBadges(null, { consent_partner_share_at: "2026-10-01T00:00:00Z" })).toHaveLength(1);
    expect(drawerBadges(null, {})).toEqual([]);
  });
});

describe("grace countdown and the lost dialog (PART 6.1, D34)", () => {
  it("counts down the 7 days, says 'ended' after, and nothing after a revival", () => {
    expect(remainingText(hours(138), NOW)).toBe("5 d 18 h left");
    expect(remainingText(hours(3.5), NOW)).toBe("3 h 30 min left");
    expect(remainingText(hours(0.2), NOW)).toBe("12 min left");
    expect(remainingText(hours(-1), NOW)).toBe("ended");
    expect(remainingText(null, NOW)).toBeNull();
    const r = routing({
      allocations: [allocation({ id: 21, partner_name: "Acme Edtech", lost_at: hours(-30), lost_grace_until: hours(138) })],
      lost_grace: { allocation_id: 21, reference: "EDW-21", partner_id: 3, lost_at: hours(-30), grace_until: hours(138), lost_reason: "joined elsewhere", revived: false, revived_at: null, in_grace: true, lost_count: 1 },
    });
    expect(graceCountdown(r, NOW)).toMatchObject({ partner: "Acme Edtech", inGrace: true, remaining: "5 d 18 h left", lostReason: "joined elsewhere" });
    const revived = routing({ lost_grace: { ...r.lost_grace!, revived: true, revived_at: hours(-1), in_grace: false } });
    expect(graceCountdown(revived, NOW)).toMatchObject({ inGrace: false, remaining: null, revived: true });
    expect(graceCountdown(routing(), NOW)).toBeNull();
  });

  it("describes the grace, revival and the bar; the success toast says in grace", () => {
    const copy = lostDialogCopy("Acme Edtech");
    expect(copy).toContain("7 days");
    expect(copy).toContain("back with them");
    expect(copy).toContain("partner-barred for ever");
    expect(LOST_SUCCESS_TOAST).toBe("Recorded: lost, in grace for 7 days");
    expect(allocationStatusText({ status: "accepted", outcome: null, lost_at: hours(-1), lost_revived_at: null })).toBe("Lost, in grace");
    expect(allocationStatusText({ status: "closed", outcome: "lost", lost_at: hours(-200), lost_revived_at: null })).toBe("Lost at partner");
    expect(allocationStatusText({ status: "accepted", outcome: null, lost_at: null, lost_revived_at: null })).toBe("Accepted");
  });
});

describe("nurture, readiness, holds and re-enquiries", () => {
  it("summarises the qualification nurture: missing details in words and the last check", () => {
    const r = routing({
      hold: { kind: "qualification_nurture", open: true, allocation_id: 9, lane: "nurture", reason: "not_qualified" },
      nurture_watch: { lead_id: 7, allocation_id: 9, fingerprint: "x", class: "unqualified", missing: ["no_email", "witty_unconfirmed"], qualified_at: null, recheck_at: hours(2), consent_request_id: null, reengaged_at: null, checked_at: hours(-1), times: 3 },
    });
    const n = nurtureSummary(r)!;
    expect(n.active).toBe(true);
    expect(n.reason).toBe("Not qualified");
    expect(n.missing).toEqual(["email", "Witty has not confirmed the details (no HOT / WARM / COLD)"]);
    expect(n.lastCheck).toBe(hours(-1));
    expect(n.times).toBe(3);
    expect(nurtureSummary(routing())).toBeNull();
  });

  it("reads the readiness wait", () => {
    expect(waitText(routing({ readiness: { ready: false, missing: ["unqualified: waiting for 18 h without a student message"], is_test: false, wait: { kind: "inactivity", hours: 18, until: "2026-10-08T09:30:00Z" } } })))
      .toBe(`Waiting for 18 h without a student message · decides ${formatIst("2026-10-08T09:30:00Z")}`);
    expect(waitText(routing({ readiness: { ready: false, missing: ["awaiting partner-sharing consent"], is_test: false, wait: { kind: "consent", until: null } } }))).toBe("Awaiting partner-sharing consent");
    expect(waitText(routing())).toBeNull();
  });

  it("labels holds, the outlook and the re-enquiry holders", () => {
    expect(holdText(routing({ hold: sellingHold() }))).toBe("With B2C sales · Sent to B2C by the Admin");
    expect(holdText(routing())).toBeNull();
    expect(outlookText(routing({ outlook: { outlook: "b2c_nurture", reason: "not_qualified", lane: "nurture" } }))).toBe("B2C nurture · Not qualified");
    expect(reenquiriesTitle([{ holder: "partner", partner_name: "Acme Edtech" }])).toBe("New enquiries while with Acme Edtech");
    expect(reenquiriesTitle([{ holder: "barred", partner_name: null }])).toBe("New enquiries while partner-barred, with B2C");
    expect(reenquiriesTitle([])).toBe("New enquiries");
  });

  it("turns the route_to_partners refusals into sentences without their prefix", () => {
    expect(friendlyRouteError("partner_barred: partner-barred (duplicate) since 3 Oct: this lead can never be sent to partners")).toBe("Partner-barred (duplicate) since 3 Oct: this lead can never be sent to partners.");
    expect(friendlyRouteError("no_consent: the student has not consented to sharing with partners")).toBe("The student has not consented to sharing with partners.");
    expect(friendlyRouteError("test leads use the sandbox")).toBe("Test leads use the sandbox.");
  });
});

function formatIst(iso: string) {
  return new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso));
}
