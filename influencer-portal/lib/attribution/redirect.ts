import "server-only";
// The short-link redirect (spec 9.1, INTEGRATION_CONTRACTS §1.3): log the click, ask Witty for an access code for
// WhatsApp links (Route A, 1.5 s timeout, never for crawlers), and send the visitor on. A failure anywhere still
// redirects, so a creator's link never breaks in front of a student.
import { createHmac } from "node:crypto";
import { z } from "zod";
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { rateLimit } from "@/lib/rate-limit";
import { clientIp, rateIp } from "@/lib/security";
import { SETTINGS } from "@/lib/settings/registry";
import { adminClient } from "@/lib/supabase/admin";
import { deviceType, inAppBrowser, isCrawler } from "./bots";
import { normalizeCode } from "./codes";
import {
  landingUrl,
  renderMessage,
  safeHttpsUrl,
  slugify,
  utmFor,
  whatsappUrl,
  withUtm,
} from "./links";

const WITTY_TIMEOUT_MS = 1500;
const linkSchema = z.object({
  id: z.uuid(),
  code: z.string(),
  active: z.boolean(),
  destination: z.enum(["whatsapp_witty", "website_landing", "custom_url"]),
  custom_url: z.string().nullable(),
  platform: z.string().nullable(),
  creator_name: z.string(),
  handle: z.string(),
  campaign_slug: z.string().nullable(),
  /** The campaign's own message template, when it has one. */
  message: z.string().nullable().catch(null),
  programme: z.string().nullable(),
});

/** A keyed hash of the visitor's IP (never stored raw), for the same-device fraud signal. */
function ipHash(ip: string | null): string | null {
  return ip
    ? createHmac("sha256", env().INF_INTERNAL_API_KEY).update(`ip:${ip}`).digest("hex").slice(0, 32)
    : null;
}

async function issueAccessCode(
  p: Record<string, unknown>,
): Promise<{ code: string | null; click_id: number | null }> {
  const call = adminClient()
    .rpc("witty_issue_code", { p: p as never })
    .then(({ data, error }) => {
      if (error) throw new Error(error.message);
      const r = z
        .object({ code: z.string().nullable(), click_id: z.number().nullable().optional() })
        .parse(data);
      return { code: r.code, click_id: r.click_id ?? null };
    });
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("witty timeout")), WITTY_TIMEOUT_MS),
  );
  return Promise.race([call, timeout]);
}

export type RedirectOutcome =
  | { location: string; status: 302 }
  | { location: string; status: 302; inactive: true };

export async function resolveRedirect(
  rawCode: string,
  req: { method: string; headers: Headers; url: string },
): Promise<RedirectOutcome> {
  const inactive = {
    location: new URL("/link-inactive", env().NEXT_PUBLIC_SITE_URL).toString(),
    status: 302 as const,
    inactive: true as const,
  };
  const code = normalizeCode(decodeURIComponent(rawCode));
  if (!code) return inactive;
  const db = adminClient();
  const [resolved, setting] = await Promise.all([
    db.rpc("link_resolve", { p_code: code }),
    db.rpc("setting", { p_key: "attribution.links" }),
  ]);
  const link = linkSchema.nullable().safeParse(resolved.data);
  if (resolved.error || !link.success || !link.data || !link.data.active) return inactive;
  const l = link.data;
  const s = SETTINGS["attribution.links"].schema
    .catch(SETTINGS["attribution.links"].default)
    .parse(setting.data);
  const ua = req.headers.get("user-agent");
  const limited = !(await rateLimit("redirect", rateIp(req.headers))).ok;
  const bot = limited || isCrawler(ua, req.method);
  const utm = utmFor({
    source: s.utm_source,
    platform: l.platform,
    campaign: l.campaign_slug ? slugify(l.campaign_slug) : null,
    code: l.code,
  });
  const ip = clientIp(req.headers);

  let location: string | null = null;
  let access: { code: string | null; click_id: number | null } = { code: null, click_id: null };
  let issueFailed = false;
  if (l.destination === "whatsapp_witty") {
    if (!bot && s.issue_witty_access_codes) {
      try {
        access = await issueAccessCode({
          source: s.utm_source,
          campaign: utm.utm_campaign,
          ...utm,
          creator_code: l.code,
          referrer: req.headers.get("referer"),
          landing_url: req.url,
          ip,
          user_agent: ua,
          device_type: deviceType(ua),
          in_app: inAppBrowser(ua),
          is_bot: false,
        });
      } catch (e) {
        issueFailed = true;
        log.warn("redirect.witty_issue_failed", { code: l.code, error: errorMessage(e) });
      }
    }
    const text = renderMessage(l.message ?? s.deep_link_template, {
      creator_name: l.creator_name,
      programme: l.programme ?? "online programmes",
      code: l.code,
      access_code: access.code,
    });
    location = whatsappUrl(s.witty_whatsapp_number, text);
  } else if (l.destination === "website_landing") {
    location = landingUrl(s.website_base_url, l.handle, l.code, utm);
  } else {
    const u = l.custom_url ? safeHttpsUrl(l.custom_url) : null;
    location = u ? withUtm(u, utm) : null;
  }
  if (!location) return inactive;

  const logged = await db.rpc("click_log", {
    p: {
      link_id: l.id,
      ip_hash: ipHash(ip),
      user_agent: ua,
      referrer: req.headers.get("referer"),
      device: deviceType(ua),
      in_app: inAppBrowser(ua),
      is_bot: bot,
      w2_access_code: access.code,
      w2_click_id: access.click_id,
      issue_failed: issueFailed,
    },
  });
  if (logged.error)
    log.warn("redirect.click_log_failed", { code: l.code, error: logged.error.message });
  return { location, status: 302 };
}
