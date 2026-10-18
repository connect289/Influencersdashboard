import { describe, expect, it } from "vitest";
import { absolute, composeEmail, composeWhatsApp, notificationVars, type NotificationFacts } from "./compose";

const SITE = "https://creators.eduwit.in";
const paid: NotificationFacts = {
  event: "payout.paid",
  title: "Payout sent",
  body: "₹4,500.00 is on its way.",
  link: "/creator/earnings",
  data: { amount: "₹4,500.00", utr: "UTR123", phone: "9999999999", payout_id: "x" },
};

describe("notification composition", () => {
  it("offers only the event's variables from the data", () => {
    const v = notificationVars(paid, "Riya", SITE);
    expect(v).toMatchObject({ name: "Riya", amount: "₹4,500.00", utr: "UTR123", link: `${SITE}/creator/earnings` });
    expect(v).not.toHaveProperty("phone");
    expect(v).not.toHaveProperty("payout_id");
  });

  it("only makes in-app paths absolute", () => {
    expect(absolute("/creator", SITE + "/")).toBe(`${SITE}/creator`);
    expect(absolute("https://evil.example", SITE)).toBeNull();
    expect(absolute("//evil.example", SITE)).toBeNull();
    expect(absolute(null, SITE)).toBeNull();
  });

  it("uses the built-in copy without a template", () => {
    const m = composeEmail(paid, null, "Riya", SITE);
    expect(m.subject).toBe("Payout sent");
    expect(m.text).toBe(`₹4,500.00 is on its way.\n\n${SITE}/creator/earnings`);
    expect(m.html).toContain(`href="${SITE}/creator/earnings"`);
  });

  it("renders a staff template, escaping values in HTML", () => {
    const m = composeEmail(
      { ...paid, data: { ...paid.data, utr: "<b>U1</b>" } },
      { subject: "Paid: {{ amount }}", body: "Hi {{name}},\n\nUTR {{utr}}.", wa_template_name: null },
      "Riya",
      SITE,
    );
    expect(m.subject).toBe("Paid: ₹4,500.00");
    expect(m.text).toBe(`Hi Riya,\n\nUTR <b>U1</b>.\n\n${SITE}/creator/earnings`);
    expect(m.html).toContain("UTR &lt;b&gt;U1&lt;/b&gt;.");
    expect(m.html).not.toContain("<b>U1</b>");
  });

  it("sends WhatsApp only with an approved template and a usable number", () => {
    const tpl = { subject: null, body: "{{name}}\n{{amount}}\n{{utr}}", wa_template_name: "payout_paid_v1" };
    expect(composeWhatsApp(paid, tpl, "Riya", "+919812345678", SITE)).toEqual({
      to: "919812345678",
      template: "payout_paid_v1",
      language: "en",
      params: ["Riya", "₹4,500.00", "UTR123"],
    });
    expect(composeWhatsApp(paid, { ...tpl, wa_template_name: null }, "Riya", "+919812345678", SITE)).toBeNull();
    expect(composeWhatsApp(paid, null, "Riya", "+919812345678", SITE)).toBeNull();
    expect(composeWhatsApp(paid, tpl, "Riya", "12", SITE)).toBeNull();
    expect(composeWhatsApp(paid, tpl, "Riya", null, SITE)).toBeNull();
  });
});
