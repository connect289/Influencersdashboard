import { createVerify, generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import { rawMessage, sendGmail, signedJwt } from "./gmail";

const decode = (s: string) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");

describe("Gmail as the counsellor", () => {
  it("signs a delegation JWT for the counsellor's mailbox", () => {
    const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    const sa = { email: "b2c@project.iam.gserviceaccount.com", privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString() };
    const jwt = signedJwt(sa, "priya@eduwit.in", "https://www.googleapis.com/auth/gmail.send", 1760000000);
    const [h, c, s] = jwt.split(".");
    expect(JSON.parse(decode(c!))).toMatchObject({ iss: sa.email, sub: "priya@eduwit.in", aud: "https://oauth2.googleapis.com/token", exp: 1760003600 });
    const ok = createVerify("RSA-SHA256").update(`${h}.${c}`).verify(publicKey, Buffer.from(s!.replace(/-/g, "+").replace(/_/g, "/"), "base64"));
    expect(ok).toBe(true);
  });

  it("strips line breaks from headers so a subject cannot inject one", () => {
    const raw = decode(rawMessage({ from: "priya@eduwit.in", to: "asha@example.com\r\nBcc: x@evil.test", subject: "Fees\r\nBcc: y@evil.test", text: "Hello" }));
    expect(raw).not.toMatch(/^Bcc:/m);
    expect(raw).toContain("To: asha@example.com Bcc: x@evil.test");
  });

  it("never calls Google when not live", async () => {
    expect(await sendGmail(null, { from: "a@eduwit.in", to: "b@example.com", subject: "s", text: "t" }, false)).toEqual({ ok: true, dry_run: true });
  });
});
