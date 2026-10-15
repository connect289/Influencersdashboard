import { describe, expect, it } from "vitest";
import { attachmentLines, daysUntouched, groupByDay, inWords, isMoveBackRefusal, nextIndex, renderMerge, suggestNext, talkMinutes } from "./workspace";
import { commissionText, duration, programmeQuery } from "./programmes";

describe("merge fields", () => {
  it("fills every field it has and leaves the rest visible", () => {
    const v = { first_name: "Asha", programme: "Online MBA", fee: "Rs 80,000 a year", counsellor_name: "Priya Shah", counsellor_first_name: "Priya", followup_time: null };
    expect(renderMerge("Hi {{first_name}}, {{ programme }} costs {{fee}}. {{emi}} — {{counsellor_first_name}}", v))
      .toBe("Hi Asha, Online MBA costs Rs 80,000 a year. {{emi}} — Priya");
    expect(renderMerge("{{counsellor}} at {{followup_time}}", v)).toBe("Priya Shah at {{followup_time}}");
  });
  it("adds https brochure links from a template's attachments", () => {
    expect(attachmentLines([{ name: "Amity MBA brochure", url: "https://x.in/b.pdf" }, { name: "bad", url: "http://y" }])).toBe("\n\nAmity MBA brochure: https://x.in/b.pdf");
    expect(attachmentLines(null)).toBe("");
  });
});

describe("calls", () => {
  it("estimates talk time from the time away", () => {
    const t = Date.parse("2026-10-15T10:00:00Z");
    expect(talkMinutes(t, t + 7.4 * 60000)).toBe(7);
    expect(talkMinutes(t, t + 10000)).toBe(1);
    expect(talkMinutes(t, t - 5000)).toBe(1);
    expect(talkMinutes(t, t + 20 * 3600e3)).toBe(600);
  });
  it("suggests the next step like the database", () => {
    expect(suggestNext("no_answer", 0)).toMatchObject({ kind: "call", in_minutes: 180 });
    expect(suggestNext("busy", 2)).toMatchObject({ kind: "whatsapp", in_minutes: 30 });
    expect(suggestNext("connected", 5)).toMatchObject({ kind: "call", in_minutes: 1440 });
    expect(suggestNext("wrong_number", 0).kind).toBe("whatsapp");
    expect(inWords(180)).toBe("in 3 h");
    expect(inWords(1440)).toBe("tomorrow");
  });
});

describe("follow-ups and neglect", () => {
  const now = new Date("2026-10-15T06:00:00Z"); // 11:30 IST
  it("counts days untouched from the last activity, else the assignment", () => {
    expect(daysUntouched({ days_untouched: 3 }, now)).toBe(3);
    expect(daysUntouched({ last_activity_at: "2026-10-13T05:00:00Z" }, now)).toBe(2);
    expect(daysUntouched({ last_activity_at: null, assigned_at: "2026-10-14T07:00:00Z" }, now)).toBe(0);
    expect(daysUntouched({}, now)).toBeNull();
  });
  it("groups upcoming follow-ups by IST day and finds the next one", () => {
    const rows = [{ at: "2026-10-16T04:00:00Z" }, { at: "2026-10-16T12:00:00Z" }, { at: "2026-10-16T19:00:00Z" }, { at: "2026-10-18T05:00:00Z" }];
    const g = groupByDay(rows, (r) => r.at, now);
    expect(g.map((x) => [x.label, x.rows.length])).toEqual([["Tomorrow", 2], ["Sat 17 Oct", 1], ["Sun 18 Oct", 1]]);
    expect(nextIndex([{ at: "2026-10-15T05:00:00Z" }, { at: "2026-10-15T08:00:00Z" }], (r) => r.at, now)).toBe(1);
  });
  it("recognises the database's refusal of a move back", () => {
    expect(isMoveBackRefusal("moving back from Applicant to Counselled needs the Admin")).toBe(true);
    expect(isMoveBackRefusal("choose a sub-stage")).toBe(false);
  });
});

describe("programme page", () => {
  it("turns the address into the search, dropping fee bounds at the catalogue's edge", () => {
    const q = programmeQuery({ q: " mba ", fee_min: "50000", fee_max: "400000", emi: "1", eligible: "1", lead: "42", sort: "fee", page: "2" }, { min: 50000, max: 400000 });
    expect(q).toMatchObject({ q: "mba", fee_min: null, fee_max: null, emi: true, eligible: true, lead: 42, sort: "fee", offset: 48 });
    expect(programmeQuery({ fee_max: "200000", sort: "nonsense", eligible: "1" }, { min: 50000, max: 400000 })).toMatchObject({ fee_max: 200000, sort: "name", eligible: null });
  });
  it("words durations and commissions", () => {
    expect(duration(24)).toBe("2 years");
    expect(duration(18)).toBe("18 months");
    expect(commissionText(12)).toBe("12%");
    expect(commissionText({ type: "fixed", value: 15000 })).toBe("₹15,000");
  });
});
