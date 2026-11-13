import "server-only";
import { z } from "zod";
import { istToday } from "@/lib/format";
import { log } from "@/lib/log";
import { runScorecard } from "@/lib/scorecards/data";
import { adminClient } from "@/lib/supabase/admin";
import { enqueueMany } from "./fan-out";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ period: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/) });

/**
 * Monthly scorecards (pg_cron `inf-scorecards` on the 1st for the month just ended): one scorecards.creator job per
 * approved creator without the month's card, each a short job of its own.
 */
export const scorecardsRun: JobHandler = async (job) => {
  const { period } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const { data, error } = await db.rpc("scorecards_due", { p_period: period });
  if (error) throw new Error(error.message);
  const queued = await enqueueMany(
    db,
    z
      .array(z.uuid())
      .parse(data)
      .map((creatorId) => ({
        kind: "scorecards.creator",
        payload: { period, creator_id: creatorId },
        idemKey: `scorecard:${period}:${creatorId}`,
      })),
  );
  log.info("scorecards.queued", { period, queued });
};

/** One creator's monthly card, applying a tier change. Idempotent: inf.scorecard_save keeps the first card. */
export const scorecardsCreator: JobHandler = async (job) => {
  const { period, creator_id } = payloadSchema.extend({ creator_id: z.uuid() }).parse(job.payload);
  await runScorecard({ db: adminClient(), creatorId: creator_id, period, kind: "monthly", today: istToday() });
};
