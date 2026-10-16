/**
 * The telephony adapter (spec B8.4: startCall, onCallEvent, fetchRecording). Providers: Exotel (click-to-call: it rings
 * the counsellor's mobile first, then the student, records the call and posts status callbacks) and the mock, which
 * plays the same events for test leads. Another provider is one more `parse…` and `start…` pair here.
 * The database (b2c.call_start, b2c.call_event) decides everything; this file only speaks the provider's HTTP.
 */
export type CallStatus = "initiated" | "ringing" | "answered" | "completed" | "no_answer" | "busy" | "failed" | "agent_no_answer" | "missed";
export type CallEvent = {
  provider: string; provider_ref?: string; call_id?: number; status: CallStatus; provider_status?: string; direction: "in" | "out";
  from?: string; agent?: string; duration_s?: number; recording_url?: string; cost?: number; event_key?: string;
};

export type ExotelConfig = { sid: string; apiKey: string; apiToken: string; subdomain: string; callerId: string | null; webhookKey: string };

export function exotelConfig(env: Record<string, string | undefined> = process.env): ExotelConfig | null {
  const { EXOTEL_SID: sid, EXOTEL_API_KEY: apiKey, EXOTEL_API_TOKEN: apiToken, EXOTEL_WEBHOOK_KEY: webhookKey } = env;
  if (!sid || !apiKey || !apiToken || !webhookKey) return null;
  return { sid, apiKey, apiToken, webhookKey, subdomain: env.EXOTEL_SUBDOMAIN || "api.in.exotel.com", callerId: env.EXOTEL_CALLER_ID || null };
}

const digits = (s: string | null | undefined) => (s ?? "").replace(/\D/g, "");

/** Exotel's status words → ours. */
export function exotelStatus(s: string | undefined): CallStatus | null {
  const v = (s ?? "").toLowerCase().replace(/_/g, "-");
  if (v === "completed") return "completed";
  if (v === "no-answer") return "no_answer";
  if (v === "busy") return "busy";
  if (v === "failed" || v === "canceled" || v === "cancelled") return "failed";
  if (v === "in-progress" || v === "answered") return "answered";
  if (v === "ringing") return "ringing";
  if (v === "queued" || v === "initiated") return "initiated";
  return null;
}

/**
 * One Exotel callback → our event. Outbound (Calls/connect): Legs[0] is the counsellor, Legs[1] the student; if the
 * counsellor's leg never connected the student was not rung (agent_no_answer). Inbound (a Passthru applet in the call
 * flow): DialCallStatus tells whether a counsellor picked up; anything but completed is a missed call.
 */
export function parseExotel(q: Record<string, unknown>): CallEvent | null {
  const g = (k: string) => (q[k] === undefined || q[k] === null || q[k] === "" ? undefined : String(q[k]));
  const sid = g("CallSid");
  if (!sid) return null;
  const direction = (g("Direction") ?? "").toLowerCase().startsWith("in") ? "in" : "out";
  let legs: unknown = q.Legs;
  if (typeof legs === "string") { try { legs = JSON.parse(legs); } catch { legs = undefined; } }
  const legList = Array.isArray(legs) ? (legs as Record<string, unknown>[]) : [];
  const custom = g("CustomField");
  const num = (v: string | undefined) => (v !== undefined && Number.isFinite(Number(v)) ? Number(v) : undefined);
  const legTalk = num(legList[1] ? String(legList[1].OnCallDuration ?? "") : undefined);
  const base = {
    provider: "exotel", provider_ref: sid, call_id: custom && /^\d+$/.test(custom) ? Number(custom) : undefined, direction,
    from: g("From") ?? g("CallFrom"), recording_url: g("RecordingUrl"), cost: num(g("Price")),
  } as const;
  if (direction === "in") {
    const dial = g("DialCallStatus");
    const talk = num(g("DialCallDuration")) ?? num(g("ConversationDuration"));
    const status: CallStatus = !dial ? "ringing" : dial.toLowerCase() === "completed" && (talk ?? 1) > 0 ? "completed" : "missed";
    return { ...base, status, provider_status: dial ?? g("Status"), agent: g("DialWhomNumber"), duration_s: talk, event_key: `exotel:${sid}:${status}` };
  }
  const raw = g("Status") ?? g("CallStatus");
  const answeredEvent = (g("EventType") ?? "").toLowerCase() === "answered";
  let status = answeredEvent ? "answered" : exotelStatus(raw);
  if (!status) return null;
  const agentLeg = legList[0] ? exotelStatus(String(legList[0].Status ?? "")) : null;
  if (["no_answer", "busy", "failed"].includes(status) && agentLeg && agentLeg !== "completed" && agentLeg !== "answered") status = "agent_no_answer";
  const talk = num(g("ConversationDuration")) ?? legTalk ?? num(g("DialCallDuration"));
  return { ...base, status, provider_status: raw, duration_s: talk, event_key: `exotel:${sid}:${status}` };
}

