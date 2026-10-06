import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { Commission, Template } from "@/lib/programmes";

/** Programme Repository reads as the signed-in Admin; every b2b.programme* function re-checks b2b.is_admin(). */

export type ProgrammeLabel = {
  id: number;
  program_name: string;
  university: string;
  university_short: string | null;
  course: string;
  course_key: string;
  specialization: string;
  level: string;
  mode: string;
  fee_total: number | null;
  fee_yearly: number | null;
  active: boolean;
};

export type Overview = {
  stale_days: number;
  requests: number;
  partners: {
    id: number; name: string; display_name: string | null; logo_url: string | null; brand_color: string | null; status: string;
    source: string | null; live_count: number;
    published: { id: number; version_no: number; published_at: string; file_name: string | null } | null;
    draft: { id: number; version_no: number; uploaded_at: string; review: number } | null;
    last_upload_at: string | null; stale: boolean;
  }[];
  coverage: { course_key: string; course: string; programmes: number; covered: number; single: number; competing: number }[];
};

export type VersionSummary = {
  id: number; version_no: number; status: string; file_name: string | null; sheet: string | null; has_file: boolean; row_count: number;
  uploaded_at: string; published_at: string | null; note: string | null; counts: Record<string, number> | null;
};

export type Offer = ProgrammeLabel & {
  offer_id: number; partner_course_code: string | null; partner_programme_name: string | null;
  fees: Record<string, number>; eligibility: { min_qualification?: string; min_pct?: number }; commission: Commission | null;
  season_from: string | null; season_to: string | null; valid_from: string;
};

export type PartnerRepo = {
  partner: { id: number; name: string; display_name: string | null; logo_url: string | null; brand_color: string | null; status: string };
  source: {
    type: "upload" | "gsheet"; column_template: Template; last_changed_at: string | null; last_checked_at: string | null;
    sheet_id: string | null; tab: string | null; sync_every_hours: number; last_error: string | null; content_hash: string | null;
  } | null;
  versions: VersionSummary[];
  offers: Offer[];
};

export type VersionRow = {
  id: number; row_no: number; review_status: string; match_method: string | null; confidence: number | null; ignore_reason: string | null;
  norm: {
    university: string; course: string; specialization: string; mode: string | null; level: string | null; programme_name: string | null;
    programme_code: string | null; fees: Record<string, number>; commission: Commission | null; errors?: string[];
  };
  programme: ProgrammeLabel | null;
  candidates: (ProgrammeLabel & { score: number })[];
  requested: boolean;
};

export type Version = VersionSummary & { partner_id: number; file_path: string | null; rows: VersionRow[] };

export type Preview = {
  version: { id: number; version_no: number; status: string; partner_id: number };
  pending_review: number; ignored: number; duplicates: number; live_count: number; new_count: number; unchanged: number; proposed_commission: number;
  added: (ProgrammeLabel & { fees: Record<string, number>; commission: Commission | null; fee_gap: number | null })[];
  removed: (ProgrammeLabel & { last_partner: boolean })[];
  changed: (ProgrammeLabel & { fields: string[]; old_fees: Record<string, number>; new_fees: Record<string, number>;
    old_commission: Commission | null; new_commission: Commission | null; fee_gap: number | null })[];
};

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const programmesOverview = () => rpc<Overview>("programmes_overview");
export const partnerRepo = cache((id: number) => rpc<PartnerRepo | null>("programme_partner", { p_partner_id: id }));
export const programmeVersion = cache((id: number) => rpc<Version | null>("programme_version", { p_version_id: id }));
export const versionPreview = (id: number) => rpc<Preview | null>("programme_version_preview", { p_version_id: id });
export const catalogueUniversities = () => rpc<{ id: number; name: string; short_name: string | null }[]>("catalogue_universities");
