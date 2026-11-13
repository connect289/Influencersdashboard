import { describe, expect, it } from "vitest";
import { fromDbError, SETTING_CONFLICT } from "./api.ts";

describe("fromDbError (D-137)", () => {
  it("maps a stale settings version to a conflict the person can act on", () => {
    const e = fromDbError({ code: "40001", message: "setting checks changed since the page loaded it" });
    expect(e.kind).toBe("conflict");
    expect(e.message).toBe(SETTING_CONFLICT);
    expect(SETTING_CONFLICT).toBe("Someone else changed this setting — reload and try again.");
  });

  it("says the database took too long when the client's time limit cut the call", () => {
    const e = fromDbError({ code: "", message: "TimeoutError: The operation was aborted due to timeout" });
    expect(e.kind).toBe("unavailable");
    expect(e.message).toBe("The database took too long to answer. Try again in a minute.");
  });

  it("shows an owner-only refusal that says what it is about, and nothing else a 42501 carries (D-139)", () => {
    const e = fromDbError({
      code: "42501",
      message: "only the owner can mute a top-priority alarm: check B2B-03 is P1",
    });
    expect(e.kind).toBe("not_allowed");
    expect(e.message).toBe("Only the owner can mute a top-priority alarm: check B2B-03 is P1.");
    expect(
      fromDbError({ code: "42501", message: "only the owner can mute a top-priority alarm: app b2b has P1 checks" })
        .message,
    ).toBe("Only the owner can mute a top-priority alarm: app b2b has P1 checks.");
    for (const message of ["not allowed", "permission denied for function ui_mute", "owner only", undefined])
      expect(fromDbError({ code: "42501", message }).message).toBe("Your role cannot do this.");
  });

  it("keeps the other mappings", () => {
    expect(fromDbError({ code: "42501" }).message).toBe("Your role cannot do this.");
    expect(fromDbError({ code: "22023", message: "nothing changed" }).message).toBe("Nothing changed.");
    expect(fromDbError({ code: "", message: "TypeError: fetch failed" }).message).toBe(
      "The database did not answer as expected. Try again.",
    );
  });
});
