import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, CircleCheck, CircleDashed } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { COVERAGE_GROUP_LABEL, type Coverage, type CoverageItem, type Studio } from "@/lib/mapping";
import { mappingStudio } from "@/lib/mapping-data";
import { DraftBar } from "./DraftBar";
import { FieldsPanel } from "./Fields";
import { QueuePanel } from "./Queue";
import { SchemaPanel } from "./Schema";
import { StagesPanel } from "./Stages";
import { TestPanel } from "./TestPanel";
import { ActivitiesPanel, ValuesPanel } from "./Values";
import { VersionsPanel } from "./Versions";

type Props = { params: Promise<{ partnerId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
const TABS = [
  { id: "stages", label: "Stages" }, { id: "fields", label: "Fields" }, { id: "values", label: "Values" }, { id: "activities", label: "Activities" },
  { id: "test", label: "Test" }, { id: "queue", label: "Queue" }, { id: "schema", label: "Schema" }, { id: "versions", label: "Versions" },
] as const;
type Tab = (typeof TABS)[number]["id"];
const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const id = parseId((await params).partnerId);
  const s = id ? await mappingStudio(id).catch(() => null) : null;
  return { title: s ? `${s.partner.name} · Mapping` : "Mapping studio" };
}

function CoverageCard({ c, studio }: { c: Coverage; studio: Studio }) {
  const pct = c.required_total ? Math.round((c.required_done / c.required_total) * 100) : 0;
  const open = c.items.filter((i) => i.required && !i.done);
  const groups = [...new Set(open.map((i) => i.group))] as CoverageItem["group"][];
  const failing = studio.editing?.goldens.filter((g) => !g.pass).length ?? 0;
  const ready = pct === 100 && failing === 0;
  return (
    <Card className="mb-6 min-w-0">
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3 px-5 py-4">
        <div className="min-w-[220px] flex-1">
          <p className="flex items-center gap-2 text-[13px] font-medium text-fg">
            Coverage for go-live {ready ? <Badge tone="success">Ready</Badge> : <Badge tone="warning">Not ready</Badge>}
          </p>
          <div className="mt-2 flex items-center gap-3">
            <div className="h-2 flex-1 overflow-hidden rounded-full bg-surface-2" aria-hidden><div className={cn("h-full rounded-full", pct === 100 ? "bg-success" : "bg-amber")} style={{ width: `${pct}%` }} /></div>
            <span className="tabular text-[13px] text-muted">{c.required_done} of {c.required_total} required</span>
          </div>
        </div>
        <p className="text-[12.5px] text-muted">
          {c.stages_seen} partner stages seen · {studio.editing?.goldens.length ?? 0} golden files{failing > 0 && <span className="text-danger"> ({failing} failing)</span>}
          {studio.held_events > 0 && <> · <span className="text-warning">{studio.held_events} events held</span></>}
        </p>
      </div>
      {open.length > 0 && (
        <details className="border-t border-border px-5 py-3 text-[12.5px]">
          <summary className="cursor-pointer text-muted">Still missing ({open.length})</summary>
          <div className="mt-2 grid gap-3 md:grid-cols-2">
            {groups.map((g) => (
              <div key={g}>
                <p className="mb-1 font-medium text-fg">{COVERAGE_GROUP_LABEL[g]}</p>
                <ul className="space-y-0.5">{open.filter((i) => i.group === g).map((i) => <li key={i.item} className="flex items-center gap-1.5 text-muted"><CircleDashed className="size-3.5 text-subtle" /> {i.item}</li>)}</ul>
              </div>
            ))}
          </div>
        </details>
      )}
      {open.length === 0 && c.required_total > 0 && (
        <p className="flex items-center gap-1.5 border-t border-border px-5 py-3 text-[12.5px] text-success"><CircleCheck className="size-4" /> Every partner stage, required field and test-lead value is mapped.</p>
      )}
    </Card>
  );
}

export default async function MappingStudioPage({ params, searchParams }: Props) {
  await requireAdmin();
  const id = parseId((await params).partnerId);
  if (!id) notFound();
  const s = await mappingStudio(id);
  if (!s) notFound();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "stages";
  const ed = s.editing;
  const openQueue = s.queue.filter((q) => q.status === "open").length;

  return (
    <>
      <Link href="/mapping" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Mapping studio</Link>
      <div className="mb-5 flex flex-wrap items-center gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-xl font-semibold tracking-tight text-fg">{s.partner.name}</h1>
          <p className="text-[13px] text-muted">
            {s.partner.adapter_type.replace("_", " ")} · {s.profiles.find((p) => p.status === "active") ? `version ${s.profiles.find((p) => p.status === "active")!.version} active` : "no published mapping"}
          </p>
        </div>
        <Link href={`/partners/${s.partner.id}`} className={buttonClass("secondary", "sm")}>Partner page</Link>
      </div>

      <DraftBar partnerId={s.partner.id} editing={ed} failingGoldens={ed?.goldens.filter((g) => !g.pass).length ?? 0} held={s.held_events} />
      {ed && <CoverageCard c={ed.coverage} studio={s} />}

      <nav aria-label="Mapping sections" className="mb-6 flex gap-5 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <Link key={t.id} href={`/mapping/${s.partner.id}?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
            {t.id === "queue" && openQueue > 0 && <span className="tabular ml-1.5 rounded bg-warning-bg px-1 text-[11px] text-warning">{openQueue}</span>}
            {t.id === "stages" && ed && <span className="tabular ml-1.5 text-[11px] text-subtle">{ed.status_rules.length}</span>}
            {t.id === "fields" && ed && <span className="tabular ml-1.5 text-[11px] text-subtle">{ed.field_rules.length}</span>}
          </Link>
        ))}
      </nav>

      <Card className="min-w-0 overflow-hidden">
        {tab === "stages" && <StagesPanel studio={s} />}
        {tab === "fields" && <FieldsPanel studio={s} />}
        {tab === "values" && <ValuesPanel studio={s} />}
        {tab === "activities" && <ActivitiesPanel studio={s} />}
        {tab === "test" && <TestPanel studio={s} />}
        {tab === "queue" && <QueuePanel studio={s} />}
        {tab === "schema" && <SchemaPanel studio={s} />}
        {tab === "versions" && <VersionsPanel studio={s} />}
      </Card>
    </>
  );
}
