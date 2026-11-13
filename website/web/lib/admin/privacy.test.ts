import { describe, expect, it } from "vitest";
import {
  checklist,
  closeInput,
  countsSummary,
  exportFileName,
  fulfilInput,
  leadLine,
  privacyError,
  requestId,
  systemInput,
  websiteDone,
} from "./privacy";

describe("privacy request inputs (D-096)", () => {
  it("an erasure or a sent copy needs the request id, its kind and the ticked confirmation", () => {
    expect(fulfilInput.safeParse({ id: "12", kind: "delete", confirm: "on" }).data).toEqual({
      id: 12,
      kind: "delete",
      confirm: "on",
    });
    expect(fulfilInput.safeParse({ id: "12", kind: "export", confirm: "on" }).success).toBe(true);
    // no tick, another value, or a missing box: refused before anything reaches the database
    for (const confirm of [null, undefined, "", "off", "true"])
      expect(fulfilInput.safeParse({ id: "12", kind: "delete", confirm }).success).toBe(false);
    expect(fulfilInput.safeParse({ id: "12", kind: "opt_out", confirm: "on" }).success).toBe(false);
    for (const id of ["", "0", "-3", "1.5", "abc", null, "12; drop"])
      expect(fulfilInput.safeParse({ id, kind: "delete", confirm: "on" }).success).toBe(false);
  });
  it("a checklist tick names Spark or B2B, done or not applicable, with a note", () => {
    expect(
      systemInput.safeParse({ id: "7", system: "spark", state: "done", note: "  Erased in Spark, ref PR-1  " }).data,
    ).toEqual({
      id: 7,
      system: "spark",
      state: "done",
      note: "Erased in Spark, ref PR-1",
    });
    expect(systemInput.safeParse({ id: "7", system: "website", state: "done", note: "done" }).success).toBe(false);
    expect(systemInput.safeParse({ id: "7", system: "b2b", state: "pending", note: "done" }).success).toBe(false);
    expect(systemInput.safeParse({ id: "7", system: "b2b", state: "done", note: " x " }).success).toBe(false);
    expect(systemInput.safeParse({ id: "7", system: "b2b", state: "done", note: "x".repeat(301) }).success).toBe(false);
  });
  it("closing takes done or rejected and an optional note", () => {
    expect(closeInput.safeParse({ id: "3", status: "rejected", note: "" }).success).toBe(true);
    expect(closeInput.safeParse({ id: "3", status: "open", note: "" }).success).toBe(false);
    expect(requestId.safeParse("41").data).toBe(41);
    expect(requestId.safeParse("../41").success).toBe(false);
  });
});

describe("privacy request view", () => {
  it("has no checklist before the website step, then website, Spark, B2B in that order", () => {
    expect(websiteDone({ systems: {} })).toBe(false);
    expect(websiteDone({ systems: null })).toBe(false);
    expect(checklist({ systems: { website: { state: "pending", downloaded_at: "2026-11-13T10:00:00Z" } } })).toEqual(
      [],
    );
    const r = {
      systems: {
        website: { state: "done" as const, did: "erased" as const },
        spark: { state: "pending" as const },
        b2b: { state: "not_applicable" as const },
      },
    };
    expect(websiteDone(r)).toBe(true);
    expect(checklist(r).map((x) => [x.key, x.entry.state])).toEqual([
      ["website", "done"],
      ["spark", "pending"],
      ["b2b", "not_applicable"],
    ]);
  });
  it("names what the website holds, skipping empty kinds", () => {
    expect(countsSummary({ enquiries: 2, applications: 1, chats: 0, chat_messages: 1234, consents: 3 })).toBe(
      "2 verified forms, 1 application or enquiry, 1,234 chat messages",
    );
    expect(countsSummary({})).toBe("no saved items, forms or chats");
    expect(countsSummary(null)).toBe("no saved items, forms or chats");
  });
  it("says whose lead it is, or why to confirm first", () => {
    expect(leadLine({ lead_id: 9, tie: null })).toBe("Lead #9: this account's own lead.");
    expect(leadLine({ lead_id: 9, tie: "other_confirmed_email" })).toContain(
      "confirm in the CRM before acting (the lead has another confirmed email)",
    );
    expect(leadLine({ lead_id: 9, tie: "some_new_reason" })).toContain("(some new reason)");
  });
  it("words every refusal and never shows a bare code", () => {
    for (const code of [
      "forbidden",
      "wrong_kind",
      "account_erased",
      "requester_mismatch",
      "other_requests_open",
      "not_downloaded",
      "lead_not_erased",
      "use_fulfil",
      "fulfil_started",
      "note_required",
    ]) {
      expect(privacyError(code)).not.toBe(privacyError("???"));
      expect(privacyError(code)).not.toContain("_");
    }
    expect(privacyError(undefined)).toBe("That did not work. Reload the page and try again.");
    expect(privacyError("constructor")).toBe("That did not work. Reload the page and try again.");
  });
  it("names the downloaded file by request, not by person", () => {
    expect(exportFileName(41)).toBe("eduwit-data-copy-request-41.json");
  });
});
