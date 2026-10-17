import "server-only";
import { z } from "zod";
import { istToday } from "@/lib/format";
import { log } from "@/lib/log";
import { runScorecard } from "@/lib/scorecards/data";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ period: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/) });

/**
 * Monthly scorecards (pg_cron `inf-scorecards` on the 1st for the month just ended): one card per approved creator,
 * applying tier changes. Idempotent: creators who already have the month's card are skipped, so a failed run resumes.
 */
export const scorecardsRun: JobHandler = async (job) => {
  const { period } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const { data, error } = await db.rpc("scorecards_due", { p_period: period });
  if (error) throw new Error(error.message);
  const today = istToday();
  let done = 0;
  for (const creatorId of z.array(z.uuid()).parse(data)) {
    await runScorecard({ db, creatorId, period, kind: "monthly", today });
    done += 1;
  }
  log.info("scorecards.run", { period, done });
};
