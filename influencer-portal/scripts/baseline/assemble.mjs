// Builds supabase/migrations/00000000000000_shared_baseline.sql from three parts:
//   stubs-before.sql  hand-written shape stubs of other products' objects (LOCAL ONLY)
//   exact.sql         exact production DDL, output of generate-baseline.sql (read-only catalog queries)
//   stubs-after.sql   catalogue views, old CRM helpers and production policies on student_leads
// Usage: node scripts/baseline/assemble.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (f) => fileURLToPath(new URL(f, import.meta.url));
const parts = ["stubs-before.sql", "exact.sql", "stubs-after.sql"].map((f) => readFileSync(here(f), "utf8").trim());

const header = `-- =====================================================================================================================
-- SHARED BASELINE: LOCAL DEVELOPMENT AND CI ONLY. NEVER APPLY TO PRODUCTION OR STAGING.
-- =====================================================================================================================
-- Recreates, in an empty local Supabase, the production objects of other products that the Influencer Portal reads:
-- student_leads, touchpoints, enrollments, Witty's code tables and functions, lead_intake(), the catalogue, the old CRM
-- access rules on student_leads, and shape-compatible stubs of B2B/B2C contract views. Generated on 16 Oct 2026 from
-- production project xlseqwgyjuqhktrguhyc by read-only catalog queries (scripts/baseline/generate-baseline.sql),
-- assembled by scripts/baseline/assemble.mjs. Do not edit by hand: change the parts and re-assemble.
--
-- On production these objects already exist and belong to Witty and the CRMs. The deploy procedure (docs/RUNBOOK.md)
-- marks this version as applied without running it. As a second line of defence the guard below aborts the migration if
-- any of the shared objects already exists, so it can never overwrite them.
-- =====================================================================================================================

do $guard$
begin
  if to_regclass('public.student_leads') is not null or to_regclass('public.w2_access_codes') is not null
     or to_regnamespace('b2b') is not null or to_regnamespace('b2c') is not null then
    raise exception 'shared_baseline is LOCAL ONLY and must never run on a database that already has the shared objects';
  end if;
end
$guard$;

set search_path to public, extensions;
`;

const out = [header, ...parts, "reset search_path;", ""].join("\n\n");
writeFileSync(here("../../supabase/migrations/00000000000000_shared_baseline.sql"), out);
console.info(`wrote shared baseline (${out.length} bytes)`);
