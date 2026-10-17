"use client";

import dynamic from "next/dynamic";
import { Suspense } from "react";
import { setOfferingParam } from "@/lib/client/use-finder";
import type { FinderParams } from "@/lib/search/state";
import type { ProgrammeGroup } from "@/lib/search/types";
import { CompareTray } from "./CompareTray";
import { PanelHost } from "./PanelHost";
import { ResultGroup } from "./ResultGroup";

const ApplicationForm = dynamic(() => import("@/components/forms/ApplicationForm").then((m) => m.ApplicationForm), {
  ssr: false,
  loading: () => <p className="text-muted text-sm">Loading the form…</p>,
});

/** A university's programmes in the finder's results format, each opening the same detail panel (spec 6.6). */
export function UniversityProgrammes({ groups, params, slug, name, whatsapp, advisorEnabled, goals }: {
  groups: ProgrammeGroup[];
  params: FinderParams;
  slug: string;
  name: string;
  whatsapp: string;
  advisorEnabled: boolean;
  goals: { value: string; label: string }[];
}) {
  const programmes = groups.flatMap((g) =>
    (g.items ?? []).map((o) => ({
      offeringId: o.id,
      label: `${o.programme_name} · ${o.spec_name}${o.mode === "ODL" ? " (Distance)" : ""}`,
      level: o.level_id,
      minQualification: o.min_qualification,
    })),
  );
  return (
    <>
      <div className="grid gap-4">
        {groups.map((g) => (
          <ResultGroup key={g.key} g={g} params={params} singleUniversity onOpen={(o) => setOfferingParam(o.id, "push")} />
        ))}
      </div>
      <section id="apply" aria-labelledby="apply-u" className="glass mt-10 grid max-w-2xl scroll-mt-24 gap-3 rounded-[var(--radius-2xl)] p-5 sm:p-6">
        <h2 id="apply-u" className="font-display text-text text-2xl font-semibold">Apply to {name}</h2>
        <p className="text-muted text-sm">Choose a programme and share your details; a counsellor checks your eligibility and helps you apply.</p>
        <ApplicationForm target={{ kind: "university", universitySlug: slug, universityName: name, programmes }} goals={goals} whatsapp={whatsapp} />
      </section>
      <CompareTray />
      <Suspense>
        <PanelHost advisorEnabled={advisorEnabled} whatsapp={whatsapp} goals={goals} />
      </Suspense>
    </>
  );
}
