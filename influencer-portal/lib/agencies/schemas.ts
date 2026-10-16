import { z } from "zod";
import { GSTIN_RE, normalisePhone } from "@/lib/creators/schemas";

export const AGENCY_GRANTS = ["view", "deliverables", "negotiate", "earnings"] as const;
export type AgencyGrant = (typeof AGENCY_GRANTS)[number];

export const agencyInput = z.object({
  id: z.uuid().optional(),
  name: z.string().trim().min(2).max(120),
  legalName: z.string().trim().max(160).default(""),
  email: z.union([z.literal(""), z.email().max(254)]).default(""),
  phone: z
    .string()
    .trim()
    .max(20)
    .default("")
    .refine((v) => v === "" || normalisePhone(v) !== null, "phone"),
  gstin: z
    .string()
    .default("")
    .transform((v) => v.replace(/\s+/g, "").toUpperCase())
    .refine((v) => v === "" || GSTIN_RE.test(v), "gstin"),
  notes: z.string().trim().max(2000).default(""),
});
export type AgencyInput = z.input<typeof agencyInput>;

export const memberInput = z.object({
  agencyId: z.uuid(),
  email: z
    .email()
    .max(254)
    .transform((v) => v.trim().toLowerCase()),
  fullName: z.string().trim().min(1).max(120),
  role: z.enum(["owner", "member"]),
});
export type MemberInput = z.input<typeof memberInput>;

/** Grants the creator chooses. "View" is implied by any other grant and always on for an accepted link. */
export const grantsInput = z.object({
  deliverables: z.boolean(),
  negotiate: z.boolean(),
  earnings: z.boolean(),
});
export type GrantsInput = z.infer<typeof grantsInput>;
