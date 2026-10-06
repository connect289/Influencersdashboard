import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime } from "@/lib/format";
import { ALLOCATION_LABEL, fromStored } from "@/lib/routing";
import { routingDecision } from "@/lib/routing-data";
import { DecisionView } from "../../DecisionView";

export const metadata: Metadata = { title: "Routing decision" };

type Props = { params: Promise<{ id: string }> };
const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

/** One stored routing decision: what the engine saw and why it chose as it did. */
export default async function DecisionPage({ params }: Props) {
  await requireAdmin();
  const id = parseId((await params).id);
  if (!id) notFound();
  const s = await routingDecision(id);
  if (!s) notFound();

  return (
    <>
      <Link href="/routing" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Routing</Link>
      <div className="mb-5 flex flex-wrap items-center gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-xl font-semibold tracking-tight text-fg">Decision #{s.id} · {s.lead_name || `Lead #${s.lead_id}`}</h1>
          <p className="text-[13px] text-muted">
            {formatDateTime(s.created_at)} · by {s.actor_type === "engine" ? "the engine (automatic)" : "an Admin"}
            {s.settings_version !== null && <> · engine settings v{s.settings_version}</>}
            {s.allocation && <> · allocation <span className="font-mono">{s.allocation.reference}</span>: {ALLOCATION_LABEL[s.allocation.status] ?? s.allocation.status}</>}
          </p>
        </div>
        <Link href={`/leads?lead=${s.lead_id}`} className={buttonClass("secondary", "sm")}>Open the lead</Link>
      </div>
      <Card className="min-w-0 p-5">
        <DecisionView d={fromStored(s)} />
      </Card>
    </>
  );
}
