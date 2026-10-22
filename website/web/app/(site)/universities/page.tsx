import type { Metadata } from "next";
import Link from "next/link";
import { BadgeCheck } from "lucide-react";
import { UniversityMark } from "@/components/finder/UniversityMark";
import { formatInrRange } from "@/lib/format";
import { UGC_LABEL } from "@/lib/search/labels";
import { universities } from "@/lib/server/search";
import { withOverrides } from "@/lib/server/page-meta";

const META: Metadata = {
  title: "Universities",
  description: "Universities offering online, distance and on-campus programmes: UGC-DEB status, NAAC grade, NIRF rank, programmes and fees.",
  alternates: { canonical: "/universities" },
};

export async function generateMetadata(): Promise<Metadata> {
  return withOverrides("/universities", META);
}

/** University directory (spec 4): university-level facts from the catalogue, each linking to its profile. */
export default async function UniversitiesPage() {
  const list = await universities();
  return (
    <main id="main" className="container-site grid gap-8 pt-8 pb-28 lg:pb-16">
      <header className="max-w-3xl">
        <p className="eyebrow">Universities</p>
        <h1 className="font-display text-text mt-1 text-3xl font-semibold sm:text-4xl">Universities</h1>
        <p className="text-muted mt-3">
          {list.length} universities offering online, distance and on-campus programmes through Eduwit. Approvals, NAAC grades and NIRF ranks are shown only where the university states them.
        </p>
      </header>
      <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {list.map((u) => (
          <li key={u.slug}>
            <Link href={`/universities/${u.slug}`} className="glass hover:border-border-strong grid h-full gap-3 rounded-[var(--radius-xl)] border border-transparent p-5 transition-colors">
              <div className="flex items-start gap-3">
                <UniversityMark name={u.name} short={u.short} logo={u.logo} size={44} />
                <div className="min-w-0">
                  <h2 className="font-display text-text text-lg leading-snug font-semibold">{u.name}</h2>
                  {u.type ? <p className="text-subtle text-xs">{u.type}</p> : null}
                </div>
              </div>
              <div className="flex flex-wrap gap-1.5 text-xs">
                {u.ugc_deb ? <span className="bg-accent-soft text-accent rounded-full px-2 py-0.5 font-semibold">{UGC_LABEL[u.ugc_deb]}</span> : null}
                {u.naac_grade ? (
                  <span className="bg-success-soft text-success inline-flex items-center gap-1 rounded-full px-2 py-0.5 font-semibold">
                    <BadgeCheck className="size-3.5" aria-hidden /> NAAC {u.naac_grade}
                  </span>
                ) : null}
                {u.nirf_rank ? <span className="bg-surface text-muted rounded-full px-2 py-0.5 font-semibold">NIRF #{u.nirf_rank}</span> : null}
                {u.aicte ? <span className="bg-surface text-muted rounded-full px-2 py-0.5 font-semibold">AICTE</span> : null}
              </div>
              <p className="text-muted text-sm">
                {u.programmes} {u.programmes === 1 ? "programme" : "programmes"} · {u.offerings} options
                {u.fee_min && u.fee_max ? ` · ${formatInrRange(u.fee_min, u.fee_max)}` : ""}
              </p>
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}
