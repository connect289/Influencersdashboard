// Unsubscribe links (D-198): what a link proves, which emails carry one, and the headers mail providers read.
import { describe, expect, it } from "vitest";
import { EVENT_KEYS, EVENTS, channelLocked } from "./catalogue";
import {
  isOneClickBody,
  listUnsubscribeHeaders,
  signUnsubscribe,
  UNSUBSCRIBE_CATEGORIES,
  UNSUBSCRIBE_TOKEN_MAX,
  unsubscribeCategory,
  unsubscribeLinks,
  verifyUnsubscribe,
} from "./unsubscribe";

const SECRET = "unit-test-unsubscribe-secret-0123456789abcdef";
const OTHER = "another-unit-test-secret-0123456789abcdef-xyz";
const RIYA = "0b9f7a52-3c1e-4d6a-9f2b-7e5d4c3b2a10";
const ARJUN = "5e8d2c41-9a7b-4f3e-8c6d-1b2a3f4e5d6c";
const SITE = "https://creators.eduwit.in";

/** Replaces one character with a different one from the link alphabet. */
function flip(token: string, at: number): string {
  const c = token[at] === "A" ? "B" : "A";
  return token.slice(0, at) + c + token.slice(at + 1);
}

describe("unsubscribe link", () => {
  it("round-trips the account and the category for every category", () => {
    for (const category of UNSUBSCRIBE_CATEGORIES) {
      const token = signUnsubscribe(SECRET, { userId: RIYA, category });
      expect(verifyUnsubscribe(SECRET, token), category).toEqual({ userId: RIYA, category });
      expect(token.length, category).toBeLessThanOrEqual(UNSUBSCRIBE_TOKEN_MAX);
      expect(token, category).toMatch(/^v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/);
    }
  });

  it("is the same every time, so a link in an old email keeps working (no expiry)", () => {
    const a = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    expect(signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" })).toBe(a);
  });

  it("shows no name, address or readable account id", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    expect(token).not.toContain(RIYA);
    expect(token).not.toContain(RIYA.replace(/-/g, ""));
    expect(token).not.toContain("@");
    expect(Buffer.from(token.split(".")[1] ?? "", "base64url").toString("latin1")).not.toContain(RIYA);
  });

  it("refuses a link signed with another secret", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    expect(verifyUnsubscribe(OTHER, token)).toBeNull();
  });

  it("refuses any change to the payload or the signature", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    for (let i = 3; i < token.length; i++) {
      if (token[i] === ".") continue;
      expect(verifyUnsubscribe(SECRET, flip(token, i)), `character ${i.toString()}`).toBeNull();
    }
  });

  it("refuses one link's signature on another account or another category", () => {
    const [v, payload, sig] = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" }).split(".");
    const [, otherUser] = signUnsubscribe(SECRET, { userId: ARJUN, category: "campaigns" }).split(".");
    const [, otherKind] = signUnsubscribe(SECRET, { userId: RIYA, category: "deals" }).split(".");
    expect(verifyUnsubscribe(SECRET, `${v ?? ""}.${payload ?? ""}.${sig ?? ""}`)).not.toBeNull();
    expect(verifyUnsubscribe(SECRET, `${v ?? ""}.${otherUser ?? ""}.${sig ?? ""}`)).toBeNull();
    expect(verifyUnsubscribe(SECRET, `${v ?? ""}.${otherKind ?? ""}.${sig ?? ""}`)).toBeNull();
  });

  it("refuses another version, even with the rest untouched", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    expect(verifyUnsubscribe(SECRET, token.replace(/^v1\./, "v2."))).toBeNull();
    expect(verifyUnsubscribe(SECRET, token.replace(/^v1\./, ""))).toBeNull();
    expect(verifyUnsubscribe(SECRET, token.replace(/^v1\./, "V1."))).toBeNull();
  });

  it("refuses a truncated, padded or over-long link and anything that is not a link", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    for (let cut = 1; cut <= token.length; cut++) expect(verifyUnsubscribe(SECRET, token.slice(0, -cut))).toBeNull();
    for (const bad of [
      "",
      "v1",
      "v1..",
      `${token}A`,
      `${token}=`,
      ` ${token}`,
      `${token}\n`,
      `${token}.${token}`,
      token.replace(/\./g, "/"),
      "a".repeat(5000),
      "../../admin",
      "<script>alert(1)</script>",
    ])
      expect(verifyUnsubscribe(SECRET, bad), JSON.stringify(bad.slice(0, 30))).toBeNull();
    expect(verifyUnsubscribe(SECRET, undefined as unknown as string)).toBeNull();
  });

  it("accepts exactly one spelling of a signature", () => {
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    const last = token.at(-1) ?? "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    // The last character carries two unused bits: three other characters decode to the same bytes.
    const twins = alphabet
      .split("")
      .filter((c) => c !== last && alphabet.indexOf(c) >> 2 === alphabet.indexOf(last) >> 2);
    expect(twins).toHaveLength(3);
    for (const c of twins) expect(verifyUnsubscribe(SECRET, token.slice(0, -1) + c)).toBeNull();
  });

  it("never signs or accepts with a short secret, an unknown category or a malformed id", () => {
    expect(() => signUnsubscribe("short", { userId: RIYA, category: "campaigns" })).toThrow(/too short/);
    expect(() => signUnsubscribe(SECRET, { userId: "not-a-uuid", category: "campaigns" })).toThrow(/invalid/);
    expect(() => signUnsubscribe(SECRET, { userId: RIYA, category: "everything" as "campaigns" })).toThrow(/invalid/);
    expect(verifyUnsubscribe("short", signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" }))).toBeNull();
  });
});

