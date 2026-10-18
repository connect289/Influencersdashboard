// Inputs for the content actions (briefs, deliverables, review, go-live, metrics) and the database errors they map to
// message keys. Shared by the forms (client) and the server actions.
import { z } from "zod";
import { CONTENT_FORMATS, PLATFORMS } from "@/lib/creators/schemas";
import { ASCI_CHECKLIST } from "./compliance";
import { briefContent, briefTemplateContent, stageToggles } from "./brief";
import { DUE_STAGES } from "./workflow";

const uuid = z.uuid();
const note = (max: number) => z.string().trim().max(max);
const reason = z.string().trim().min(3).max(1000);

export const briefTemplateInput = z.object({
  id: uuid.nullable().default(null),
  name: z.string().trim().min(2).max(120),
  description: note(500).default(""),
  isDefault: z.boolean().default(false),
  content: briefTemplateContent,
});
export type BriefTemplateInput = z.input<typeof briefTemplateInput>;

export const briefSaveInput = z.object({ briefId: uuid, content: briefContent });
export type BriefSaveInput = z.input<typeof briefSaveInput>;

export const briefPublishInput = z.object({ briefId: uuid, note: note(500).default("") });

export const questionInput = z.object({
  briefId: uuid,
  body: z.string().trim().min(1).max(4000),
  parentId: uuid.nullable().default(null),
});
export type QuestionInput = z.input<typeof questionInput>;

const isoInstant = z.iso.datetime({ offset: true });
export const dueDatesInput = z.partialRecord(z.enum(DUE_STAGES), isoInstant);

export const deliverableNewInput = z.object({
  dealId: uuid,
  title: z.string().trim().min(2).max(120),
  platform: z.enum(PLATFORMS),
  format: z.enum(CONTENT_FORMATS),
  count: z.number().int().min(1).max(20).default(1),
  stages: stageToggles,
  dueDates: dueDatesInput.default({}),
  revisionLimit: z.number().int().min(0).max(20).nullable().default(null),
  configRef: z
    .string()
    .trim()
    .regex(/^[a-z0-9][a-z0-9_-]{0,39}$/)
    .nullable()
    .default(null),
});
export type DeliverableNewInput = z.input<typeof deliverableNewInput>;

export const deliverableEditInput = z.object({
  id: uuid,
  title: z.string().trim().min(2).max(120),
  stages: stageToggles,
  dueDates: dueDatesInput,
  revisionLimit: z.number().int().min(0).max(20),
  configRef: z
    .string()
    .trim()
    .regex(/^[a-z0-9][a-z0-9_-]{0,39}$/)
    .nullable(),
  specs: z.object({
    duration_s: z.number().int().min(1).max(7200).nullable(),
    aspect_ratio: z.string().trim().max(10).nullable(),
    notes: note(500),
  }),
});
export type DeliverableEditInput = z.input<typeof deliverableEditInput>;

export const statusChangeInput = z
  .object({ id: uuid, action: z.enum(["complete", "cancel"]), reason: note(500).default("") })
  .refine((v) => v.action !== "cancel" || v.reason.length >= 3, { path: ["reason"] });

/** A file already uploaded under the deliverable's folder (`<deliverable id>/<uuid>-<name>`). */
export const FILE_PATH_RE = /^[0-9a-f-]{36}\/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$/;
export const UPLOAD_TYPES = [
  "video/mp4",
  "video/quicktime",
  "video/webm",
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
] as const;
export type UploadType = (typeof UPLOAD_TYPES)[number];
export const uploadedFile = z.object({
  path: z.string().regex(FILE_PATH_RE),
  name: z.string().trim().min(1).max(200),
  type: z.enum(UPLOAD_TYPES),
  size: z.number().int().positive(),
});

export const uploadRequest = z.object({
  deliverableId: uuid,
  fileName: z.string().min(1).max(200),
  type: z.enum(UPLOAD_TYPES),
  size: z.number().int().positive(),
});
export type UploadRequest = z.input<typeof uploadRequest>;

export const submissionInput = z
  .object({
    deliverableId: uuid,
    kind: z.enum(["concept", "draft"]),
    body: note(20000).default(""),
    files: z.array(uploadedFile).max(10).default([]),
    linkUrl: z
      .string()
      .trim()
      .max(1000)
      .refine((u) => u === "" || /^https:\/\/[^\s/]+\.[^\s]+$/i.test(u), "https")
      .default(""),
    note: note(2000).default(""),
  })
  .refine((v) => v.body !== "" || v.files.length > 0 || v.linkUrl !== "", {
    path: ["body"],
    message: "empty",
  });
export type SubmissionInput = z.input<typeof submissionInput>;

export const checklistInput = z.object(
  Object.fromEntries(ASCI_CHECKLIST.map((k) => [k, z.boolean()])) as Record<
    (typeof ASCI_CHECKLIST)[number],
    z.ZodBoolean
  >,
);

