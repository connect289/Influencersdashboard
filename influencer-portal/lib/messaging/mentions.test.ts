import { describe, expect, it } from "vitest";
import { mentionToken, messageParts, parseMentions, plainText } from "./mentions";

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
});
