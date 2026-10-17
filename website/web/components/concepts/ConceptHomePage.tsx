import { ConceptFrame, type ConceptId } from "./ConceptFrame";
import { HeroA, HeroB } from "./Heroes";
import { HomeSections } from "./HomeSections";
import { conceptGroups, conceptStats, conceptUniversities } from "@/lib/seed/stats";

export function ConceptHomePage({ c }: { c: ConceptId }) {
  return (
    <ConceptFrame concept={c} active="home">
      <main id="main">
        {c === "a" ? <HeroA stats={conceptStats} /> : <HeroB stats={conceptStats} />}
        <HomeSections concept={c} groups={conceptGroups} universities={conceptUniversities} />
      </main>
    </ConceptFrame>
  );
}
