import { describe, expect, it } from "vitest";
import { landingUrl, renderMessage, safeHttpsUrl, shortLink, slugify, utmFor, whatsappUrl, withUtm } from "./links";

const T = "Hi Eduwit! I saw {creator_name}'s post about {programme}. My access code is {access_code} (ref {code})";

describe("links", () => {
  it("renders the WhatsApp message with an access code", () => {
    expect(
      renderMessage(T, {
        creator_name: "Riya",
        programme: "the online MBA",
        code: "RIYA-IG-7K",
        access_code: "K7QM2X",
      }),
    ).toBe("Hi Eduwit! I saw Riya's post about the online MBA. My access code is K7QM2X (ref RIYA-IG-7K)");
  });

  it("drops the access-code sentence when Witty gave none, keeping the creator code", () => {
    expect(renderMessage(T, { creator_name: "Riya", programme: "MBA", code: "RIYA-IG-7K", access_code: null })).toBe(
      "Hi Eduwit! I saw Riya's post about MBA. (ref RIYA-IG-7K)",
    );
    expect(
      renderMessage("Hello {access_code}", { creator_name: "", programme: "", code: "A-B", access_code: null }),
    ).toBe("(ref A-B)");
  });

  it("builds wa.me links with only digits and an encoded message", () => {
    expect(whatsappUrl("+91 96439 77407", "Hi & bye")).toBe("https://wa.me/919643977407?text=Hi%20%26%20bye");
  });

  it("accepts only safe https destinations", () => {
    expect(safeHttpsUrl("https://eduwit.in/mba")?.toString()).toBe("https://eduwit.in/mba");
    for (const bad of [
      "http://eduwit.in",
      "https://user:pw@eduwit.in",
      "https://localhost/x",
      "https://10.0.0.1/x",
      "javascript:alert(1)",
      "nope",
      "https://intranet/x",
      "https://printer.local/x",
      "https://[::1]/",
    ])
      expect(safeHttpsUrl(bad), bad).toBeNull();
  });

  it("sets UTMs, replacing existing ones", () => {
    const utm = utmFor({ source: "influencer", platform: "instagram", campaign: "diwali-mba", code: "RIYA-IG-7K" });
    const u = withUtm(new URL("https://eduwit.in/mba?utm_source=old&x=1"), utm);
    expect(u).toBe(
      "https://eduwit.in/mba?utm_source=influencer&x=1&utm_medium=instagram&utm_campaign=diwali-mba&utm_content=RIYA-IG-7K",
    );
    expect(utmFor({ source: "influencer", platform: null, campaign: null, code: "A-B" })).toEqual({
      utm_source: "influencer",
      utm_medium: "creator",
      utm_campaign: "always-on",
      utm_content: "A-B",
    });
  });

  it("builds landing pages and short links", () => {
    const utm = utmFor({ source: "influencer", platform: "youtube", campaign: "x", code: "RIYA-YT-22" });
    expect(landingUrl("https://eduwit.in/", "riya learns", "RIYA-YT-22", utm)).toBe(
      "https://eduwit.in/c/riya%20learns?code=RIYA-YT-22&utm_source=influencer&utm_medium=youtube&utm_campaign=x&utm_content=RIYA-YT-22",
    );
    expect(landingUrl("http://eduwit.in", "riya", "A-B", utm)).toBeNull();
    expect(shortLink("https://creators.eduwit.in/r/", "RIYA-YT-22")).toBe("https://creators.eduwit.in/r/RIYA-YT-22");
  });

  it("slugifies campaign names", () => {
    expect(slugify("Diwali MBA Push — 2026!")).toBe("diwali-mba-push-2026");
    expect(slugify("!!!")).toBe("campaign");
  });
});
