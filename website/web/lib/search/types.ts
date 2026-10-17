/** Shapes returned by the web_* search functions (docs/SCHEMA_PLAN.md §3). Kept in one place for the finder and Witty. */

export type Eligibility = "eligible" | "check" | "not_eligible";

export interface UniversityRef {
  id?: number;
  slug: string;
  name: string;
  short?: string;
  logo?: string;
  type?: string;
  naac_grade?: string;
}

export interface OfferingCard {
  id: number;
  program_key?: string;
  group_key: string;
  programme_id: string;
  programme_name: string;
  level_id: string;
  level_short: string;
  spec_ids: string[];
  spec_name: string;
  spec_display?: string;
  university: UniversityRef;
  mode?: string;
  format?: string;
  attributes?: Record<string, string | boolean>;
  fee: { total?: number; yearly?: number; semester?: number; on_request?: boolean };
  duration_months?: number;
  naac_grade?: string;
  naac_accredited?: boolean;
  nirf_rank?: number;
  nirf_year?: number;
  ugc_deb?: "entitled" | "approved" | "recognised" | "stated";
  aicte?: boolean;
  min_qualification?: string;
  min_pct_general?: number;
  work_exp_years?: number;
  entrance_exam?: boolean;
  eligibility?: Eligibility;
  verified_at?: string;
}

export interface NirfStatement {
  rank?: number;
  band?: string;
  year?: number;
  category?: string;
  discipline?: string;
  statement: string;
}

export interface UniversityFacts {
  ugc_deb?: "entitled" | "approved" | "recognised" | "stated";
  ugc_deb_statement?: string;
  naac_grade?: string;
  naac_accredited?: boolean;
  naac_statement?: string;
  aicte?: boolean;
  nirf?: NirfStatement;
  nirf_programmes?: NirfStatement[];
}

export interface OfferingDetails extends OfferingCard {
  moved_from?: number;
  programme_full: string;
  level_label: string;
  category_id: string;
  category_label: string;
  program_name: string;
  fee_exam?: number;
  fee_registration?: number;
  emi_amount?: number;
  fee_lines?: { label: string; amount: number }[];
  duration_source?: "eligibility_text" | "fee_schedule";
  min_pct_reserved?: number;
  eligibility_text?: string;
  brochure_url?: string;
  university_facts?: UniversityFacts;
  alternatives?: OfferingCard[];
}

export interface ProgrammeGroup {
  key: string;
  programme_id: string;
  programme_name: string;
  programme_full: string;
  level_id: string;
  level_short: string;
  level_label: string;
  category_id: string;
  spec_ids: string[];
  spec_name: string;
  offerings: number;
  universities: number;
  fee_min?: number;
  fee_max?: number;
  duration_min?: number;
  duration_max?: number;
  best_naac?: string;
  modes: string[];
  some_fee_on_request?: boolean;
  eligibility?: Record<Eligibility, number>;
  top_universities?: UniversityRef[];
  items?: OfferingCard[];
}

export interface FacetOption {
  value: string;
  label: string;
  count: number;
  full?: string;
  level?: string;
}

export interface Facets {
  level: FacetOption[];
  category: FacetOption[];
  programme: FacetOption[];
  spec: FacetOption[];
  university: FacetOption[];
  mode: FacetOption[];
  naac: FacetOption[];
  min_q: FacetOption[];
  state: FacetOption[];
  duration: FacetOption[];
  format: FacetOption[];
  goal: FacetOption[];
  fee: { min: number | null; max: number | null; on_request: number };
  ugc_deb: number;
  aicte: number;
  nirf: number;
  work_exp: { required: number; not_required: number };
  entrance: { yes: number; no: number };
  eligibility?: Record<Eligibility, number>;
}

export interface Resolved {
  programme: string[];
  specialisation: string[];
  university: string[];
  level: string[];
  category: string[];
  mode: string[];
  corrected: { from: string; to: string }[];
  used_words: string[];
  ignored_words: string[];
}

export interface SearchResult {
  total: number;
  total_groups: number;
  page: number;
  page_size: number;
  view: "grouped" | "flat";
  sort: string;
  items: ProgrammeGroup[] | OfferingCard[];
  facets: Facets;
  relaxations: { filter: string; count: number }[];
  resolved: Resolved;
  without_query?: number;
  closest?: OfferingCard[];
}

export interface Suggestions {
  programmes: { id: string; label: string; full: string; level: string; count: number; universities: number }[];
  groups: { key: string; programme_id: string; spec_ids: string[]; label: string; count: number; universities: number }[];
  universities: { slug: string; label: string; count: number }[];
  guides?: { slug: string; title: string }[];
}

export interface CatalogStats {
  universities: number;
  offerings: number;
  programmes: number;
  groups: number;
  universities_ugc_deb: number;
  universities_naac_a_plus: number;
  all_ugc_deb: boolean;
  fee_min: number | null;
  verified_at: string | null;
  refreshed_at: string | null;
}

export interface UniversitySummary {
  slug: string;
  name: string;
  short?: string;
  type?: string;
  logo?: string;
  state?: string;
  naac_grade?: string;
  nirf_rank?: number;
  ugc_deb?: string;
  aicte?: boolean;
  offerings: number;
  programmes: number;
  fee_min?: number;
  fee_max?: number;
  modes: string[];
  verified_at?: string;
}

export interface UniversityDetails {
  slug: string;
  name: string;
  catalogue_name: string;
  short?: string;
  type?: string;
  logo?: string;
  state?: string;
  city?: string;
  website_url?: string;
  about?: string;
  facts: UniversityFacts;
  offerings: number;
  programmes: string[];
  verified_at: string;
}
