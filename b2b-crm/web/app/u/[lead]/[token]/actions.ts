"use server";
import { headers } from "next/headers";
import { clientIp } from "@/lib/security";
import { parseUnsubscribeLink, recordUnsubscribe } from "@/lib/unsubscribe";

export type UnsubscribeState = { status: "done" } | { status: "error"; message: string } | undefined;

const BAD_LINK = "This link is incomplete. Open the Unsubscribe link in your latest email from Eduwit again.";
const BUSY = "Too many requests right now. Please wait a minute and press the button again.";
const UNAVAILABLE = "We could not record this just now. Please try again in a minute.";

/**
 * The button on /u/<lead>/<token> (M34j). A signed-out visitor: the two values come from the page's hidden fields and are
 * checked again here. A token that is not this lead's is answered like a valid one (lib/unsubscribe.ts).
 */
export async function confirmUnsubscribe(_prev: UnsubscribeState, form: FormData): Promise<UnsubscribeState> {
  const link = parseUnsubscribeLink({ lead: form.get("lead"), token: form.get("token") });
  if (!link) return { status: "error", message: BAD_LINK };
  const outcome = await recordUnsubscribe(link, clientIp(await headers()), "link");
  if (outcome.kind === "rate_limited") return { status: "error", message: BUSY };
  if (outcome.kind === "unavailable") return { status: "error", message: UNAVAILABLE };
  return { status: "done" };
}
