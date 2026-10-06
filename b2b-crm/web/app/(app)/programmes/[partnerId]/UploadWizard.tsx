"use client";
import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { FileSpreadsheet, LoaderCircle, Upload } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import { Notice } from "@/components/ui/Notice";
import { FIELDS, type FieldKey, type Template } from "@/lib/programmes";
import { createDraft, stageFile, switchSheet, type Staged } from "../actions";

const select = "h-9 w-full rounded-lg border border-border bg-surface px-2.5 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

/** Upload → choose sheet and map columns (pre-filled from the partner's saved template) → create a draft. */
export function UploadWizard({ partnerId, hasTemplate }: { partnerId: number; hasTemplate: boolean }) {
  const [staged, setStaged] = useState<Staged | null>(null);
  const [template, setTemplate] = useState<Template>({});
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [drag, setDrag] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const router = useRouter();

  const upload = (file: File | undefined) => {
    if (!file) return;
    setError(null);
    const fd = new FormData();
    fd.set("file", file);
    start(async () => {
      const res = await stageFile(partnerId, fd);
      if (!res.ok) { setError(res.error); return; }
      setStaged(res.staged);
      setTemplate(res.staged.template);
    });
  };

  const changeSheet = (sheet: string) => {
    if (!staged) return;
    setError(null);
    start(async () => {
      const res = await switchSheet(partnerId, staged.path, staged.fileName, sheet);
      if (!res.ok) { setError(res.error); return; }
      setStaged(res.staged);
      setTemplate(res.staged.template);
    });
  };

  const submit = () => {
    if (!staged) return;
    setError(null);
    start(async () => {
      const res = await createDraft(partnerId, { path: staged.path, fileName: staged.fileName, sheet: staged.sheet, template });
      if ("error" in res) setError(res.error);
      else router.push(`/programmes/${partnerId}/versions/${res.versionId}`);
    });
  };

  if (!staged) {
    return (
      <div className="space-y-4">
        <label
          onDragOver={(e) => { e.preventDefault(); setDrag(true); }}
          onDragLeave={() => setDrag(false)}
          onDrop={(e) => { e.preventDefault(); setDrag(false); upload(e.dataTransfer.files[0]); }}
          className={cn(
            "flex cursor-pointer flex-col items-center justify-center rounded-[var(--radius-card)] border-2 border-dashed px-6 py-12 text-center transition-colors",
            drag ? "border-ring bg-amber/10" : "border-border bg-surface hover:border-border-strong",
          )}
        >
          {pending ? <LoaderCircle className="size-8 animate-spin text-muted" /> : <FileSpreadsheet className="size-8 text-muted" />}
          <span className="mt-3 text-sm font-medium text-fg">{pending ? "Reading the file…" : "Drop the partner's programme file here, or choose it"}</span>
          <span className="mt-1 text-[12.5px] text-muted">Excel (.xlsx) or CSV, up to 4 MB and 5,000 rows. Old .xls files: save as .xlsx first.</span>
          <input ref={input} type="file" accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" className="sr-only" disabled={pending}
            onChange={(e) => upload(e.target.files?.[0])} />
          <span className={cn("mt-4", pending && "invisible")}><span className="inline-flex h-8 items-center gap-1.5 rounded-lg bg-primary px-3 text-[13px] font-medium text-primary-fg"><Upload className="size-3.5" /> Choose file</span></span>
        </label>
        {error && <Notice tone="error">{error}</Notice>}
        <p className="text-[12.5px] text-muted">
          The file is kept exactly as uploaded. {hasTemplate ? "Columns are matched using this partner's saved template." : "You map its columns once; the mapping is saved for the next file."}
        </p>
      </div>
    );
  }

  const missing = FIELDS.filter((f) => f.required && !template[f.key]);
  const set = (k: FieldKey, v: string) => setTemplate((t) => { const n = { ...t }; if (v) n[k] = v; else delete n[k]; return n; });

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-surface px-4 py-3">
        <FileSpreadsheet className="size-5 shrink-0 text-success" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13.5px] font-medium text-fg">{staged.fileName}</p>
          <p className="text-[12px] text-muted"><span className="tabular">{staged.rowCount}</span> rows · {staged.headers.length} columns</p>
        </div>
        {staged.sheets.length > 1 && (
          <label className="flex items-center gap-2 text-[13px] text-muted">
            Sheet
            <select value={staged.sheet} onChange={(e) => changeSheet(e.target.value)} disabled={pending} className={cn(select, "w-48")}>
              {staged.sheets.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
        )}
        <Button variant="ghost" size="sm" onClick={() => { setStaged(null); setError(null); }} disabled={pending}>Use another file</Button>
      </div>

      <div className="overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface">
        <div className="border-b border-border px-5 py-3">
          <h3 className="text-sm font-semibold text-fg">Match the file&apos;s columns</h3>
          <p className="text-[12.5px] text-muted">Required fields are marked. Leave a field empty when the file does not have it.</p>
        </div>
        <div className="divide-y divide-border">
          {FIELDS.map((f) => {
            const col = template[f.key];
            const examples = col ? staged.sample.map((r) => r[col]).filter(Boolean).slice(0, 3) : [];
            return (
              <div key={f.key} className="grid items-center gap-x-4 gap-y-1 px-5 py-2 sm:grid-cols-[200px_240px_minmax(0,1fr)]">
                <label htmlFor={`map-${f.key}`} className="text-[13px] text-fg">
                  {f.label}{f.required && <span className="ml-0.5 text-danger" aria-label="required">*</span>}
                </label>
                <select id={`map-${f.key}`} value={col ?? ""} onChange={(e) => set(f.key, e.target.value)} className={select}
                  aria-invalid={f.required && !col}>
                  <option value="">— Not in this file —</option>
                  {staged.headers.map((h) => <option key={h} value={h}>{h}</option>)}
                </select>
                <p className="truncate text-[12px] text-subtle" title={examples.join(" · ")}>{examples.length ? examples.join(" · ") : col ? "Empty in the first rows" : ""}</p>
              </div>
            );
          })}
        </div>
      </div>

      {error && <Notice tone="error">{error}</Notice>}
      <div className="flex flex-wrap items-center justify-end gap-3">
        {missing.length > 0 && <p className="mr-auto text-[13px] text-warning">Choose the column for {missing.map((f) => f.label).join(", ")}.</p>}
        <Button onClick={submit} disabled={pending || missing.length > 0} aria-busy={pending}>
          {pending && <LoaderCircle className="size-4 animate-spin" />}
          {pending ? "Matching to the catalogue…" : `Create draft from ${staged.rowCount} rows`}
        </Button>
      </div>
    </div>
  );
}
