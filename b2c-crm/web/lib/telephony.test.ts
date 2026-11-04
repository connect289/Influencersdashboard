import { afterEach, describe, expect, it, vi } from "vitest";
import type { fetchChecked } from "./safe-fetch";
import { exotelConfig, exotelStatus, fetchRecording, parseExotel, silentWav } from "./telephony";

const CFG = exotelConfig({ EXOTEL_SID: "s", EXOTEL_API_KEY: "key", EXOTEL_API_TOKEN: "token", EXOTEL_WEBHOOK_KEY: "w" })!;

describe("recording downloads", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
  it("refuses a recording link outside Exotel's hosts and sends nothing", async () => {
    const fetchSpy = vi.fn(async () => new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "audio/mpeg" } }));
    vi.stubGlobal("fetch", fetchSpy);
    for (const url of ["https://evil.example.com/r.mp3", "https://169.254.169.254/latest/meta-data/", "http://recordings.exotel.com/r.mp3"]) {
      await expect(fetchRecording("exotel", url, CFG), url).rejects.toThrow(/refused/);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });
  it("offers Exotel's credentials only for Exotel's hosts", async () => {
    vi.stubEnv("EXOTEL_RECORDING_HOSTS", "files.example.net");
    const calls: { url: string; credentialHosts: readonly string[] | undefined; creds: Record<string, string> | undefined; hosts: readonly string[] }[] = [];
    const fetcher = (async (url, rules, creds) => {
      calls.push({ url, credentialHosts: rules.credentialHosts, creds, hosts: rules.hosts });
      return { status: 200, contentType: "audio/mpeg", body: Buffer.from("ID3"), url };
    }) as typeof fetchChecked;
    const f = await fetchRecording("exotel", "https://recordings.exotel.com/a.mp3", CFG, fetcher);
    expect(f).toMatchObject({ contentType: "audio/mpeg", ext: "mp3" });
    await fetchRecording("exotel", "https://files.example.net/a.mp3", CFG, fetcher);
    expect(calls.map((c) => c.url)).toEqual(["https://recordings.exotel.com/a.mp3", "https://files.example.net/a.mp3"]);
    for (const c of calls) {
      expect(c.creds?.authorization).toBe("Basic " + Buffer.from("key:token").toString("base64"));
      expect(c.credentialHosts).toEqual([".exotel.com", ".exotel.in"]);   // fetchChecked adds them only on these hosts
      expect(c.hosts).toContain("files.example.net");
    }
  });
});

describe("Exotel callbacks", () => {
  it("maps a completed outbound call with talk time and recording", () => {
    const e = parseExotel({ CallSid: "abc", Status: "completed", Direction: "outbound-api", CustomField: "42", ConversationDuration: "250", RecordingUrl: "https://x/r.mp3",
      Legs: [{ Status: "completed", OnCallDuration: 260 }, { Status: "completed", OnCallDuration: 250 }] });
    expect(e).toMatchObject({ provider: "exotel", provider_ref: "abc", call_id: 42, status: "completed", direction: "out", duration_s: 250, recording_url: "https://x/r.mp3", event_key: "exotel:abc:completed" });
  });
  it("knows when the counsellor's own phone did not answer", () => {
    expect(parseExotel({ CallSid: "a", Status: "no-answer", Legs: JSON.stringify([{ Status: "no-answer" }]) })?.status).toBe("agent_no_answer");
    expect(parseExotel({ CallSid: "a", Status: "no-answer", Legs: [{ Status: "completed" }, { Status: "no-answer" }] })?.status).toBe("no_answer");
    expect(parseExotel({ CallSid: "a", Status: "busy", Legs: [{ Status: "completed" }, { Status: "busy" }] })?.status).toBe("busy");
  });
  it("reads the answered event and ignores junk", () => {
    expect(parseExotel({ CallSid: "a", EventType: "answered", Status: "in-progress" })?.status).toBe("answered");
    expect(parseExotel({ Status: "completed" })).toBeNull();
    expect(parseExotel({ CallSid: "a", Status: "weird" })).toBeNull();
    expect(exotelStatus("canceled")).toBe("failed");
  });
  it("turns an inbound Passthru into ringing, completed or missed", () => {
    expect(parseExotel({ CallSid: "i", Direction: "incoming", CallFrom: "09876543210" })).toMatchObject({ status: "ringing", direction: "in", from: "09876543210" });
    expect(parseExotel({ CallSid: "i", Direction: "incoming", CallFrom: "0987", DialCallStatus: "completed", DialCallDuration: "75", DialWhomNumber: "0900" }))
      .toMatchObject({ status: "completed", duration_s: 75, agent: "0900" });
    expect(parseExotel({ CallSid: "i", Direction: "incoming", CallFrom: "0987", DialCallStatus: "no-answer" })?.status).toBe("missed");
  });
  it("needs every secret before it is on", () => {
    expect(exotelConfig({ EXOTEL_SID: "s", EXOTEL_API_KEY: "k", EXOTEL_API_TOKEN: "t" })).toBeNull();
    expect(exotelConfig({ EXOTEL_SID: "s", EXOTEL_API_KEY: "k", EXOTEL_API_TOKEN: "t", EXOTEL_WEBHOOK_KEY: "w" })?.subdomain).toBe("api.in.exotel.com");
  });
  it("makes a valid silent WAV for the mock", () => {
    const w = Buffer.from(silentWav(1));
    expect(w.toString("ascii", 0, 4)).toBe("RIFF");
    expect(w.readUInt32LE(40)).toBe(16000);
    expect(w.length).toBe(44 + 16000);
  });
});