export const reviewInput = z
  .object({
    submissionId: uuid,
    decision: z.enum(["approve", "changes"]),
    note: note(4000).default(""),
    checklist: checklistInput.nullable().default(null),
  })
  .refine((v) => v.decision !== "changes" || v.note.length >= 3, { path: ["note"] });
export type ReviewInput = z.input<typeof reviewInput>;

export const commentInput = z.object({
  submissionId: uuid,
  body: z.string().trim().min(1).max(4000),
  timestampMs: z.number().int().min(0).max(86_400_000).nullable().default(null),
  region: z
    .object({
      file: z.number().int().min(0).max(9),
      x: z.number().min(0).max(1),
      y: z.number().min(0).max(1),
      w: z.number().min(0).max(1),
      h: z.number().min(0).max(1),
    })
    .nullable()
    .default(null),
  parentId: uuid.nullable().default(null),
});
export type CommentInput = z.input<typeof commentInput>;

export const overrideInput = z.object({ checkId: uuid, reason });
export const extensionInput = z.object({
  deliverableId: uuid,
  reason,
  feePaise: z.number().int().min(0).max(100_000_000_000).default(0),
});
export const decisionInput = z
  .object({ id: uuid, approve: z.boolean(), note: note(1000).default("") })
  .refine((v) => v.approve || v.note.length >= 3, { path: ["note"] });

export const scheduleInput = z.object({ deliverableId: uuid, at: isoInstant });

export const postInput = z.object({
  deliverableId: uuid,
  url: z.string().trim().min(8).max(1000),
  postedOn: z.iso.date(),
});
export type PostInput = z.input<typeof postInput>;

export const verifyInput = z
  .object({
    postId: uuid,
    live: z.boolean(),
    disclosure: z.boolean(),
    matches: z.boolean(),
    note: note(1000).default(""),
  })
  .refine((v) => (v.live && v.disclosure && v.matches) || v.note.length >= 3, { path: ["note"] });
export type VerifyInput = z.input<typeof verifyInput>;

export const METRIC_FIELDS = [
  "views",
  "reach",
  "likes",
  "comments",
  "shares",
  "saves",
  "clicks",
  "watch_time_s",
] as const;
export type MetricField = (typeof METRIC_FIELDS)[number];

const metric = z.number().int().min(0).max(1_000_000_000_000).nullable().default(null);
export const metricsInput = z
  .object({
    deliverableId: uuid,
    checkpoint: z.string().regex(/^([0-9]{1,4}h|adhoc)$/),
    views: metric,
    reach: metric,
    likes: metric,
    comments: metric,
    shares: metric,
    saves: metric,
    clicks: metric,
    watch_time_s: metric,
    screenshots: z.array(z.string().regex(FILE_PATH_RE)).max(5).default([]),
  })
  .refine(
    (v) => [v.views, v.reach, v.likes, v.comments, v.shares, v.saves, v.clicks, v.watch_time_s].some((x) => x !== null),
    {
      path: ["views"],
      message: "empty",
    },
  );
export type MetricsInput = z.input<typeof metricsInput>;

export const bannedClaimInput = z.object({
  id: uuid.nullable().default(null),
  pattern: z.string().trim().min(2).max(200),
  kind: z.enum(["phrase", "regex"]),
  severity: z.enum(["block", "warn"]),
  note: note(300).default(""),
  active: z.boolean().default(true),
});
export type BannedClaimInput = z.input<typeof bannedClaimInput>;

/** Database messages → content.errors.* keys (first match wins). */
export const CONTENT_DB_ERRORS: readonly [RegExp, string][] = [
  [/already has a brief/, "briefExists"],
  [/brief is empty/, "briefEmpty"],
  [/nothing changed since the last version/, "briefUnchanged"],
  [/newer version of the brief/, "briefNewer"],
  [/deal is closed/, "dealClosed"],
  [/stages can only change before work starts/, "stagesLocked"],
  [/this deliverable is closed/, "deliverableClosed"],
  [/^cannot /, "notNow"],
  [/add text, a file or a link/, "submissionEmpty"],
  [/invalid file/, "invalidFile"],
  [/already been reviewed/, "alreadyReviewed"],
  [/compliance scan has not run/, "scanPending"],
  [/compliance checks failed/, "checksFailed"],
  [/ASCI checklist/, "checklist"],
  [/say what should change/, "changesNote"],
  [/revision limit is reached/, "revisionLimit"],
  [/already waiting for approval/, "extensionPending"],
  [/already been decided/, "alreadyDecided"],
  [/nothing to override/, "nothingToOverride"],
  [/posting date can't be in the future/, "futureDate"],
  [/already been checked/, "alreadyChecked"],
  [/say what is wrong/, "verifyNote"],
  [/submit the live link first/, "liveFirst"],
  [/choose a future date/, "futureSchedule"],
  [/template with this name exists/, "templateName"],
  [/pattern is already in the list/, "claimExists"],
  [/a reason is required/, "reasonRequired"],
  [/invalid region/, "invalidRegion"],
];
