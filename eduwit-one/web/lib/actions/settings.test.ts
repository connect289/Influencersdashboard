import { beforeEach, describe, expect, it, vi } from "vitest";

// Saving a setting over the version the page loaded (D-137): the action sends that version, and the database's refusal
// (40001: someone else saved in between) reaches the person as a sentence they can act on. The privileges shortcut
// sends the hash of the list it showed. The real act() and ui() run; only the session and the client are stand-ins.

const rpc = vi.fn();
vi.mock("../session.ts", () => ({ assertUser: async () => ({ role: "owner" }) }));
vi.mock("../supabase.ts", () => ({ userClient: async () => ({ rpc }) }));

const { acknowledgePrivileges, saveSetting } = await import("./settings.ts");

function form(fields: Record<string, string>): FormData {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.set(k, v);
  return f;
}

beforeEach(() => {
  rpc.mockReset();
});

describe("saveSetting", () => {
  it("sends the version the page loaded", async () => {
    rpc.mockResolvedValue({ data: { ok: true, version: 8 }, error: null });
    const r = await saveSetting(
      undefined,
      form({ key: "thresholds", value: '{"job_silent_min": 20}', reason: "slower on Sundays", expected_version: "7" }),
    );
    expect(r).toEqual({ ok: true, message: "Saved as a new version." });
    expect(rpc).toHaveBeenCalledWith(
      "ui_settings_put",
      expect.objectContaining({
        p_key: "thresholds",
        p_value: { job_silent_min: 20 },
        p_reason: "slower on Sundays",
        p_expected_version: 7,
      }),
    );
  });

  it("says someone else changed it when the database refuses the version", async () => {
    rpc.mockResolvedValue({
      data: null,
      error: {
        code: "40001",
        message: "setting thresholds changed since the page loaded it (version 9 now, 7 on the page)",
      },
    });
    const r = await saveSetting(
      undefined,
      form({ key: "thresholds", value: "{}", reason: "slower on Sundays", expected_version: "7" }),
    );
    expect(r).toEqual({ ok: false, error: "Someone else changed this setting — reload and try again." });
  });

  it("says the role cannot when an engineer saves an owner's key", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "42501", message: "owner only" } });
    const r = await saveSetting(
      undefined,
      form({ key: "thresholds", value: "{}", reason: "quieter", expected_version: "7" }),
    );
    expect(r).toEqual({ ok: false, error: "Your role cannot do this." });
  });

  it("without a version, saves as before", async () => {
    rpc.mockResolvedValue({ data: { ok: true, version: 2 }, error: null });
    await saveSetting(undefined, form({ key: "checks", value: "{}", reason: "slower" }));
    expect(rpc.mock.calls[0]?.[1]).not.toHaveProperty("p_expected_version");
  });

  it("refuses a version that is not a whole number before calling the database", async () => {
    const r = await saveSetting(
      undefined,
      form({ key: "checks", value: "{}", reason: "slower", expected_version: "x" }),
    );
    expect(r.ok).toBe(false);
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("acknowledgePrivileges", () => {
  it("sends the count and the hash of the list shown, and needs the hash", async () => {
    rpc.mockResolvedValue({ data: { ok: true, acknowledged: 2 }, error: null });
    const hash = "72d071b226ab708adf5634bc36e65ec9";
    expect(await acknowledgePrivileges(undefined, form({ schema: "ce_admin", expected: "2", hash }))).toEqual({
      ok: true,
      message: "Acknowledged 2 in ce_admin.",
    });
    expect(rpc).toHaveBeenCalledWith(
      "ui_privilege_ack_schema",
      expect.objectContaining({ p_schema: "ce_admin", p_expected: 2, p_hash: hash }),
    );
    rpc.mockReset();
    expect((await acknowledgePrivileges(undefined, form({ schema: "ce_admin", expected: "2" }))).ok).toBe(false);
    expect(rpc).not.toHaveBeenCalled();
  });
});
