import "server-only";
import { createHash } from "node:crypto";
import { env, siteUrl } from "./env";
import { log } from "./log";

/**
 * Meta Conversions API adapter (spec 13.3, 9.4). Sends only when a token exists (S-17) and the visitor allowed
 * marketing cookies (D-047); otherwise the event is recorded as skipped. Personal data is SHA-256 hashed as Meta
 * requires; the event id matches the browser Pixel event for de-duplication.
 */
export interface CapiEvent {
  name: "Lead" | "SubmitApplication";
  eventId: string;
  email?: string;
  phone?: string;
  fbp?: string;
  fbc?: string;
  sourcePath?: string;
  at?: Date;
}

const sha = (v: string) => createHash("sha256").update(v.trim().toLowerCase()).digest("hex");

export function capiPayload(e: CapiEvent, testCode?: string) {
  return {
    data: [
      {
        event_name: e.name,
        event_time: Math.floor((e.at ?? new Date()).getTime() / 1000),
        event_id: e.eventId,
        action_source: "website",
        event_source_url: siteUrl(e.sourcePath ?? "/"),
        user_data: {
          em: e.email ? [sha(e.email)] : undefined,
          ph: e.phone ? [sha(e.phone.replace(/\D/g, ""))] : undefined,
          country: [sha("in")],
          fbp: e.fbp,
          fbc: e.fbc,
        },
      },
    ],
    ...(testCode ? { test_event_code: testCode } : {}),
  };
}

export async function sendCapi(e: CapiEvent): Promise<"sent" | "mocked"> {
  const { META_CAPI_TOKEN: token, NEXT_PUBLIC_META_PIXEL_ID: pixel, META_CAPI_TEST_CODE: test } = env();
  if (!token || !pixel) {
    log("info", "capi.mocked", { event: e.name, event_id: e.eventId });
    return "mocked";
  }
  const res = await fetch(`https://graph.facebook.com/v21.0/${pixel}/events?access_token=${encodeURIComponent(token)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(capiPayload(e, test)),
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error(`capi ${res.status}`);
  log("info", "capi.sent", { event: e.name, event_id: e.eventId });
  return "sent";
}
