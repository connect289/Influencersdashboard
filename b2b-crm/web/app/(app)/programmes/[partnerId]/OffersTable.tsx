"use client";
import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { commissionText, inr } from "@/lib/programmes";
import type { Offer } from "@/lib/programmes-data";

/** The partner's live programmes, filtered as you type (a partner file has at most a few thousand rows). */
export function OffersTable({ offers }: { offers: Offer[] }) {
  const [q, setQ] = useState("");
  const [uni, setUni] = useState("");
  const universities = useMemo(() => [...new Set(offers.map((o) => o.university))].sort(), [offers]);
  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return offers.filter((o) => (!uni || o.university === uni)
      && (!s || [o.program_name, o.specialization, o.course, o.partner_course_code ?? "", o.partner_programme_name ?? ""].some((v) => v.toLowerCase().includes(s))));
  }, [offers, q, uni]);

  return (
    <>
      <div className="flex flex-wrap items-center gap-3 border-b border-border px-4 py-3">
        <div className="relative min-w-0 flex-1 basis-56 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" aria-hidden />
          <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Programme, specialization or code" aria-label="Search live programmes"
            className="h-9 w-full rounded-lg border border-border bg-surface pl-9 pr-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30" />
        </div>
        {universities.length > 1 && (
          <select value={uni} onChange={(e) => setUni(e.target.value)} aria-label="University"
            className="h-9 rounded-lg border border-border bg-surface px-2.5 text-[13px] text-fg focus:border-ring focus:outline-none">
            <option value="">All universities</option>
            {universities.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
        )}
        <p className="ml-auto text-[12.5px] text-muted"><span className="tabular font-medium text-fg">{shown.length}</span> of {offers.length}</p>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[860px] text-left text-[13px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="px-4 py-2.5 font-medium">Programme</th>
              <th scope="col" className="px-3 py-2.5 font-medium">University</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Mode</th>
              <th scope="col" className="px-3 py-2.5 font-medium">Partner code</th>
              <th scope="col" className="px-3 py-2.5 text-right font-medium">Partner fee</th>
              <th scope="col" className="px-3 py-2.5 text-right font-medium">Catalogue fee</th>
              <th scope="col" className="px-4 py-2.5 text-right font-medium">Commission</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {shown.map((o) => (
              <tr key={o.offer_id}>
                <td className="max-w-[320px] px-4 py-2.5">
                  <span className="block truncate font-medium text-fg">{o.course} · {o.specialization}</span>
                  {o.partner_programme_name && <span className="block truncate text-[12px] text-subtle">{o.partner_programme_name}</span>}
                </td>
                <td className="px-3 py-2.5 text-muted">{o.university_short || o.university}</td>
                <td className="px-3 py-2.5 text-muted">{o.mode}</td>
                <td className="px-3 py-2.5 font-mono text-[12px] text-muted">{o.partner_course_code ?? "—"}</td>
                <td className="tabular px-3 py-2.5 text-right text-fg">{inr(o.fees?.total)}</td>
                <td className="tabular px-3 py-2.5 text-right text-muted">{inr(o.fee_total)}</td>
                <td className="tabular px-4 py-2.5 text-right text-fg">{commissionText(o.commission)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
