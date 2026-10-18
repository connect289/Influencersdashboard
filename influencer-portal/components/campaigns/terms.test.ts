import { describe, expect, it } from "vitest";
import { offerTerms } from "@/lib/campaigns/schemas";
import { draftFromTerms, termsFromDraft } from "./terms";

describe("terms draft", () => {
  it("round-trips terms through the form draft with integer paise", () => {
    const terms = {
      deal_type: "hybrid" as const,
      fixed_fee_paise: 1250050,
      includes_commission: true,
      deliverables: [{ platform: "instagram" as const, format: "reel" as const, count: 2 }],
    };
    const back = termsFromDraft(draftFromTerms(terms));
    expect(back.fixed_fee_paise).toBe(1250050);
    expect(back.includes_commission).toBe(true);
    expect(offerTerms.safeParse(back).success).toBe(true);
  });
  it("drops the fee for commission-only and barter deals", () => {
    const d = { ...draftFromTerms(undefined), deal_type: "commission" as const, feeRupees: "5000" };
    expect(termsFromDraft(d).fixed_fee_paise).toBeUndefined();
    expect(termsFromDraft(d).includes_commission).toBe(true);
    expect(termsFromDraft({ ...d, deal_type: "barter" }).fixed_fee_paise).toBeUndefined();
  });
  it("prefills deliverables from the campaign when the offer has none", () => {
    expect(draftFromTerms(undefined, [{ platform: "youtube", format: "short", count: 3 }]).deliverables).toHaveLength(
      1,
    );
  });
});
