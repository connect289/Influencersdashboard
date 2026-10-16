import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { requestTarget, sign, signedGetHeaders, signedHeaders, verify, verifyGet } from "./b2b-sign";

const secret = "whsec_" + "x".repeat(48);
const body = '{"id":"evt_1","type":"ping"}';

describe("contract §1 signature", () => {
  it("matches the contract's reference code", () => {
    const ts = "1760000000";
    const expected = "sha256=" + createHmac("sha256", secret).update(`${ts}.${body}`, "utf8").digest("hex");
    expect(sign(body, ts, secret)).toBe(expected);
  });

  it("accepts a fresh, correct signature", () => {
    const now = 1760000000;
    expect(verify(body, String(now), sign(body, String(now), secret), secret, now + 10)).toEqual({ ok: true });
  });

  it("refuses a changed body, a wrong secret and a missing header", () => {
    const now = 1760000000;
    const sig = sign(body, String(now), secret);
    expect(verify(body + " ", String(now), sig, secret, now)).toEqual({ ok: false, reason: "signature" });
    expect(verify(body, String(now), sig, secret + "y", now)).toEqual({ ok: false, reason: "signature" });
    expect(verify(body, null, sig, secret, now)).toEqual({ ok: false, reason: "missing" });
  });

  it("refuses a timestamp more than 5 minutes away, either way", () => {
    const now = 1760000000;
    expect(verify(body, String(now - 301), sign(body, String(now - 301), secret), secret, now).ok).toBe(false);
    expect(verify(body, String(now + 301), sign(body, String(now + 301), secret), secret, now).ok).toBe(false);
    expect(verify(body, "17e8", "sha256=00", secret, now)).toEqual({ ok: false, reason: "timestamp" });
  });

  it("signs B2C → B2B events with the same scheme", () => {
    const h = signedHeaders(body, secret, 1760000000);
    expect(h["x-eduwit-timestamp"]).toBe("1760000000");
    expect(verify(body, h["x-eduwit-timestamp"]!, h["x-eduwit-signature"]!, secret, 1760000000).ok).toBe(true);
  });

  it("signs a GET over its method, path and query (GET /v1/events)", () => {
    const now = 1760000000;
    const target = "/v1/events?since=120&limit=200";
    const h = signedGetHeaders(target, secret, now);
    expect(requestTarget("get", target)).toBe("GET /v1/events?since=120&limit=200");
    expect(h["x-eduwit-signature"]).toBe("sha256=" + createHmac("sha256", secret).update(`${now}.GET ${target}`, "utf8").digest("hex"));
    expect(verifyGet(target, h["x-eduwit-timestamp"]!, h["x-eduwit-signature"]!, secret, now + 5)).toEqual({ ok: true });
  });

  it("refuses a GET whose query was changed, or signed as a POST body", () => {
    const now = 1760000000;
    const h = signedGetHeaders("/v1/events?since=120", secret, now);
    expect(verifyGet("/v1/events?since=0", h["x-eduwit-timestamp"]!, h["x-eduwit-signature"]!, secret, now)).toEqual({ ok: false, reason: "signature" });
    expect(verifyGet("/v1/events?since=120", String(now), sign("", String(now), secret), secret, now)).toEqual({ ok: false, reason: "signature" });
    expect(verifyGet("/v1/events?since=120", String(now - 400), h["x-eduwit-signature"]!, secret, now)).toEqual({ ok: false, reason: "timestamp" });
    expect(verifyGet("/v1/events?since=120", null, null, secret, now)).toEqual({ ok: false, reason: "missing" });
  });
});
