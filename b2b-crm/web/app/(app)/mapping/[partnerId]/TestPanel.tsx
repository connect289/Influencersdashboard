"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { CircleCheck, CircleX, LoaderCircle, Play, Save, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { STAGE_LABEL, type Studio } from "@/lib/mapping";
import { archiveGolden, saveGolden, testInbound, testOutbound } from "./actions";
import { area, field, fieldBase } from "@/components/ui/Modal";

type InResult = {
  status?: { matched: boolean; stage?: string; sub_stage?: string; lost_reason?: string; ignored?: boolean; ignore_reason?: string; is_reopen?: boolean };
  fields?: Record<string, string>;
  custom?: Record<string, unknown>;
  activity?: { kind: string; outcome?: string };
  unmapped?: { kind: string; item: string; error?: string }[];
};
type OutResult = { canonical: Record<string, string>; roundtrip: { out: { fields: Record<string, string>; missing_required: string[]; unmapped: { item: string }[] }; checks: { key: string; sent: string; back: string | null; pass: boolean }[] } };

const EXAMPLE = '{\n  "stage": "Attempted",\n  "sub_stage": "RNR",\n  "fields": { "Counsellor": "Priya", "Next Call": "07/10/2026 11:00" }\n}';

export function TestPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const ed = studio.editing;
  const [kind, setKind] = useState<"stage" | "update" | "activity">("stage");
  const [sample, setSample] = useState(EXAMPLE);
  const [res, setRes] = useState<InResult | null>(null);
  const [pending, setPending] = useState(false);
  const [goldenName, setGoldenName] = useState("");
  const [expected, setExpected] = useState("");
  const [leadId, setLeadId] = useState("");
  const [out, setOut] = useState<OutResult | null>(null);
  const [archive, setArchive] = useState<{ id: number; name: string } | null>(null);
  const label = (k: string) => studio.canonical.find((c) => c.key === k)?.label ?? k;
  const results = new Map((ed?.goldens ?? []).map((g) => [g.id, g]));

  const run = async () => {
    if (!ed) return;
    setPending(true);
    const r = await testInbound(studio.partner.id, ed.id, kind, sample);
    setPending(false);
    if (!r.ok) { toast.error(r.error); return; }
    const d = r.data as InResult;
    setRes(d);
    const exp: Record<string, unknown> = {};
    if (d.status?.matched) exp.status = Object.fromEntries(Object.entries({ stage: d.status.stage, sub_stage: d.status.sub_stage, lost_reason: d.status.lost_reason, ignored: d.status.ignored || undefined }).filter(([, v]) => v !== undefined));
    if (d.fields && Object.keys(d.fields).length) exp.fields = d.fields;
    if (d.activity) exp.activity = { kind: d.activity.kind, ...(d.activity.outcome ? { outcome: d.activity.outcome } : {}) };
    setExpected(JSON.stringify(exp, null, 2));
  };
  const runOut = async () => {
    if (!ed) return;
    setPending(true);
    const r = await testOutbound(studio.partner.id, ed.id, Number(leadId));
    setPending(false);
    if (!r.ok) { toast.error(r.error); return; }
    setOut(r.data as unknown as OutResult);
  };
  const save = async () => {
    let data: unknown;
    try { data = JSON.parse(sample); } catch { toast.error("The sample is not valid JSON."); return; }
    const r = await saveGolden(studio.partner.id, goldenName, JSON.stringify({ kind, data }), expected);
    if (!r.ok) { toast.error(r.error); return; }
    toast.success("Golden file saved; every publish now runs it");
    setGoldenName(""); router.refresh();
  };

  if (!ed) return <p className="px-5 py-6 text-[13px] text-muted">Start a draft first; tests run against the draft (or the active version).</p>;
  return (
    <div className="grid gap-6 p-5 xl:grid-cols-2">
      <Card className="min-w-0">
        <CardHeader title="Partner → Eduwit" description={`A payload as the partner sends it, through ${ed.status === "draft" ? "the draft" : `version ${ed.version}`}. Nothing is saved.`} />
        <div className="space-y-3 px-5 py-4">
          <div className="flex flex-wrap gap-2">
            <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} className={cn(fieldBase, "w-36")} aria-label="Event type">
              <option value="stage">stage</option><option value="update">update</option><option value="activity">activity</option>
            </select>
            {studio.samples.length > 0 && (
              <select onChange={(e) => { const s = studio.samples.find((x) => String(x.id) === e.target.value); if (s) { setKind(s.type as typeof kind); setSample(JSON.stringify(s.data, null, 2)); } }}
                className={cn(fieldBase, "min-w-0 flex-1")} aria-label="Use a received event" defaultValue="">
                <option value="" disabled>Use a received event…</option>
                {studio.samples.map((s) => <option key={s.id} value={s.id}>#{s.id} {s.type} · {String((s.data as Record<string, unknown>).stage ?? (s.data as Record<string, unknown>).type ?? "")} · {s.status}</option>)}
              </select>
            )}
          </div>
          <textarea value={sample} onChange={(e) => setSample(e.target.value)} rows={8} className={area} aria-label="Payload data" spellCheck={false} />
          <Button size="sm" onClick={run} disabled={pending}>{pending ? <LoaderCircle className="size-3.5 animate-spin" /> : <Play className="size-3.5" />} Run</Button>
          {res && (
            <div className="space-y-2 rounded-lg border border-border p-3 text-[12.5px]">
              {res.status && (
                <p>Stage: {res.status.matched
                  ? res.status.ignored ? <Badge>Ignored: {res.status.ignore_reason}</Badge>
                    : <><Badge tone="info">{STAGE_LABEL[res.status.stage ?? ""] ?? res.status.stage}</Badge>{res.status.sub_stage && <span className="text-muted"> {res.status.sub_stage}</span>}{res.status.lost_reason && <span className="text-muted"> · {res.status.lost_reason}</span>}</>
                  : <Badge tone="warning">No rule: the event would be held</Badge>}</p>
              )}
              {res.activity && <p>Activity: <Badge tone="info">{res.activity.kind}</Badge> {res.activity.outcome}</p>}
              {res.fields && Object.keys(res.fields).length > 0 && (
                <dl className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)] gap-x-3 gap-y-0.5">
                  {Object.entries(res.fields).map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{label(k)}</dt><dd className="truncate font-mono text-fg">{v}</dd></div>)}
                </dl>
              )}
              {res.custom && Object.keys(res.custom).length > 0 && <p className="text-muted">Kept as custom: <span className="font-mono">{Object.keys(res.custom).join(", ")}</span></p>}
              {(res.unmapped ?? []).length > 0 && (
                <ul className="space-y-0.5 text-warning">{res.unmapped!.map((u, i) => <li key={i}>Unmapped {u.kind}: {u.item}{u.error && ` (${u.error})`}</li>)}</ul>
              )}
            </div>
          )}
          {res && (
            <div className="space-y-2 border-t border-border pt-3">
              <p className="text-[13px] font-medium">Keep it as a golden file</p>
              <p className="text-[12px] text-muted">Every publish re-runs it; the result must still contain what you expect below.</p>
              <input value={goldenName} onChange={(e) => setGoldenName(e.target.value)} placeholder="e.g. RNR is contacted" className={field} maxLength={80} />
              <textarea value={expected} onChange={(e) => setExpected(e.target.value)} rows={5} className={area} aria-label="Expected result" spellCheck={false} />
              <Button size="sm" variant="secondary" onClick={save} disabled={goldenName.trim().length < 2}><Save className="size-3.5" /> Save golden file</Button>
            </div>
          )}
        </div>
      </Card>

      <div className="space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Eduwit → partner → Eduwit" description="A lead as the partner would receive it, then read back through the inbound rules (round trip)." />
          <div className="space-y-3 px-5 py-4">
            <div className="flex gap-2">
              <input value={leadId} onChange={(e) => setLeadId(e.target.value.replace(/\D/g, ""))} placeholder="Lead number" inputMode="numeric" className={cn(fieldBase, "w-40")} />
              <Button size="sm" onClick={runOut} disabled={pending || !leadId}><Play className="size-3.5" /> Run</Button>
            </div>
            {out && (
              <div className="space-y-2 text-[12.5px]">
                <p className="text-muted">Fields the partner receives{Object.keys(out.roundtrip.out.fields).length === 0 && ": none (no outbound rules; the standard Eduwit payload is sent)"}</p>
                {Object.keys(out.roundtrip.out.fields).length > 0 && (
                  <dl className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)] gap-x-3 gap-y-0.5 rounded-lg border border-border p-3">
                    {Object.entries(out.roundtrip.out.fields).map(([k, v]) => <div key={k} className="contents"><dt className="font-mono text-muted">{k}</dt><dd className="truncate text-fg">{v}</dd></div>)}
                  </dl>
                )}
                {out.roundtrip.out.missing_required.length > 0 && <p className="text-danger">Missing required: {out.roundtrip.out.missing_required.map(label).join(", ")}</p>}
                {out.roundtrip.checks.length > 0 && (
                  <ul className="space-y-0.5">
                    {out.roundtrip.checks.map((c) => (
                      <li key={c.key} className="flex items-center gap-1.5">
                        {c.pass ? <CircleCheck className="size-3.5 text-success" /> : <CircleX className="size-3.5 text-danger" />}
                        {label(c.key)}: <span className="font-mono">{c.sent}</span>{!c.pass && <> came back as <span className="font-mono">{c.back ?? "nothing"}</span></>}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
        </Card>

        <Card className="min-w-0">
          <CardHeader title="Golden files" description="Sample payloads and the result they must give. A failing file blocks publishing." />
          {studio.goldens.length === 0 ? <p className="px-5 py-4 text-[13px] text-muted">None yet. Run a test and keep it as a golden file.</p> : (
            <ul className="divide-y divide-border">
              {studio.goldens.map((g) => {
                const r = results.get(g.id);
                return (
                  <li key={g.id} className="flex items-center gap-2 px-5 py-2.5 text-[12.5px]">
                    {r?.pass ? <CircleCheck className="size-4 text-success" /> : <CircleX className="size-4 text-danger" />}
                    <span className="min-w-0 flex-1"><span className="font-medium text-fg">{g.name}</span> <span className="text-subtle">{g.input.kind}</span>
                      {r && !r.pass && <span className="block truncate text-danger" title={JSON.stringify(r.actual ?? r.error)}>{r.error ?? "result differs from what is expected"}</span>}</span>
                    <Button size="sm" variant="ghost" onClick={() => setArchive({ id: g.id, name: g.name })} aria-label="Remove"><Trash2 className="size-3.5" /></Button>
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      </div>
      <ConfirmDialog
        open={archive !== null} onClose={() => setArchive(null)} title={`Remove the golden file “${archive?.name ?? ""}”?`} tone="danger" confirmLabel="Remove"
        onConfirm={async () => {
          if (!archive) return;
          const r = await archiveGolden(studio.partner.id, archive.id);
          if (!r.ok) return r.error;
          toast.success("Golden file removed");
          router.refresh();
        }}
      >
        Publishing no longer checks it. It is archived, not erased.
      </ConfirmDialog>
    </div>
  );
}
