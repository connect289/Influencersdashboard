import { ConceptFrame, type ConceptId } from "./ConceptFrame";
import { FinderDemo } from "@/components/finder/FinderDemo";
import { seedOfferings } from "@/lib/seed/concept";

export function ConceptFinderPage({ c }: { c: ConceptId }) {
  return (
    <ConceptFrame concept={c} active="finder">
      <main id="main" className="container-site grid gap-8 py-10">
        <header className="grid gap-2">
          <p className="eyebrow">Programme finder</p>
          <h1 className="text-display text-[length:var(--text-4xl)] font-semibold">Find your programme</h1>
          <p className="text-muted max-w-2xl">
            Every fee, approval and eligibility rule here comes from the catalogue. Missing details are left out, never
            guessed.
          </p>
        </header>
        <FinderDemo offerings={seedOfferings} variant={c} />
      </main>
    </ConceptFrame>
  );
}
