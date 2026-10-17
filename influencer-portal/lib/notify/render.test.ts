import { describe, expect, it } from "vitest";
import { renderHtml, renderText, templateVars, unknownVars, whatsappParams } from "./render";

describe("templates", () => {
  it("finds variables once, case-insensitively", () => {
    expect(templateVars("Hi {{ name }}, {{NAME}} — {{amount}}")).toEqual(["name", "amount"]);
  });

  it("refuses variables the event does not provide", () => {
    expect(unknownVars("payout.paid", "Paid {{amount}} (UTR {{utr}})", "{{name}}")).toEqual([]);
    expect(unknownVars("payout.paid", "{{phone}} {{amount}}")).toEqual(["phone"]);
  });

  it("renders text and reports missing values", () => {
    expect(renderText("Hi {{name}}, you earned {{amount}}.", { name: "Riya" })).toEqual({
      text: "Hi Riya, you earned .",
      missing: ["amount"],
    });
  });

  it("escapes values and the template in HTML and builds paragraphs", () => {
    const r = renderHtml("Hi {{name}},\n\nYour <b>payout</b> of {{amount}}\nis on its way.", {
      name: "<script>",
      amount: "₹1,000",
    });
    expect(r.text).toBe("<p>Hi &lt;script&gt;,</p><p>Your &lt;b&gt;payout&lt;/b&gt; of ₹1,000<br>is on its way.</p>");
  });

  it("builds WhatsApp parameters one line each, never empty", () => {
    expect(whatsappParams("{{name}}\n\n{{amount}}\n{{utr}}", { name: "Riya", amount: "₹54,000" })).toEqual([
      "Riya",
      "₹54,000",
      "-",
    ]);
  });
});
