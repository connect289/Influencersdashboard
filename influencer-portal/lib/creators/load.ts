import "server-only";
import type {
  ContactRow,
  CreatorRow,
  KycView,
  PlatformRow,
  PortfolioRow,
  RateCardRow,
} from "@/components/creator-profile/types";
import type { ServerSupabase } from "@/lib/supabase/server";

export interface CreatorProfileData {
  creator: CreatorRow;
  platforms: PlatformRow[];
  rates: RateCardRow[];
  portfolio: PortfolioRow[];
  contacts: ContactRow[];
}

/** Everything on the profile screens, in parallel. Null when the creator isn't visible to the caller. */
export async function loadCreatorProfile(
  supabase: ServerSupabase,
  creatorId: string,
): Promise<{ data: CreatorProfileData | null; error: boolean }> {
  const [creator, platforms, rates, portfolio, contacts] = await Promise.all([
    supabase.from("creators").select("*").eq("id", creatorId).maybeSingle(),
    supabase.from("creator_platforms").select("*").eq("creator_id", creatorId).order("created_at"),
    supabase
      .from("creator_rate_cards")
      .select("*")
      .eq("creator_id", creatorId)
      .order("platform")
      .order("format"),
    supabase.from("creator_portfolio").select("*").eq("creator_id", creatorId).order("position"),
    supabase
      .from("creator_contacts")
      .select("id, kind, label, phone_last2, created_at")
      .eq("creator_id", creatorId)
      .order("created_at"),
  ]);
  const error = [creator, platforms, rates, portfolio, contacts].some((r) => r.error);
  if (error || !creator.data) return { data: null, error };
  return {
    data: {
      creator: creator.data,
      platforms: platforms.data ?? [],
      rates: rates.data ?? [],
      portfolio: portfolio.data ?? [],
      contacts: contacts.data ?? [],
    },
    error: false,
  };
}

export async function loadKyc(
  supabase: ServerSupabase,
  creatorId: string,
): Promise<KycView | null> {
  const { data, error } = await supabase.rpc("kyc_view", { p_creator: creatorId });
  if (error) return null;
  return data as unknown as KycView;
}
