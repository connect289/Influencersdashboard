import { describe, expect, it } from "vitest";
import { decodeLink, encodeLink, readToken, signToken } from "./tokens";

const K = "k".repeat(40);

describe("email link tokens", () => {
  it("round-trips each link kind", () => {
    for (const l of [{ kind: "unsubscribe", lead: 42, channel: "email" }, { kind: "open", email: 7 },
                     { kind: "click", email: 7, link: "other", url: "https://x.in/a?b=1|c" }] as const) {
      expect(decodeLink(encodeLink(l, K), K)).toEqual(l);
    }
  });
  it("refuses a changed payload or another key", () => {
    const t = signToken("o|7", K);
    const forged = Buffer.from("o|8").toString("base64url") + "." + t.split(".")[1];
    expect(readToken(forged, K)).toBeNull();
    expect(readToken(t, "z".repeat(40))).toBeNull();
    expect(readToken("garbage", K)).toBeNull();
  });
});
