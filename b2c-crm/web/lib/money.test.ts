import { describe, expect, it } from "vitest";
import { calcText, parseTiers, rateText } from "./money";

const inr = (n: number) => `₹${n.toLocaleString("en-IN")}`;

describe("money words", () => {
  it("describes rates and what was computed", () => {
    expect(rateText({ rate_type: "percent", value: 25, fee_base: "first_year" }, inr)).toBe("25% of the first-year fee");
    expect(rateText({ rate_type: "fixed", value: 5000 }, inr)).toBe("fixed ₹5,000");
    expect(calcText({ pct: 25, base: 90000, amount: 22500 }, inr)).toBe("25% of ₹90,000 = ₹22,500");
    expect(calcText(null, inr)).toBe("–");
  });
  it("parses tiers that cover every conversion with no gap", () => {
    expect(parseTiers("0-7:22.42, 7-9:20.42, 9-:18.42")).toEqual([{ from: 0, to: 7, value: 22.42 }, { from: 7, to: 9, value: 20.42 }, { from: 9, to: null, value: 18.42 }]);
    expect(parseTiers("0-7:22, 8-:18")).toBeNull();
    expect(parseTiers("0-7:22")).toBeNull();
    expect(parseTiers("nonsense")).toBeNull();
  });
});
