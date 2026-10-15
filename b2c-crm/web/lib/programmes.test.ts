import { describe, expect, it } from "vitest";
import { accreditationLabel, groupByUniversity, headlineFee, isFiltered, levelLabel, moreOffsets, programmeQuery, universityCommission, type Programme } from "./programmes";

const row = (o: Partial<Programme>): Programme => ({
  id: 1, name: "Online MBA", course: "MBA", specialization: null, level: "PG", mode: "Online", university: "Jain Online", university_id: 2, university_short: "Jain",
  duration_months: 24, fee_yearly: 80000, fee_semester: 40000, fee_total: 160000, fee_exam: null, fee_registration: null, emi_monthly: null, scholarship: null,
  intakes: null, deadline: null, accreditation: null, recognitions: null, min_qualification: null, min_pct: null, eligibility: null, brochure_url: null,
  enrollments: 0, eligible: null, within_budget: null, ...o,
});

describe("programmes", () => {
  it("turns the address into the search, with the course family and a fee bound only inside the catalogue's range", () => {
    const q = programmeQuery({ q: " mba ", course: "MBA", level: "PG", fee_min: "100000", fee_max: "500000", sort: "fee", lead: "42", eligible: "1" }, { min: 100000, max: 300000 }, 300);
    expect(q).toMatchObject({ q: "mba", course: "MBA", level: "PG", fee_min: null, fee_max: null, sort: "fee", lead: 42, eligible: true, limit: 300, offset: 300 });
    expect(programmeQuery({ sort: "moon" }).sort).toBe("name");
    expect(isFiltered({ sort: "fee" })).toBe(false);
    expect(isFiltered({ course: "BBA" })).toBe(true);
  });

  it("spells out the level codes", () => {
    expect(levelLabel("UG")).toBe("Undergraduate");
    expect(levelLabel("pg")).toBe("Postgraduate");
    expect(levelLabel("DIPLOMA")).toBe("Diploma");
    expect(levelLabel("Executive")).toBe("Executive");
    expect(levelLabel(null)).toBeNull();
  });

  it("picks one short approval out of the university's text", () => {
    const text = "[ACCREDITATIONS] Distance/Online Education Approvals: UGC-DEB Approved NAAC Rating: NAAC A Grade Other: AICTE Approved";
    expect(accreditationLabel(text)).toBe("UGC-DEB approved");
    expect(accreditationLabel("NAAC A++ accredited")).toBe("NAAC A++");
    expect(accreditationLabel(null, ["UGC entitled"])).toBe("UGC recognised");
    expect(accreditationLabel(null, ["Some board"])).toBe("Some board");
    expect(accreditationLabel("nothing here")).toBeNull();
  });

  it("shows the total fee with the per-semester figure under it", () => {
    expect(headlineFee({ fee_total: 160000, fee_yearly: 80000, fee_semester: 40000 })).toEqual({ label: "Total fee", value: 160000, per: "per semester:40000" });
    expect(headlineFee({ fee_total: null, fee_yearly: 80000, fee_semester: null })).toEqual({ label: "Fee per year", value: 80000, per: null });
    expect(headlineFee({ fee_total: 160000, fee_yearly: 80000, fee_semester: null })).toEqual({ label: "Total fee", value: 160000, per: "per year:80000" });
  });

  it("groups by university A to Z and keeps each university's order", () => {
    const g = groupByUniversity([row({ id: 1, university: "Jain Online" }), row({ id: 2, university: "Amity University Online" }), row({ id: 3, university: "Jain Online" })]);
    expect(g.map((x) => x.university)).toEqual(["Amity University Online", "Jain Online"]);
    expect(g[1]!.rows.map((r) => r.id)).toEqual([1, 3]);
  });

  it("sums up a university's commission for the header", () => {
    const pct = { rate_type: "percent", value: 20, fee_base: "first_year", amount: 16000 };
    expect(universityCommission([row({ eduwit_commission: pct }), row({ id: 2, eduwit_commission: pct })])).toEqual({ kind: "rate", text: "20% of the first-year fee" });
    expect(universityCommission([row({ eduwit_commission: pct }), row({ id: 2, eduwit_commission: { ...pct, value: 15 } })])).toEqual({ kind: "varies" });
    expect(universityCommission([row({ eduwit_commission: null }), row({ id: 2 })])).toEqual({ kind: "none" });
  });

  it("reads the rest of a big catalogue in a few calls", () => {
    expect(moreOffsets(200)).toEqual([]);
    expect(moreOffsets(715)).toEqual([300, 600]);
    expect(moreOffsets(5000)).toEqual([300, 600, 900]);
  });
});
