import "server-only";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";

export const SIGN_CHANNELS = ["email", "whatsapp"] as const;
export type SignChannel = (typeof SIGN_CHANNELS)[number];

/**
 * The one-time-code channels a signer can use: those turned on in settings (contracts.signing.otp_channels) for which
 * we have a destination. Email is the signed-in address; WhatsApp needs the creator's own phone number on file, so it
 * is offered only to the creator signing for themselves.
 */
export async function signingChannels(opts: {
  email: string | null;
  creatorId: string | null;
}): Promise<{ channel: SignChannel; phone: string | null }[]> {
  const db = adminClient();
  const [setting, creator] = await Promise.all([
    db.rpc("setting", { p_key: "contracts.signing" }),
    opts.creatorId
      ? db.from("creators").select("phone_e164").eq("id", opts.creatorId).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const enabled = z
    .object({ otp_channels: z.array(z.enum(SIGN_CHANNELS)) })
    .catch({ otp_channels: ["email"] })
    .parse(setting.data).otp_channels;
  const phone = creator.data?.phone_e164 ?? null;
  const out: { channel: SignChannel; phone: string | null }[] = [];
  for (const ch of enabled) {
    if (ch === "email" && opts.email) out.push({ channel: ch, phone: null });
    if (ch === "whatsapp" && phone) out.push({ channel: ch, phone });
  }
  return out;
}

/** r•••@example.test, or the last digits of a phone number. */
export function maskDestination(channel: SignChannel, value: string): string {
  if (channel === "whatsapp") return `•••${value.slice(-4)}`;
  const [local = "", domain = ""] = value.split("@");
  return `${local.slice(0, 1)}•••@${domain}`;
}
