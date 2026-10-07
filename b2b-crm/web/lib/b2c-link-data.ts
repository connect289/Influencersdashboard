import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { LinkOverview } from "@/lib/b2c-link";

/** The B2C CRM link screen reads as the signed-in Admin; b2b.b2c_link_overview re-checks b2b.is_admin(). */
export async function b2cLinkOverview(): Promise<LinkOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("b2c_link_overview");
  if (error) throw new Error(`b2c_link_overview failed (${error.code ?? "unknown"})`);
  return data as LinkOverview;
}
