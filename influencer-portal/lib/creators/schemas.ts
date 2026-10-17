// Creator profile and KYC input rules, shared by forms (client) and server actions. The database enforces the same
// rules again (inf.valid_pan, inf.valid_ifsc, inf.valid_gstin and table checks), so a bypassed form changes nothing.
import { z } from "zod";

export const PLATFORMS = [
  "instagram",
  "youtube",
  "facebook",
  "linkedin",
  "x",
  "telegram",
  "moj_josh",
  "other",
] as const;
export type Platform = (typeof PLATFORMS)[number];

export const CONTENT_FORMATS = [
  "reel",
  "story",
  "post",
  "youtube_video",
  "short",
  "live",
  "carousel",
  "blog",
  "other",
] as const;
export type ContentFormat = (typeof CONTENT_FORMATS)[number];

export const GST_STATUSES = ["unregistered", "registered", "composition"] as const;
export const CONTACT_KINDS = ["self", "family", "team"] as const;

/** PAN: 5 letters (4th = holder type), 4 digits, 1 letter. */
export const PAN_RE = /^[A-Z]{3}[ABCFGHLJPT][A-Z][0-9]{4}[A-Z]$/;
/** IFSC: 4-letter bank code, a zero, 6-character branch code. */
export const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
/** GSTIN: state code (01–38 or 97), the PAN, entity number, Z, check character. */
export const GSTIN_RE =
  /^(0[1-9]|[12][0-9]|3[0-8]|97)[A-Z]{3}[ABCFGHLJPT][A-Z][0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
export const ACCOUNT_RE = /^\d{9,18}$/;
export const E164_RE = /^\+[1-9]\d{7,14}$/;

const compact = (v: string) => v.replace(/\s+/g, "").toUpperCase();

/** Indian mobile entered in any common shape → +91XXXXXXXXXX; other E.164 numbers pass through. */
export function normalisePhone(raw: string): string | null {
  const s = raw.trim();
  if (!s) return null;
  const digits = s.replace(/\D/g, "");
  if (s.startsWith("+")) return E164_RE.test(`+${digits}`) ? `+${digits}` : null;
  if (digits.length === 10 && /^[6-9]/.test(digits)) return `+91${digits}`;
  if (digits.length === 11 && digits.startsWith("0")) return normalisePhone(digits.slice(1));
  if (digits.length === 12 && digits.startsWith("91")) return normalisePhone(digits.slice(2));
  return null;
}

const httpsUrl = z
  .string()
  .trim()
  .max(500)
  .refine((v) => /^https:\/\/\S{4,}$/.test(v), "https");

const tagList = z.array(z.string().trim().min(1).max(40)).max(20);

export const profileInput = z.object({
  displayName: z.string().trim().min(2).max(80),
  legalName: z.string().trim().max(120).default(""),
  bio: z.string().trim().max(1000).default(""),
  city: z.string().trim().max(80).default(""),
  state: z.string().trim().max(80).default(""),
  phone: z
    .string()
    .trim()
    .max(20)
    .default("")
    .refine((v) => v === "" || normalisePhone(v) !== null, "phone"),
  languages: tagList.default([]),
  niches: tagList.default([]),
  publicPageEnabled: z.boolean().default(false),
  leaderboardOptIn: z.boolean().default(false),
});
export type ProfileInput = z.input<typeof profileInput>;

const optionalCount = z
  .union([z.number().int().min(0).max(10_000_000_000), z.nan(), z.null()])
  .transform((v) => (v === null || Number.isNaN(v) ? null : v));

export const platformInput = z.object({
  id: z.uuid().optional(),
  platform: z.enum(PLATFORMS),
  url: httpsUrl,
  handle: z
    .string()
    .trim()
    .min(1)
    .max(100)
    .transform((v) => v.replace(/^@/, "")),
  followers: optionalCount,
  avgViews: optionalCount,
  engagementRate: z
    .union([z.number().min(0).max(100), z.nan(), z.null()])
    .transform((v) => (v === null || Number.isNaN(v) ? null : Math.round(v * 1000) / 1000)),
});
export type PlatformInput = z.input<typeof platformInput>;

export const rateCardInput = z.object({
  platform: z.enum(PLATFORMS),
  format: z.enum(CONTENT_FORMATS),
  /** Rupees as typed; stored as integer paise. */
  rupees: z.number().min(0).max(100_000_000),
  notes: z.string().trim().max(500).default(""),
});
export type RateCardInput = z.input<typeof rateCardInput>;

export function rupeesToPaise(rupees: number): number {
  return Math.round(rupees * 100);
}

export const portfolioInput = z.object({
  url: httpsUrl.pipe(z.string().max(1000)),
  title: z.string().trim().max(200).default(""),
  caption: z.string().trim().max(1000).default(""),
});
export type PortfolioInput = z.input<typeof portfolioInput>;

export const contactInput = z
  .object({
    kind: z.enum(CONTACT_KINDS),
    label: z.string().trim().max(80).default(""),
    phone: z.string().trim().max(20).default(""),
    email: z.union([z.literal(""), z.email().max(254)]).default(""),
  })
  .refine((v) => v.phone !== "" || v.email !== "", { path: ["phone"], message: "required" })
  .refine((v) => v.phone === "" || normalisePhone(v.phone) !== null, {
    path: ["phone"],
    message: "phone",
  });
export type ContactInput = z.input<typeof contactInput>;

/**
 * KYC form. PAN and account number are optional on edit: blank keeps what is stored (they are never sent back to the
 * browser, so the form cannot prefill them).
 */
export const kycInput = z
  .object({
    pan: z
      .string()
      .default("")
      .transform(compact)
      .refine((v) => v === "" || PAN_RE.test(v), "pan"),
    nameOnPan: z.string().trim().min(2).max(120),
    gstStatus: z.enum(GST_STATUSES),
    gstin: z.string().default("").transform(compact),
    bankAccount: z
      .string()
      .default("")
      .transform((v) => v.replace(/\s+/g, ""))
      .refine((v) => v === "" || ACCOUNT_RE.test(v), "account"),
    ifsc: z
      .string()
      .transform(compact)
      .refine((v) => IFSC_RE.test(v), "ifsc"),
    accountHolder: z.string().trim().min(2).max(120),
    proofPath: z.string().max(200).default(""),
  })
  .refine((v) => v.gstStatus === "unregistered" || GSTIN_RE.test(v.gstin), {
    path: ["gstin"],
    message: "gstin",
  })
  .refine((v) => v.gstStatus === "unregistered" || v.pan === "" || v.gstin.slice(2, 12) === v.pan, {
    path: ["gstin"],
    message: "gstin_pan",
  });
export type KycInput = z.input<typeof kycInput>;

/** Errors the database returns from kyc_save, mapped to message keys. */
export const KYC_DB_ERRORS = {
  invalid_pan: "kyc.errors.pan",
  invalid_account: "kyc.errors.account",
  invalid_ifsc: "kyc.errors.ifsc",
  invalid_gstin: "kyc.errors.gstin",
  invalid_gst_status: "errors.invalidInput",
  gstin_pan_mismatch: "kyc.errors.gstinPan",
} as const;

/** Validation codes from kycInput (issue messages), mapped to message keys. */
export const KYC_FORM_ERRORS = {
  pan: "kyc.errors.pan",
  account: "kyc.errors.account",
  ifsc: "kyc.errors.ifsc",
  gstin: "kyc.errors.gstin",
  gstin_pan: "kyc.errors.gstinPan",
} as const;

/** Name for an uploaded proof: keep letters, digits, dot, dash, underscore; cap length; keep the extension. */
export function safeFileName(name: string): string {
  const cleaned = name
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^[-.]+/, "");
  const dot = cleaned.lastIndexOf(".");
  const ext = dot > 0 ? cleaned.slice(dot).slice(0, 10) : "";
  const base = (dot > 0 ? cleaned.slice(0, dot) : cleaned).slice(0, 80) || "file";
  return `${base}${ext}`;
}

export const KYC_PROOF_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
] as const;
export const KYC_PROOF_MAX_BYTES = 10 * 1024 * 1024;
