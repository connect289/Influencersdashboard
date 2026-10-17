// Creator CRM rules shared by the admin screens and server actions: pipeline, filters (which live in the URL so
// views are shareable and saveable), outreach vocabularies, task fields and CSV import rows.
import { z } from "zod";
import { normalisePhone, PLATFORMS } from "@/lib/creators/schemas";

export const PIPELINE_STAGES = [
  "prospect",
  "contacted",
  "negotiating",
  "contracted",
  "onboarding",
  "active",
  "paused",
  "dormant",
  "archived",
] as const;
export type PipelineStage = (typeof PIPELINE_STAGES)[number];

export const CREATOR_STATUSES = [
  "prospect",
  "invited",
  "onboarding",
  "active",
  "paused",
  "blocked",
  "archived",
] as const;
export type CreatorStatus = (typeof CREATOR_STATUSES)[number];

export const OUTREACH_CHANNELS = ["call", "whatsapp", "instagram_dm", "email", "meeting", "note", "other"] as const;
export const OUTREACH_OUTCOMES = [
  "no_response",
  "interested",
  "not_interested",
  "follow_up",
  "negotiating",
  "agreed",
  "declined",
  "info",
] as const;
export const TASK_PRIORITIES = ["low", "normal", "high"] as const;
export const SORT_KEYS = ["name", "followers", "updated", "last_activity", "stage", "follow_up"] as const;
export const PAGE_SIZES = [25, 50, 100] as const;

const csvList = (v: unknown) =>
  typeof v === "string" && v !== ""
    ? v
        .split(",")
        .map((x) => x.trim())
        .filter(Boolean)
    : Array.isArray(v)
      ? (v as unknown[])
      : [];

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .optional()
    .transform((v) => v || undefined);
const optionalCount = z
  .union([z.literal(""), z.coerce.number().int().min(0).max(10_000_000_000)])
  .optional()
  .transform((v) => (v === "" || v === undefined ? undefined : v));

/** Filters as they appear in the URL (all strings). Anything invalid is dropped, never an error. */
export const creatorFilterSchema = z.object({
  q: optionalText(80).catch(undefined),
  status: z.preprocess(csvList, z.array(z.enum(CREATOR_STATUSES))).catch([]),
  stage: z.preprocess(csvList, z.array(z.enum(PIPELINE_STAGES))).catch([]),
  platform: z.enum(PLATFORMS).optional().catch(undefined),
  followers_min: optionalCount.catch(undefined),
  followers_max: optionalCount.catch(undefined),
  niche: optionalText(40).catch(undefined),
  language: optionalText(40).catch(undefined),
  city: optionalText(80).catch(undefined),
  state: optionalText(80).catch(undefined),
  tier_id: z.uuid().optional().catch(undefined),
  owner_id: z
    .union([z.literal("me"), z.literal("none"), z.uuid()])
    .optional()
    .catch(undefined),
  tag: optionalText(40).catch(undefined),
  follow_up: z.enum(["overdue", "today"]).optional().catch(undefined),
  /** Creators with an open deal of this type (proposed, negotiating, agreed or active). */
  deal_model: z.enum(["commission_only", "fixed_only", "hybrid", "barter", "custom"]).optional().catch(undefined),
  include_blocked: z
    .enum(["1"])
    .optional()
    .catch(undefined)
    .transform((v) => v === "1" || undefined),
  sort: z.enum(SORT_KEYS).optional().catch(undefined),
  dir: z.enum(["asc", "desc"]).optional().catch(undefined),
  page: z.coerce.number().int().min(1).max(10_000).optional().catch(undefined),
  page_size: z.coerce
    .number()
    .refine((n) => (PAGE_SIZES as readonly number[]).includes(n))
    .optional()
    .catch(undefined),
});
export type CreatorFilters = z.output<typeof creatorFilterSchema>;

/** Keys that are view state (paging, sorting, layout), not filters. */
const NON_FILTER_KEYS = new Set(["sort", "dir", "page", "page_size"]);

export function parseCreatorFilters(sp: Record<string, string | string[] | undefined>): CreatorFilters {
  const flat = Object.fromEntries(Object.entries(sp).map(([k, v]) => [k, Array.isArray(v) ? v.join(",") : v]));
  return creatorFilterSchema.parse(flat);
}

/** URL query string for filters (stable key order; empty values dropped). */
export function creatorFiltersToQuery(
  f: Partial<CreatorFilters>,
  extra: Record<string, string | undefined> = {},
): string {
  const out = new URLSearchParams();
  const entries = Object.entries({ ...f, ...extra }) as [string, unknown][];
  for (const [k, v] of entries.sort(([a], [b]) => a.localeCompare(b))) {
    if (Array.isArray(v)) {
      if (v.length) out.set(k, v.join(","));
    } else if (v === true) out.set(k, "1");
    else if ((typeof v === "string" && v !== "") || typeof v === "number") out.set(k, String(v));
  }
  return out.toString();
}

