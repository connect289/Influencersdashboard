// Unsubscribe links in emails (D-198): withdrawing consent is as easy as giving it, and mail providers get the
// one-click header they ask bulk senders for. A link names one account and one kind of email: a notification group
// from the catalogue, or the digest. It is signed with HMAC-SHA256 under a key derived from UNSUBSCRIBE_SECRET, so
// checking it needs no database read and nobody can make one for someone else. It carries the account's id as bytes
// and the category: no name, email address or phone number. Following it can only turn email OFF for that kind, and
// an email may be opened years after it was sent, so links do not expire; changing the secret ends every link sent
// before. Required notices carry no link. Pure (node:crypto only).
import { createHmac, timingSafeEqual } from "node:crypto";
import { EVENT_GROUPS, eventDef, type Audience, type EventGroup } from "./catalogue";

export const UNSUBSCRIBE_CATEGORIES = [...EVENT_GROUPS, "digest"] as const;
export type UnsubscribeCategory = EventGroup | "digest";

export interface UnsubscribeClaims {
  userId: string;
  category: UnsubscribeCategory;
}

/** The signing secret's minimum length (lib/env.ts refuses a shorter one). */
export const UNSUBSCRIBE_SECRET_MIN = 32;

const VERSION = "v1";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
/** Version "." base64url(16-byte account id + category) "." base64url(32-byte MAC). */
const TOKEN = /^v1\.[A-Za-z0-9_-]{24,48}\.[A-Za-z0-9_-]{43}$/;
/** The longest token this version makes; anything longer is not ours. */
export const UNSUBSCRIBE_TOKEN_MAX = 100;

/** The MAC covers the version and the encoded payload exactly as they appear in the link. */
function mac(secret: string, signed: string): string {
  const key = createHmac("sha256", secret).update("inf:unsubscribe:v1").digest();
  return createHmac("sha256", key).update(signed).digest("base64url");
}

function isCategory(v: string): v is UnsubscribeCategory {
  return (UNSUBSCRIBE_CATEGORIES as readonly string[]).includes(v);
}

export function signUnsubscribe(secret: string, claims: UnsubscribeClaims): string {
  if (secret.length < UNSUBSCRIBE_SECRET_MIN) throw new Error("the unsubscribe signing secret is too short");
  if (!UUID.test(claims.userId) || !isCategory(claims.category)) throw new Error("invalid unsubscribe claims");
  const payload = Buffer.concat([
    Buffer.from(claims.userId.replace(/-/g, ""), "hex"),
    Buffer.from(claims.category, "ascii"),
  ]).toString("base64url");
  const signed = `${VERSION}.${payload}`;
  return `${signed}.${mac(secret, signed)}`;
}

/** The claims of a link, or null for anything that is not a link we signed with this secret. */
export function verifyUnsubscribe(secret: string, token: string): UnsubscribeClaims | null {
  if (secret.length < UNSUBSCRIBE_SECRET_MIN || typeof token !== "string") return null;
  if (token.length > UNSUBSCRIBE_TOKEN_MAX || !TOKEN.test(token)) return null;
  const [version = "", payload = "", signature = ""] = token.split(".");
  const given = Buffer.from(signature, "ascii");
  const expected = Buffer.from(mac(secret, `${version}.${payload}`), "ascii");
  // Constant time, and on the encoded form, so exactly one spelling of a signature is accepted.
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  const bytes = Buffer.from(payload, "base64url");
  const hex = bytes.subarray(0, 16).toString("hex");
  const userId = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  const category = bytes.subarray(16).toString("ascii");
  if (version !== VERSION || !UUID.test(userId) || !isCategory(category)) return null;
  return { userId, category };
}

/**
 * The kind of email a notification belongs to for unsubscribing, or null when it carries no link: a required notice
 * (the catalogue or the sender marked it mandatory, exactly the set a person cannot switch off in their notification
 * settings) or an event outside the catalogue.
 */
export function unsubscribeCategory(event: string, mandatory: boolean): UnsubscribeCategory | null {
  const def = eventDef(event);
  if (mandatory || !def || def.mandatory) return null;
  return event.startsWith("digest.") ? "digest" : def.group;
}

export interface UnsubscribeLinks {
  /** The public page that names the kind of email and asks to confirm (the link in the email footer). */
  pageUrl: string;
  /** The RFC 8058 endpoint mail providers POST to (the List-Unsubscribe header). */
  oneClickUrl: string;
}

/**
 * Both links for one account and one notification, or null when its email carries none: a required notice, or no
 * signing secret is configured (the email is still sent).
 */
export function unsubscribeLinks(
  secret: string | undefined,
  siteUrl: string,
  userId: string,
  event: string,
  mandatory: boolean,
): UnsubscribeLinks | null {
  const category = unsubscribeCategory(event, mandatory);
  if (!secret || secret.length < UNSUBSCRIBE_SECRET_MIN || !category || !UUID.test(userId)) return null;
  const base = `${siteUrl.replace(/\/$/, "")}/unsubscribe/${signUnsubscribe(secret, { userId, category })}`;
  return { pageUrl: base, oneClickUrl: `${base}/one-click` };
}

/** Each portal's notification settings page. */
export const SETTINGS_PATHS = {
  creator: "/creator/notifications/settings",
  agency: "/agency/notifications/settings",
  staff: "/admin/notifications/settings",
} as const satisfies Record<Audience, string>;

/**
 * The one-click unsubscribe headers (RFC 8058) for a message, or none. The standard asks for an HTTPS address, so a
 * plain-HTTP site (local development) sends no header; the footer link still works there.
 */
export function listUnsubscribeHeaders(oneClickUrl: string | null | undefined): Record<string, string> {
  if (!oneClickUrl || !/^https:\/\/[^\s<>,"]+$/.test(oneClickUrl)) return {};
  return { "List-Unsubscribe": `<${oneClickUrl}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" };
}

/** Whether a POST body is the one RFC 8058 defines (form-encoded `List-Unsubscribe=One-Click`). */
export function isOneClickBody(body: string): boolean {
  return new URLSearchParams(body).get("List-Unsubscribe") === "One-Click";
}
