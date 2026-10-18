import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { LeadDrawer } from "@/components/leads/lead-drawer";
import type { Db } from "@/lib/contracts/data";
import { Thread } from "./thread";

/** The conversation about one payout, in a drawer opened by ?payout=<id> (earnings pages). */
export async function PayoutThreadDrawer({ db, payoutId }: { db: Db; payoutId: string | undefined }) {
  const id = z.uuid().safeParse(payoutId);
  if (!id.success) return null;
  const t = await getTranslations();
  return (
    <LeadDrawer title={t("messaging.payout.title")} param="payout">
      <Thread db={db} thread={{ type: "payout", entityId: id.data }} description={t("messaging.payout.hint")} />
    </LeadDrawer>
  );
}