/** Exotel Calls/connect: rings the counsellor (From), then the student (To), recorded, callbacks to our webhook. */
export async function exotelConnect(cfg: ExotelConfig, o: { agent: string; student: string; callerId: string | null; callbackUrl: string; callId: number }): Promise<{ sid: string | null }> {
  const callerId = digits(o.callerId ?? cfg.callerId);
  if (!callerId) throw new Error("Set the Exotel caller ID (Settings → telephony, or EXOTEL_CALLER_ID).");
  const form = new URLSearchParams({
    From: "+" + digits(o.agent), To: "+" + digits(o.student), CallerId: callerId, CallType: "trans", Record: "true", RecordingChannels: "dual",
    TimeLimit: "3600", TimeOut: "30", StatusCallback: o.callbackUrl, "StatusCallbackEvents[0]": "terminal", "StatusCallbackEvents[1]": "answered",
    StatusCallbackContentType: "application/json", CustomField: String(o.callId),
  });
  const r = await fetch(`https://${cfg.subdomain}/v1/Accounts/${encodeURIComponent(cfg.sid)}/Calls/connect.json`, {
    method: "POST", body: form, cache: "no-store", signal: AbortSignal.timeout(15_000),
    headers: { authorization: "Basic " + Buffer.from(`${cfg.apiKey}:${cfg.apiToken}`).toString("base64"), "content-type": "application/x-www-form-urlencoded" },
  });
  const text = await r.text();
  let data: Record<string, unknown> = {};
  try { data = JSON.parse(text) as Record<string, unknown>; } catch { /* not JSON */ }
  if (!r.ok) {
    const msg = (data.RestException as { Message?: string } | undefined)?.Message ?? text;
    throw new Error(`Exotel refused the call (${r.status}): ${String(msg).slice(0, 200)}`);
  }
  return { sid: ((data.Call as { Sid?: string } | undefined)?.Sid) ?? null };
}

/** A recording's bytes. Exotel's links take the account's basic auth; the mock returns one second of silence. */
export async function fetchRecording(provider: string, url: string, cfg: ExotelConfig | null): Promise<{ bytes: Uint8Array; contentType: string; ext: string }> {
  if (provider === "mock" || url.startsWith("mock://")) return { bytes: silentWav(1), contentType: "audio/wav", ext: "wav" };
  if (!/^https:\/\//.test(url)) throw new Error("not an https recording link");
  const r = await fetch(url, {
    cache: "no-store", signal: AbortSignal.timeout(60_000),
    headers: cfg && provider === "exotel" ? { authorization: "Basic " + Buffer.from(`${cfg.apiKey}:${cfg.apiToken}`).toString("base64") } : {},
  });
  if (!r.ok) throw new Error(`recording download failed (${r.status})`);
  const type = (r.headers.get("content-type") ?? "audio/mpeg").split(";")[0]!.trim();
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.byteLength > 50 * 1024 * 1024) throw new Error("recording larger than 50 MB");
  return { bytes, contentType: type.startsWith("audio/") ? type : "audio/mpeg", ext: type.includes("wav") ? "wav" : "mp3" };
}

/** A valid mono 8 kHz 16-bit WAV of the given seconds of silence (the mock's "recording"). */
export function silentWav(seconds: number): Uint8Array {
  const rate = 8000, n = rate * seconds, b = Buffer.alloc(44 + n * 2);
  b.write("RIFF", 0); b.writeUInt32LE(36 + n * 2, 4); b.write("WAVE", 8); b.write("fmt ", 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write("data", 36); b.writeUInt32LE(n * 2, 40);
  return new Uint8Array(b);
}
