import { createHash, randomBytes } from "node:crypto";
import { describe, expect, it } from "vitest";
import { gmailTokenKey } from "./env";
import { authUrl, idTokenEmail, pkce, refreshAccess, sameState, sealToken, tokenAad, unsealToken } from "./gmail-oauth";

const key = randomBytes(32);
const jwt = (claims: Record<string, unknown>) => `${Buffer.from("{}").toString("base64url")}.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.sig`;

describe("sealing the Gmail refresh token (AES-256-GCM)", () => {
  it("opens with the same key and person, and never shows the token", () => {
    const sealed = sealToken("1//refresh-token", key, tokenAad("u1"));
    expect(sealed.startsWith("v1.")).toBe(true);
    expect(sealed).not.toContain("refresh");
    expect(unsealToken(sealed, key, tokenAad("u1"))).toBe("1//refresh-token");
  });

  it("uses a fresh IV each time", () => {
    expect(sealToken("same", key, "a")).not.toBe(sealToken("same", key, "a"));
  });

  it("refuses another person's row, another key or a changed byte", () => {
    const sealed = sealToken("1//refresh-token", key, tokenAad("u1"));
    expect(() => unsealToken(sealed, key, tokenAad("u2"))).toThrow();
    expect(() => unsealToken(sealed, randomBytes(32), tokenAad("u1"))).toThrow();
    const raw = Buffer.from(sealed.slice(3), "base64url");
    raw[raw.length - 1]! ^= 1;
    expect(() => unsealToken("v1." + raw.toString("base64url"), key, tokenAad("u1"))).toThrow();
    expect(() => unsealToken("v0.abc", key, "x")).toThrow(/format/);
  });

  it("reads the key from hex or base64 and refuses a wrong length", () => {
    expect(gmailTokenKey(undefined)).toBeNull();
    expect(gmailTokenKey(key.toString("hex"))!.equals(key)).toBe(true);
    expect(gmailTokenKey(key.toString("base64"))!.equals(key)).toBe(true);
    expect(gmailTokenKey(key.toString("base64url"))!.equals(key)).toBe(true);
    expect(() => gmailTokenKey("too-short")).toThrow(/32 bytes/);
  });
});

describe("the Gmail authorization request", () => {
  it("uses PKCE S256", () => {
    const p = pkce();
    expect(p.challenge).toBe(createHash("sha256").update(p.verifier).digest("base64url"));
    expect(p.verifier.length).toBeGreaterThanOrEqual(43);
  });

  it("asks for offline access, the three Gmail scopes, the state and the challenge", () => {
    const u = new URL(authUrl({ clientId: "cid", redirectUri: "https://b2c.eduwit.in/auth/google/gmail/callback", state: "st", challenge: "ch", email: "priya@eduwit.in" }));
    const q = u.searchParams;
    expect(u.origin + u.pathname).toBe("https://accounts.google.com/o/oauth2/v2/auth");
    expect(q.get("access_type")).toBe("offline");
    expect(q.get("prompt")).toBe("consent");
    expect(q.get("scope")!.split(" ")).toEqual(expect.arrayContaining([
      "https://www.googleapis.com/auth/gmail.send", "https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.metadata", "email"]));
    expect([q.get("state"), q.get("code_challenge"), q.get("code_challenge_method"), q.get("login_hint"), q.get("hd")]).toEqual(["st", "ch", "S256", "priya@eduwit.in", "eduwit.in"]);
  });

  it("compares the state in constant time and refuses a missing one", () => {
    expect(sameState("abc", "abc")).toBe(true);
    expect(sameState("abc", "abd")).toBe(false);
    expect(sameState(null, "abc")).toBe(false);
    expect(sameState("abc", "abcd")).toBe(false);
  });

  it("takes the verified email for this client from the id_token", () => {
    expect(idTokenEmail(jwt({ aud: "cid", iss: "https://accounts.google.com", email: "Priya@Eduwit.in", email_verified: true }), "cid")).toBe("priya@eduwit.in");
    expect(idTokenEmail(jwt({ aud: "other", iss: "https://accounts.google.com", email: "priya@eduwit.in", email_verified: true }), "cid")).toBeNull();
    expect(idTokenEmail(jwt({ aud: "cid", iss: "https://evil.example", email: "priya@eduwit.in", email_verified: true }), "cid")).toBeNull();
    expect(idTokenEmail(jwt({ aud: "cid", iss: "accounts.google.com", email: "priya@eduwit.in", email_verified: false }), "cid")).toBeNull();
    expect(idTokenEmail(undefined, "cid")).toBeNull();
  });
});

describe("refreshing the access token", () => {
  it("returns the token, or Google's error such as invalid_grant after a revocation", async () => {
    const ok = (async () => new Response(JSON.stringify({ access_token: "ya29.x" }))) as unknown as typeof fetch;
    expect(await refreshAccess({ clientId: "c", clientSecret: "s", refreshToken: "r" }, ok)).toEqual({ ok: true, token: "ya29.x" });
    const revoked = (async () => new Response(JSON.stringify({ error: "invalid_grant", error_description: "Token has been expired or revoked." }), { status: 400 })) as unknown as typeof fetch;
    expect(await refreshAccess({ clientId: "c", clientSecret: "s", refreshToken: "r" }, revoked)).toEqual({ ok: false, error: "invalid_grant: Token has been expired or revoked." });
  });
});
