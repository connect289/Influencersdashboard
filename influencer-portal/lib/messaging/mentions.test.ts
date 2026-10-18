import { describe, expect, it } from "vitest";
import { encodeMentions, hasUnread, mentionToken, messageParts, parseMentions, plainText } from "./mentions";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

describe("mentions", () => {
  it("makes and parses tokens, each person once", () => {
    const body = `Hi ${mentionToken("Manoj Manager", A)} and ${mentionToken("Farhan]", B)}, also ${mentionToken("Manoj", A)}`;
    expect(parseMentions(body)).toEqual([A, B]);
    expect(plainText(body)).toBe("Hi @Manoj Manager and @Farhan, also @Manoj");
  });

  it("splits a body for display", () => {
    expect(messageParts(`Ping ${mentionToken("Asha", A)}!`)).toEqual([
      { kind: "text", text: "Ping " },
      { kind: "mention", name: "Asha", userId: A },
      { kind: "text", text: "!" },
    ]);
    expect(parseMentions("@[x](user:not-a-uuid) @plain")).toEqual([]);
  });

  it("turns picked @Names into tokens, longest first, and ignores removed ones", () => {
    const picked = [
      { name: "Asha", userId: A },
      { name: "Asha Rao", userId: B },
    ];
    expect(encodeMentions("@Asha Rao and @Asha, see this", picked)).toBe(
      `${mentionToken("Asha Rao", B)} and ${mentionToken("Asha", A)}, see this`,
    );
    expect(encodeMentions("no names left", picked)).toBe("no names left");
    expect(parseMentions(encodeMentions("@Asha @Asha", picked))).toEqual([A]);
  });

  it("knows when others wrote after the last visit", () => {
    const msgs = [
      { mine: false, created_at: "2026-10-01T10:00:00Z" },
      { mine: true, created_at: "2026-10-02T10:00:00Z" },
    ];
    expect(hasUnread(msgs, null)).toBe(true);
    expect(hasUnread(msgs, "2026-10-01T10:00:00Z")).toBe(false);
    expect(hasUnread(msgs, "2026-09-30T00:00:00Z")).toBe(true);
    expect(hasUnread([], null)).toBe(false);
  });
});