/** How many filters are active (for the "Filters (3)" badge). */
export function activeFilterCount(f: CreatorFilters): number {
  return Object.entries(f).filter(
    ([k, v]) => !NON_FILTER_KEYS.has(k) && k !== "q" && v !== undefined && !(Array.isArray(v) && v.length === 0),
  ).length;
}

/** The filters to store in a saved view (no paging). */
export function filtersForView(f: CreatorFilters): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(f).filter(([k, v]) => k !== "page" && v !== undefined && !(Array.isArray(v) && v.length === 0)),
  );
}

/** The shape inf.creator_list() expects. */
export function filtersToRpc(f: CreatorFilters): Record<string, unknown> {
  return {
    ...f,
    page: f.page ?? 1,
    page_size: f.page_size ?? 25,
    sort: f.sort ?? "updated",
    dir: f.dir ?? "desc",
  };
}

export const creatorListRow = z.object({
  id: z.uuid(),
  display_name: z.string(),
  handle: z.string(),
  email: z.string().nullable(),
  status: z.string(),
  pipeline_stage: z.string(),
  is_blocked: z.boolean(),
  city: z.string().nullable(),
  state: z.string().nullable(),
  niches: z.array(z.string()),
  tags: z.array(z.string()),
  owner_id: z.uuid().nullable(),
  owner_name: z.string().nullable(),
  tier_name: z.string().nullable(),
  followers: z.number(),
  platforms: z.array(z.string()),
  next_follow_up_at: z.string().nullable(),
  last_activity_at: z.string().nullable(),
  updated_at: z.string(),
  has_account: z.boolean(),
});
export type CreatorListRow = z.infer<typeof creatorListRow>;

export const creatorListResult = z.object({
  total: z.number(),
  page: z.number(),
  page_size: z.number(),
  rows: z.array(creatorListRow),
});

// ---------------------------------------------------------------------------------------------------------------
// Staff create/edit form
// ---------------------------------------------------------------------------------------------------------------
const list = z.array(z.string().trim().min(1).max(40)).max(30);
export const HANDLE_RE = /^[a-z0-9._]{3,30}$/;

export const creatorInput = z.object({
  id: z.uuid().optional(),
  displayName: z.string().trim().min(1).max(120),
  legalName: z.string().trim().max(200).default(""),
  handle: z
    .string()
    .trim()
    .transform((v) => v.replace(/^@/, "").toLowerCase())
    .refine((v) => HANDLE_RE.test(v), "handle"),
  email: z.union([z.literal(""), z.email().max(254)]).default(""),
  phone: z
    .string()
    .trim()
    .max(20)
    .default("")
    .refine((v) => v === "" || normalisePhone(v) !== null, "phone"),
  city: z.string().trim().max(80).default(""),
  state: z.string().trim().max(80).default(""),
  languages: list.default([]),
  niches: list.default([]),
  tags: list.default([]),
  ownerId: z.union([z.literal(""), z.uuid()]).default(""),
  tierId: z.union([z.literal(""), z.uuid()]).default(""),
  source: z.string().trim().max(80).default(""),
  bio: z.string().trim().max(2000).default(""),
});
export type CreatorInput = z.input<typeof creatorInput>;

export const outreachInput = z.object({
  creatorId: z.uuid(),
  channel: z.enum(OUTREACH_CHANNELS),
  direction: z.enum(["outbound", "inbound"]),
  outcome: z.enum(OUTREACH_OUTCOMES),
  notes: z.string().trim().max(4000).default(""),
  /** ISO timestamp or "" */
  nextFollowUp: z.union([z.literal(""), z.iso.datetime({ offset: true })]).default(""),
});
export type OutreachInput = z.input<typeof outreachInput>;

export const taskInput = z.object({
  id: z.uuid().optional(),
  title: z.string().trim().min(2).max(200),
  description: z.string().trim().max(4000).default(""),
  assigneeId: z.union([z.literal(""), z.uuid()]).default(""),
  dueAt: z.union([z.literal(""), z.iso.datetime({ offset: true })]).default(""),
  priority: z.enum(TASK_PRIORITIES).default("normal"),
  relatedType: z.enum(["creator", "campaign", "application", "agency"]).optional(),
  relatedId: z.uuid().optional(),
});
export type TaskInput = z.input<typeof taskInput>;

/** An IST date + time picked in a form ("2026-10-20", "10:30") → ISO UTC. */
export function istToIso(date: string, time = "10:00"): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return "";
  return new Date(`${date}T${time}:00+05:30`).toISOString();
}

// ---------------------------------------------------------------------------------------------------------------
// CSV import
// ---------------------------------------------------------------------------------------------------------------
export const IMPORT_MAX_ROWS = 5000;
export const IMPORT_MAX_BYTES = 2 * 1024 * 1024;

