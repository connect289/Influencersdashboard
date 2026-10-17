"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Check, Link2, MessageCircle, Sparkles, X } from "lucide-react";
import { toast } from "sonner";
import { whatsappLink } from "@/content/site";
import { saved } from "@/lib/client/saved-store";
import { bestIndex, compareRows } from "@/lib/finder/compare";
import type { OfferingDetails } from "@/lib/search/types";
import { cn } from "@/lib/utils";
import { UniversityMark } from "./UniversityMark";

/**
 * Side-by-side comparison of up to 4 offerings (spec 6.5): differences highlighted, identical rows can be hidden, the
 * selection lives in the URL so it can be shared; "Discuss with Witty" and "Talk to a counsellor".
 */
export function CompareTable({ items, advisorEnabled, whatsapp }: { items: OfferingDetails[]; advisorEnabled: boolean; whatsapp: string }) {
  const router = useRouter();
  const [hideSame, setHideSame] = useState(false);
  const rows = compareRows(items);
  const visible = hideSame ? rows.filter((r) => !r.identical) : rows;
  const sections = [...new Set(visible.map((r) => r.section))];

  // Keep the local compare selection in step with a shared link.
  useEffect(() => saved.set("compare", items.map((i) => i.id)), [items]);

  const remove = (id: number) => {
    const ids = items.map((i) => i.id).filter((x) => x !== id);
    saved.set("compare", ids);
    router.replace(ids.length ? `/compare?ids=${ids.join(",")}` : "/compare", { scroll: false });
  };
  const summary = items.map((i) => `${i.programme_name} ${i.spec_name} (${i.university.name})`).join(" vs ");

  return (
    <div className="grid gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="text-muted flex items-center gap-2 text-sm">
          <input type="checkbox" className="accent-[var(--primary)] size-4" checked={hideSame} onChange={() => setHideSame((v) => !v)} />
          Hide rows that are the same
        </label>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(window.location.href);
                toast("Link copied");
              } catch {
                toast("Copy the address from your browser to share");
              }
            }}
            className="border-border bg-surface text-text hover:bg-surface-hover inline-flex h-10 items-center gap-2 rounded-full border px-4 text-sm"
          >
            <Link2 className="size-4" aria-hidden /> Share comparison
          </button>
          {advisorEnabled ? (
            <Link href={`/witty?q=${encodeURIComponent(`Help me choose: ${summary}`)}`} className="bg-primary text-on-primary inline-flex h-10 items-center gap-2 rounded-full px-4 text-sm font-semibold">
              <Sparkles className="size-4" aria-hidden /> Discuss with Witty
            </Link>
          ) : null}
          <a href={whatsappLink(whatsapp, `Hi Eduwit, please help me compare: ${summary}`)} target="_blank" rel="noopener noreferrer" className={cn("inline-flex h-10 items-center gap-2 rounded-full px-4 text-sm font-semibold", advisorEnabled ? "border-border bg-surface text-text border" : "bg-primary text-on-primary")}>
            <MessageCircle className="size-4" aria-hidden /> Talk to a counsellor
          </a>
        </div>
      </div>

      <div className="glass overflow-x-auto rounded-[var(--radius-xl)]" role="region" aria-label="Comparison table" tabIndex={0}>
        <table className="w-full min-w-[640px] border-collapse text-sm">
          <caption className="sr-only">Comparison of {items.length} programmes</caption>
          <thead>
            <tr>
              <th scope="col" className="w-40 p-4 text-left align-bottom">
                <span className="sr-only">Detail</span>
              </th>
              {items.map((o) => (
                <th key={o.id} scope="col" className="border-border border-l p-4 text-left align-top font-normal">
                  <div className="flex items-start justify-between gap-2">
                    <UniversityMark name={o.university.name} short={o.university.short} logo={o.university.logo} size={36} />
                    <button type="button" onClick={() => remove(o.id)} className="text-muted hover:bg-surface-hover grid size-8 place-items-center rounded-full" aria-label={`Remove ${o.university.name} from comparison`}>
                      <X className="size-4" aria-hidden />
                    </button>
                  </div>
                  <p className="text-text mt-2 font-semibold">{o.programme_name} · {o.spec_name}</p>
                  <p className="text-muted">{o.university.name}</p>
                  <Link href={`/programmes?offering=${o.id}`} className="text-accent mt-1 inline-block text-xs font-medium hover:underline">
                    View details
                  </Link>
                </th>
              ))}
            </tr>
          </thead>
          {sections.map((s) => (
            <tbody key={s}>
              <tr>
                <th scope="colgroup" colSpan={items.length + 1} className="eyebrow border-border border-t px-4 pt-4 pb-1 text-left">
                  {s}
                </th>
              </tr>
              {visible.filter((r) => r.section === s).map((r) => {
                const best = bestIndex(r);
                return (
                  <tr key={r.key} className={cn(!r.identical && "bg-[color-mix(in_oklab,var(--primary)_4%,transparent)]")}>
                    <th scope="row" className="text-muted px-4 py-2.5 text-left font-normal">{r.label}</th>
                    {r.values.map((v, i) => (
                      <td key={i} className={cn("border-border tabular border-l px-4 py-2.5", v === null ? "text-subtle" : "text-text")}>
                        {v ?? "—"}
                        {best === i ? (
                          <span className="text-success ml-1.5 inline-flex items-center text-xs font-medium">
                            <Check className="size-3.5" aria-hidden />
                            <span className="sr-only">best in this row</span>
                          </span>
                        ) : null}
                      </td>
                    ))}
                  </tr>
                );
              })}
            </tbody>
          ))}
        </table>
      </div>
      <p className="text-subtle text-xs">Rows with no information for any programme are left out. Fees are set by universities and may change; confirm with your counsellor.</p>
    </div>
  );
}
