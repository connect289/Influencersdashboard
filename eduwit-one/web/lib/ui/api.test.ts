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

  it("keeps the other mappings", () => {
    expect(fromDbError({ code: "42501" }).message).toBe("Your role cannot do this.");
    expect(fromDbError({ code: "22023", message: "nothing changed" }).message).toBe("Nothing changed.");
    expect(fromDbError({ code: "", message: "TypeError: fetch failed" }).message).toBe(
      "The database did not answer as expected. Try again.",
    );
  });
});