/** Accepted header names (case-insensitive, spaces/underscores ignored) → field. */
const HEADER_ALIASES: Record<string, ImportField> = {
  name: "display_name",
  displayname: "display_name",
  fullname: "display_name",
  handle: "handle",
  username: "handle",
  email: "email",
  emailaddress: "email",
  phone: "phone",
  mobile: "phone",
  whatsapp: "phone",
  city: "city",
  state: "state",
  niches: "niches",
  niche: "niches",
  topics: "niches",
  languages: "languages",
  language: "languages",
  tags: "tags",
  platform: "platform",
  profileurl: "platform_url",
  platformurl: "platform_url",
  url: "platform_url",
  platformhandle: "platform_handle",
  followers: "followers",
  source: "source",
};
export const IMPORT_FIELDS = [
  "display_name",
  "handle",
  "email",
  "phone",
  "city",
  "state",
  "niches",
  "languages",
  "tags",
  "platform",
  "platform_url",
  "platform_handle",
  "followers",
  "source",
] as const;
export type ImportField = (typeof IMPORT_FIELDS)[number];

export function mapHeaders(headers: string[]): {
  map: (ImportField | null)[];
  missing: ImportField[];
} {
  const map = headers.map((h) => HEADER_ALIASES[h.toLowerCase().replace(/[\s_-]+/g, "")] ?? null);
  const missing = (["display_name", "handle"] as const).filter((f) => !map.includes(f));
  return { map, missing };
}

const splitCell = (v: string) =>
  v
    .split(/[;|,]/)
    .map((x) => x.trim())
    .filter(Boolean)
    .slice(0, 20);

export const importRow = z
  .object({
    display_name: z.string().trim().min(1, "name").max(120, "name"),
    handle: z
      .string()
      .trim()
      .transform((v) => v.replace(/^@/, "").toLowerCase())
      .refine((v) => HANDLE_RE.test(v), "handle"),
    email: z
      .string()
      .trim()
      .toLowerCase()
      .refine((v) => v === "" || z.email().safeParse(v).success, "email"),
    phone: z
      .string()
      .trim()
      .refine((v) => v === "" || normalisePhone(v) !== null, "phone")
      .transform((v) => (v ? (normalisePhone(v) ?? "") : "")),
    city: z.string().trim().max(80, "city"),
    state: z.string().trim().max(80, "state"),
    niches: z.string().transform(splitCell),
    languages: z.string().transform(splitCell),
    tags: z.string().transform(splitCell),
    platform: z
      .string()
      .trim()
      .toLowerCase()
      .refine((v) => v === "" || (PLATFORMS as readonly string[]).includes(v), "platform"),
    platform_url: z
      .string()
      .trim()
      .refine((v) => v === "" || /^https:\/\/\S{4,}$/.test(v), "platform_url"),
    platform_handle: z
      .string()
      .trim()
      .transform((v) => v.replace(/^@/, ""))
      .pipe(z.string().max(100, "platform_handle")),
    followers: z
      .string()
      .trim()
      .transform((v) => v.replace(/[,\s]/g, ""))
      .refine((v) => v === "" || /^\d{1,11}$/.test(v), "followers"),
    source: z.string().trim().max(80, "source"),
  })
  .refine((r) => (r.platform === "") === (r.platform_url === ""), {
    message: "platform_pair",
    path: ["platform"],
  });
export type ImportRow = z.output<typeof importRow>;

export interface ImportPrepared {
  valid: (ImportRow & { row: number })[];
  invalid: { row: number; handle: string; result: "error"; reason: string }[];
}

/** Validate parsed CSV rows (row numbers are 1-based file lines, header = 1). */
export function prepareImport(headers: string[], rows: string[][]): ImportPrepared {
  const { map } = mapHeaders(headers);
  const valid: ImportPrepared["valid"] = [];
  const invalid: ImportPrepared["invalid"] = [];
  rows.forEach((cells, i) => {
    const raw = Object.fromEntries(IMPORT_FIELDS.map((f) => [f, ""])) as Record<ImportField, string>;
    map.forEach((field, col) => {
      if (field) raw[field] = cells[col] ?? "";
    });
    const r = importRow.safeParse(raw);
    if (r.success) valid.push({ ...r.data, row: i + 2 });
    else
      invalid.push({
        row: i + 2,
        handle: raw.handle,
        result: "error",
        reason: [...new Set(r.error.issues.map((x) => x.message))].join(","),
      });
  });
  return { valid, invalid };
}

/** Every reason code an import report can carry (zod field codes and database de-duplication codes). */
export const IMPORT_REASON_CODES = [
  "name",
  "handle",
  "email",
  "phone",
  "city",
  "state",
  "platform",
  "platform_url",
  "platform_handle",
  "followers",
  "source",
  "platform_pair",
  "duplicate_in_file_handle",
  "duplicate_in_file_email",
  "duplicate_in_file_phone",
  "existing_handle",
  "existing_email",
  "existing_phone",
  "existing_platform_handle",
] as const;

/** The tabs of a creator's 360 page (staff). */
export const CREATOR_TABS = [
  "overview",
  "profile",
  "kyc",
  "outreach",
  "tasks",
  "deals",
  "links",
  "agencies",
  "history",
] as const;
export type CreatorTab = (typeof CREATOR_TABS)[number];
