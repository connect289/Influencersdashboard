import { describe, expect, it } from "vitest";
import { collectNumbers, extractNumbers, matches, validateNumbers } from "./validate";

const texts = (s: string) => extractNumbers(s).map((x) => x.text);

describe("number validator: dates, intervals and Indian units (C14)", () => {
  const tools = [{ ncpl_now: 812, ncpl_new: 862, change: 0.061, ci: [-12, 111], mba_rate: 0.041, upgrad_leads: 52, commission: 452310 }];

  it.each([
    "Simulated NCPL rises from ₹812 to ₹862 (+6.1%), but the 95% interval runs from −₹12 to ₹111.",
    "In September 2026, MBA leads enrolled at 4.1%.",
    "Raise the weight until 21 October.",
    "This month (1 to 7 October 2026), Upgrad received 52 leads",
    "Commission realised this month is ₹4.5 lakh.",
  ])("accepts %s", (text) => {
    expect(validateNumbers(text, tools)).toMatchObject({ ok: true, unverified: [] });
  });

  it("skips dates written in words, but not the counts next to them", () => {
    expect(texts("Raise the weight until 21 October.")).toEqual([]);
    expect(texts("This month (1 to 7 October 2026), Upgrad received 52 leads")).toEqual(["52"]);
    expect(texts("Oct 1–7, 2026: 52 leads")).toEqual(["52"]);
    expect(texts("On 3rd Sept, 52 leads; in May 2026, 61 leads; by 5 may, 7 leads")).toEqual(["52", "61", "7"]);
  });

  it("skips the 95% of a confidence interval, not other percentages", () => {
    expect(texts("the 95% interval runs from 2 to 9")).toEqual(["2", "9"]);
    expect(texts("95% CI: 2 to 9; 95% confidence")).toEqual(["2", "9"]);
    expect(texts("95% of leads")).toEqual(["95%"]);
  });

  it("does not take words that start like a month for one", () => {
    expect(texts("12 decisions declined in marketing; separate from 95% of leads")).toEqual(["12", "95%"]);
    expect(texts("may 5 leads")).toEqual(["5"]);
  });

  it("reads lakh and crore as Indian units", () => {
    expect(extractNumbers("₹4.5 lakh")[0]).toMatchObject({ value: 4.5, decimals: 1, scale: 1e5 });
    expect(extractNumbers("₹1.2 crore")[0]).toMatchObject({ value: 1.2, scale: 1e7 });
    expect(extractNumbers("₹2.3L and 4 Cr")).toMatchObject([{ value: 2.3, scale: 1e5 }, { value: 4, scale: 1e7 }]);
    expect(extractNumbers("12 leads")[0]).toMatchObject({ value: 12, scale: 1 });
    expect(validateNumbers("Commission realised this month is ₹4.5 lakh.", [{ commission: 300000 }])).toMatchObject({ ok: false, unverified: ["₹4.5"] });
    expect(matches(extractNumbers("₹1.2 crore")[0]!, 12_000_000)).toBe(true);
    expect(matches(extractNumbers("₹1.2 crore")[0]!, 1.2)).toBe(false);
    expect(validateNumbers("Revenue is ₹1.2 crore.", [{ revenue: 12_000_000 }]).ok).toBe(true);
    // a tool output written in lakh counts at its full value
    expect(collectNumbers({ note: "commission ₹4.5 lakh" })).toEqual([450000]);
  });
});