describe("which emails carry a link", () => {
  it("gives every notification a person can turn off its group, and the digest its own category", () => {
    expect(unsubscribeCategory("campaign.invited", false)).toBe("campaigns");
    expect(unsubscribeCategory("contract.comment", false)).toBe("contracts");
    expect(unsubscribeCategory("announcement", false)).toBe("announcements");
    expect(unsubscribeCategory("digest.creator", false)).toBe("digest");
    expect(unsubscribeCategory("digest.staff", false)).toBe("digest");
  });

  it("gives required notices none: exactly the events settings cannot switch off", () => {
    for (const key of EVENT_KEYS) {
      const category = unsubscribeCategory(key, false);
      // Email is a default channel of every required event, so "locked in settings" and "no link" are the same set.
      expect(category === null, key).toBe(EVENTS[key].mandatory);
      expect(category === null, key).toBe(channelLocked(key, "email"));
    }
    for (const key of ["contract.sent", "payout.paid", "kyc.action_needed", "tds.certificate", "privacy.export_ready"])
      expect(unsubscribeCategory(key, false), key).toBeNull();
  });

  it("gives none when the sender marked the notification required, or the event is unknown", () => {
    expect(unsubscribeCategory("campaign.invited", true)).toBeNull();
    expect(unsubscribeCategory("no.such_event", false)).toBeNull();
  });

  it("builds the page link and the one-click link, without a doubled slash", () => {
    const links = unsubscribeLinks(SECRET, `${SITE}/`, RIYA, "campaign.invited", false);
    const token = signUnsubscribe(SECRET, { userId: RIYA, category: "campaigns" });
    expect(links).toEqual({
      pageUrl: `${SITE}/unsubscribe/${token}`,
      oneClickUrl: `${SITE}/unsubscribe/${token}/one-click`,
    });
  });

  it("builds none for a required notice, without a secret, or for a malformed account id", () => {
    expect(unsubscribeLinks(SECRET, SITE, RIYA, "payout.paid", false)).toBeNull();
    expect(unsubscribeLinks(SECRET, SITE, RIYA, "campaign.invited", true)).toBeNull();
    expect(unsubscribeLinks(undefined, SITE, RIYA, "campaign.invited", false)).toBeNull();
    expect(unsubscribeLinks("", SITE, RIYA, "campaign.invited", false)).toBeNull();
    expect(unsubscribeLinks("short", SITE, RIYA, "campaign.invited", false)).toBeNull();
    expect(unsubscribeLinks(SECRET, SITE, "nobody", "campaign.invited", false)).toBeNull();
  });
});

describe("one-click headers (RFC 8058)", () => {
  it("names the HTTPS address and the POST form", () => {
    expect(listUnsubscribeHeaders(`${SITE}/unsubscribe/v1.a.b/one-click`)).toEqual({
      "List-Unsubscribe": `<${SITE}/unsubscribe/v1.a.b/one-click>`,
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    });
  });

  it("sends none without an address, over plain HTTP, or for an address that could break the header", () => {
    expect(listUnsubscribeHeaders(undefined)).toEqual({});
    expect(listUnsubscribeHeaders(null)).toEqual({});
    expect(listUnsubscribeHeaders("http://localhost:3200/unsubscribe/v1.a.b/one-click")).toEqual({});
    expect(listUnsubscribeHeaders(`${SITE}/x>, <mailto:someone@example.test`)).toEqual({});
    expect(listUnsubscribeHeaders(`${SITE}/x\r\nBcc: someone@example.test`)).toEqual({});
  });

  it("recognises the body a mail provider posts", () => {
    expect(isOneClickBody("List-Unsubscribe=One-Click")).toBe(true);
    expect(isOneClickBody("a=b&List-Unsubscribe=One-Click")).toBe(true);
    expect(isOneClickBody("")).toBe(false);
    expect(isOneClickBody("List-Unsubscribe=Two-Click")).toBe(false);
    expect(isOneClickBody("list-unsubscribe=one-click")).toBe(false);
  });
});
