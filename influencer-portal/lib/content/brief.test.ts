import { describe, expect, it } from "vitest";
import {
  approvedClaims,
  briefContent,
  briefTemplateContent,
  buildBrief,
  deliverableSpecs,
  dueDatesFrom,
  type CatalogueProgramme,
} from "./brief";
import { DEFAULT_TOGGLES } from "./workflow";

const mba: CatalogueProgramme = {
  id: 7,
  program_name: "Online MBA",
  specialization: "Marketing",
  level: "PG",
  mode: "Online",
  university: "Example University",
  recognitions: ["UGC-DEB", "AICTE"],
  accreditation_text: "NAAC A+ accredited.",
  fee_total: 150000,
  fee_yearly: null,
  min_qualification: "Graduation",
  min_pct_general: 50,
  eligibility_text: null,
};

describe("approvedClaims", () => {
  it("states only catalogue facts", () => {
    expect(approvedClaims(mba)).toEqual([
      "Example University Online MBA (Marketing) is an online PG programme.",
      "Example University Online MBA (Marketing): total fee ₹1,50,000.",
      "Example University is recognised by UGC-DEB, AICTE.",
      "Example University: NAAC A+ accredited.",
      "Example University Online MBA (Marketing) eligibility: Graduation with at least 50%.",
    ]);
  });
  it("skips what the catalogue doesn't have", () => {
    const bare = {
      ...mba,
      specialization: null,
      level: null,
      mode: null,
      recognitions: null,
      accreditation_text: null,
      fee_total: null,
      fee_yearly: 60000,
      min_qualification: null,
      eligibility_text: "12th pass",
    };
    expect(approvedClaims(bare)).toEqual([
      "Example University Online MBA: fee ₹60,000 per year.",
      "Example University Online MBA eligibility: 12th pass",
    ]);
    expect(approvedClaims({ ...bare, fee_yearly: 0, eligibility_text: null })).toEqual([]);
  });
});

describe("buildBrief", () => {
  const template = briefTemplateContent.parse({
    audience: "Working professionals, 25–35",
    dos: ["Show your own experience"],
    donts: ["Promise jobs"],
    hashtags: ["#OnlineMBA"],
    faqs: [{ q: "Can I script?", a: "Yes, submit it first." }],
  });
  it("fills from the template, campaign, deal and catalogue", () => {
    const b = buildBrief({
      template,
      campaign: {
        objective_text: "Leads for the Online MBA",
        description: null,
        deliverables: [{ platform: "instagram", format: "reel", count: 2 }],
      },
      agreed: [],
      programmes: [mba],
      banned: ["guaranteed placement"],
      disclosureTerms: ["#ad", "#collab", "paid partnership"],
    });
    expect(b.objective).toBe("Leads for the Online MBA");
    expect(b.programme_ids).toEqual([7]);
    expect(b.approved_claims).toHaveLength(5);
    expect(b.banned_claims).toEqual(["guaranteed placement"]);
    expect(b.disclosures).toEqual(["Disclose the paid partnership at the start, e.g. #ad or #collab."]);
    expect(b.deliverables).toEqual([
      { platform: "instagram", format: "reel", count: 2, duration_s: 60, aspect_ratio: "9:16", notes: "" },
    ]);
    expect(b.dos).toEqual(["Show your own experience"]);
    expect(briefContent.safeParse(b).success).toBe(true);
  });
  it("prefers the deal's agreed deliverables and the template's own disclosure text", () => {
    const b = buildBrief({
      template: { ...template, disclosures: ["Use 'Paid partnership' label"] },
      campaign: null,
      agreed: [{ platform: "youtube", format: "youtube_video", count: 1 }],
      programmes: [],
      banned: [],
      disclosureTerms: ["#ad"],
    });
    expect(b.deliverables.map((d) => [d.format, d.aspect_ratio, d.duration_s])).toEqual([
      ["youtube_video", "16:9", 480],
    ]);
    expect(b.disclosures).toEqual(["Use 'Paid partnership' label"]);
  });
});

describe("briefContent validation", () => {
  it("rejects non-https references and odd asset paths", () => {
    expect(briefContent.safeParse({ references: [{ label: "x", url: "http://a.com" }] }).success).toBe(false);
    expect(briefContent.safeParse({ references: [{ label: "x", url: "https://a.com/v" }] }).success).toBe(true);
    expect(briefContent.safeParse({ assets: [{ label: "logo", path: "../etc/passwd" }] }).success).toBe(false);
  });
});

describe("deliverableSpecs and due dates", () => {
  it("defaults formats without specs", () => {
    expect(deliverableSpecs([{ platform: "linkedin", format: "blog", count: 1 }])[0]).toMatchObject({
      duration_s: null,
      aspect_ratio: null,
    });
  });
  it("places due dates at the end of the IST day", () => {
    const d = dueDatesFrom("2026-11-01T10:00:00Z", { concept: 5, draft: 10, live: 15, metrics: 22 }, DEFAULT_TOGGLES);
    expect(d).toEqual({
      concept: "2026-11-06T18:29:59.000Z",
      draft: "2026-11-11T18:29:59.000Z",
      live: "2026-11-16T18:29:59.000Z",
      metrics: "2026-11-23T18:29:59.000Z",
    });
    expect(
      Object.keys(
        dueDatesFrom(
          "2026-11-01T10:00:00Z",
          { concept: 1, draft: 2, live: 3, metrics: 4 },
          {
            ...DEFAULT_TOGGLES,
            concept: false,
            metrics: false,
          },
        ),
      ),
    ).toEqual(["draft", "live"]);
  });
});
