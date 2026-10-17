import data from "@/content/seed/concept-offerings.json";
import { groupOfferings, seedOfferings } from "./concept";

const meta = (data as { _meta: { universities: number; programmes: number } })._meta;

/** Live-from-catalogue numbers for the concept trust line (Phase 3 replaces with web_catalog_stats()). */
export const conceptStats = { universities: meta.universities, programmes: meta.programmes, allDeb: false };
export const conceptGroups = groupOfferings(seedOfferings);
export const conceptUniversities = [...new Set(seedOfferings.map((o) => o.university))].sort();
