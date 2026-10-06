import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { NotificationsOverview } from "@/lib/notifications";

/** Notification reads as the signed-in Admin; b2b.notifications_overview re-checks b2b.is_admin(), masks recipients and never returns secrets. */
export async function notificationsOverview(): Promise<NotificationsOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("notifications_overview");
  if (error) throw new Error(`notifications_overview failed (${error.code ?? "unknown"})`);
  return data as NotificationsOverview;
}
