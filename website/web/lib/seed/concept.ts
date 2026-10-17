import data from "@/content/seed/concept-offerings.json";

/** Phase 1 concept seed (subset of the real catalogue). Replaced by the read model (Phase 3). */
export interface SeedOffering {
  id: number;
  programme: string;
  programmeKey: string;
  specialisation: string;
  level: string;
  university: string;
  universityShort: string;
  universityId: number;
  mode: string;
  feeTotal: number;
  feeYearly: number | null;
  feeSemester: number | null;
  emi: boolean;
  durationYears: number | null;
  naac: string | null;
  ugcDeb: boolean;
  aicte: boolean;
  minQualification: string;
  minPct: number | null;
  verifiedAt: string;
}

export interface SeedGroup {
  key: string;
  programme: string;
  specialisation: string;
  level: string;
  offerings: SeedOffering[];
  feeMin: number;
  feeMax: number;
  bestNaac: string | null;
  universities: string[];
}

const NAAC_ORDER = ["B", "B+", "B++", "A", "A+", "A++"];

export const seedOfferings = (data as { offerings: SeedOffering[] }).offerings;

export function groupOfferings(list: SeedOffering[]): SeedGroup[] {
  const map = new Map<string, SeedOffering[]>();
  for (const o of list) {
    const k = `${o.programmeKey}|${o.specialisation}`;
    map.set(k, [...(map.get(k) ?? []), o]);
  }
  return [...map.entries()]
    .map(([key, offerings]) => {
      const fees = offerings.map((o) => o.feeTotal);
      const best =
        offerings
          .map((o) => o.naac)
          .filter((g): g is string => !!g)
          .sort((a, b) => NAAC_ORDER.indexOf(b) - NAAC_ORDER.indexOf(a))[0] ?? null;
      const first = offerings[0]!;
      return {
        key,
        programme: first.programme,
        specialisation: first.specialisation,
        level: first.level,
        offerings,
        feeMin: Math.min(...fees),
        feeMax: Math.max(...fees),
        bestNaac: best,
        universities: [...new Set(offerings.map((o) => o.universityShort))],
      };
    })
    .sort((a, b) => b.offerings.length - a.offerings.length);
}
