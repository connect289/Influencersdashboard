import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, Download, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { partnerTitle } from "@/lib/partners";
import { commissionText, inr, VERSION_LABEL, VERSION_TONE } from "@/lib/programmes";
import { catalogueUniversities, partnerRepo, programmeVersion, versionPreview, type Preview } from "@/lib/programmes-data";
import { PublishBar } from "./PublishBar";
import { ReviewTable } from "./ReviewTable";

type Props = { params: Promise<{ partnerId: string; versionId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

const VIEWS = [
  { id: "review", label: "To review", statuses: ["needs_review", "no_match"] },
  { id: "matched", label: "Matched", statuses: ["auto", "approved"] },
  { id: "ignored", label: "Ignored", statuses: ["ignored"] },
  { id: "all", label: "All rows", statuses: null },
] as const;

export const metadata: Metadata = { title: "Programme file review" };

const pct = (n: number | null) => (n === null ? "" : `${Math.round(n * 100)}%`);

function Changes({ p }: { p: Preview }) {
  const gaps = [...p.added, ...p.changed].filter((x) => (x.fee_gap ?? 0) > 0.1);
  return (
    <div className="grid gap-px overflow-hidden bg-border md:grid-cols-3">
      <section className="bg-surface px-5 py-4">
        <h3 className="text-[13px] font-semibold text-success">+ {p.added.length} added</h3>
        <ul className="mt-2 max-h-56 space-y-1 overflow-y-auto text-[12.5px]">
          {p.added.slice(0, 200).map((a) => <li key={a.id} className="truncate text-fg">{a.university_short || a.university} · {a.course} · {a.specialization} <span className="text-subtle">{a.mode}</span></li>)}
          {p.added.length === 0 && <li className="text-subtle">None</li>}
        </ul>
      </section>
      <section className="bg-surface px-5 py-4">
        <h3 className="text-[13px] font-semibold text-danger">− {p.removed.length} removed</h3>
        <ul className="mt-2 max-h-56 space-y-1 overflow-y-auto text-[12.5px]">
          {p.removed.slice(0, 200).map((r) => (
            <li key={r.id} className={cn("truncate", r.last_partner ? "font-medium text-danger" : "text-fg")} title={r.last_partner ? "No other partner offers this programme" : undefined}>
              {r.last_partner && <TriangleAlert className="mr-1 inline size-3 align-[-1px]" />}{r.university_short || r.university} · {r.course} · {r.specialization}
            </li>
          ))}
          {p.removed.length === 0 && <li className="text-subtle">None</li>}
        </ul>
      </section>
      <section className="bg-surface px-5 py-4">
        <h3 className="text-[13px] font-semibold text-warning">~ {p.changed.length} changed <span className="font-normal text-subtle">· {p.unchanged} unchanged</span></h3>
        <ul className="mt-2 max-h-56 space-y-1.5 overflow-y-auto text-[12.5px]">
          {p.changed.slice(0, 200).map((c) => (
            <li key={c.id}>
              <span className="block truncate text-fg">{c.university_short || c.university} · {c.course} · {c.specialization}</span>
              <span className="block text-subtle">
                {c.fields.join(", ")}
                {c.fields.includes("fees") && ` · ${inr(c.old_fees?.total)} → ${inr(c.new_fees?.total)}`}
                {c.fields.includes("commission") && ` · ${commissionText(c.old_commission)} → ${commissionText(c.new_commission)}`}
              </span>
            </li>
          ))}
          {p.changed.length === 0 && <li className="text-subtle">None</li>}
        </ul>
      </section>
      {(gaps.length > 0 || p.duplicates > 0 || p.proposed_commission > 0) && (
        <section className="space-y-1 bg-surface px-5 py-3 text-[12.5px] md:col-span-3">
          {gaps.length > 0 && (
            <p className="text-warning">
              <TriangleAlert className="mr-1 inline size-3.5 align-[-2px]" />
              {gaps.length} {gaps.length === 1 ? "programme's" : "programmes'"} partner fee differs from the catalogue by more than 10%:{" "}
              {gaps.slice(0, 5).map((g) => `${g.course} ${g.specialization} (${pct(g.fee_gap)})`).join(", ")}{gaps.length > 5 ? "…" : ""}
            </p>
          )}
          {p.duplicates > 0 && <p className="text-muted">{p.duplicates} {p.duplicates === 1 ? "row matches" : "rows match"} a programme another row already has; the first row is used.</p>}
          {p.proposed_commission > 0 && <p className="text-muted">{p.proposed_commission} programmes carry a commission in the file. These are stored as proposed rates; rates take effect only when you confirm them (rates screen, coming with Commission).</p>}
        </section>
      )}
    </div>
  );
}

export default async function VersionPage({ params, searchParams }: Props) {
  await requireAdmin();
  const { partnerId: pid, versionId: vid } = await params;
  const partnerId = parseId(pid), versionId = parseId(vid);
  if (!partnerId || !versionId) notFound();
  const [repo, v, preview, universities] = await Promise.all([partnerRepo(partnerId), programmeVersion(versionId), versionPreview(versionId), catalogueUniversities()]);
  if (!repo || !v || !preview || v.partner_id !== partnerId) notFound();

  const sp = await searchParams;
  const count = (s: readonly string[] | null) => (s ? v.rows.filter((r) => s.includes(r.review_status)).length : v.rows.length);
  const defaultView = count(VIEWS[0].statuses) > 0 ? "review" : "all";
  const view = VIEWS.find((x) => x.id === sp.show) ?? VIEWS.find((x) => x.id === defaultView)!;
  const rows = view.statuses ? v.rows.filter((r) => (view.statuses as readonly string[]).includes(r.review_status)) : v.rows;
  const editable = v.status === "draft";
  const publishable = v.status === "draft" || v.status === "superseded" || v.status === "rolled_back";
  const lastPartnerLosses = preview.removed.filter((r) => r.last_partner).length;
  const summary = `${preview.new_count} programmes will be live (now ${preview.live_count}): ${preview.added.length} added, ${preview.removed.length} removed, ${preview.changed.length} changed.`;

  return (
    <>
      <Link href={`/programmes/${partnerId}?tab=versions`} className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> {partnerTitle(repo.partner)}</Link>
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="flex flex-wrap items-center gap-2 text-xl font-semibold tracking-tight text-fg">
            Version {v.version_no} <Badge tone={VERSION_TONE[v.status] ?? "neutral"}>{VERSION_LABEL[v.status] ?? v.status}</Badge>
          </h1>
          <p className="mt-1 text-[13px] text-muted">
            {v.file_name ?? "File"}{v.sheet && v.sheet !== "CSV" ? ` · sheet ${v.sheet}` : ""} · {v.row_count} rows · uploaded <span title={formatDateTime(v.uploaded_at)}>{relativeTime(v.uploaded_at)}</span>
            {v.file_path && <> · <a href={`/programmes/files/${v.id}`} className="inline-flex items-center gap-1 text-info hover:underline"><Download className="size-3" />original file</a></>}
          </p>
        </div>
        {publishable && <PublishBar partnerId={partnerId} versionId={v.id} status={v.status} pending={preview.pending_review} summary={summary} warnRemovals={lastPartnerLosses} />}
      </div>

      <Card className="mb-6 overflow-hidden">
        <CardHeader
          title={v.status === "published" ? "What this version changed" : "If you publish this version"}
          description={editable && preview.pending_review > 0 ? `${preview.pending_review} ${preview.pending_review === 1 ? "row needs" : "rows need"} review before publishing. Ignored rows: ${preview.ignored}.` : summary}
        />
        <Changes p={preview} />
      </Card>

      <Card className="overflow-hidden">
        <nav aria-label="Rows" className="flex flex-wrap gap-1 border-b border-border px-3 py-2">
          {VIEWS.map((x) => (
            <Link key={x.id} href={`?show=${x.id}`} scroll={false} aria-current={view.id === x.id ? "page" : undefined}
              className={cn("rounded-md px-2.5 py-1.5 text-[13px] transition-colors", view.id === x.id ? "bg-surface-2 font-medium text-fg" : "text-muted hover:text-fg")}>
              {x.label} <span className="tabular text-[11px] text-subtle">{count(x.statuses)}</span>
            </Link>
          ))}
        </nav>
        <ReviewTable key={view.id} versionId={v.id} rows={rows} editable={editable} universities={universities} />
      </Card>
      {!editable && (
        <p className="mt-3 text-[12.5px] text-subtle">Only a draft can be reviewed. To change a published file, upload a new version.</p>
      )}
      {editable && preview.pending_review === 0 && (
        <div className="mt-4 flex flex-wrap items-center justify-end gap-3">
          <p className="text-[13px] text-muted">Every row is reviewed.</p>
          <PublishBar partnerId={partnerId} versionId={v.id} status={v.status} pending={0} summary={summary} warnRemovals={lastPartnerLosses} />
        </div>
      )}
    </>
  );
}
