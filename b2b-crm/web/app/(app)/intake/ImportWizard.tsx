"use client";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, ArrowRight, Check, Download, FileSpreadsheet, LoaderCircle, Upload, Wand2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import {
  CHUNK_ROWS, IMPORT_FIELDS, MAX_IMPORT_BYTES, MAX_IMPORT_ROWS, PREVIEW_LABEL, ROUTE_CHOICE, chunk, mappingProblem, parseCsvRows, suggestMapping,
  tableFromRows, toCsv, type Cell, type CourseMatch, type FileTable, type ImportPreview, type IntakeOverview, type Mapping,
} from "@/lib/intake";
import {
  commitImport, continueImport, createImport, importCourses, importPreview, importRowsPage, releaseHeld, setImportCourse, stageRows, type CommitForm,
} from "./actions";
import { area, download, field, fieldSm, label } from "./ui";

type Step = "upload" | "map" | "courses" | "preview" | "confirm" | "run";
const STEPS: { id: Step; label: string }[] = [
  { id: "upload", label: "Upload" }, { id: "map", label: "Map columns" }, { id: "courses", label: "Check courses" },
  { id: "preview", label: "Duplicates" }, { id: "confirm", label: "Consent and routing" },
];
const GROUPS = Object.keys(PREVIEW_LABEL);

function Steps({ step }: { step: Step }) {
  const at = step === "run" ? STEPS.length : STEPS.findIndex((s) => s.id === step);
  return (
    <ol className="flex flex-wrap gap-x-5 gap-y-2 border-b border-border px-5 py-3 text-[12.5px]" aria-label="Import steps">
      {STEPS.map((s, i) => (
        <li key={s.id} aria-current={i === at ? "step" : undefined} className={cn("flex items-center gap-1.5", i === at ? "font-medium text-fg" : i < at ? "text-muted" : "text-subtle")}>
          <span className={cn("grid size-5 place-items-center rounded-full border text-[11px] tabular", i < at ? "border-success bg-success text-white" : i === at ? "border-amber bg-amber/15 text-fg" : "border-border")}>
            {i < at ? <Check className="size-3" /> : i + 1}
          </span>
          {s.label}
        </li>
      ))}
    </ol>
  );
}

function Bar({ value, total }: { value: number; total: number }) {
  const pct = total ? Math.min(100, Math.round((value / total) * 100)) : 0;
  return (
    <div className="space-y-1">
      <div className="h-2 overflow-hidden rounded-full bg-surface-2" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
        <div className="h-full rounded-full bg-amber transition-[width] duration-300" style={{ width: `${pct}%` }} />
      </div>
      <p className="tabular text-[12px] text-muted">{value.toLocaleString("en-IN")} of {total.toLocaleString("en-IN")} ({pct}%)</p>
    </div>
  );
}

async function readFile(f: File): Promise<{ sheets: { name: string; rows: Cell[][] }[] }> {
  const lower = f.name.toLowerCase();
  if (lower.endsWith(".xls")) throw new Error("Old .xls files cannot be read. Open the file and save it as .xlsx or CSV.");
  if (lower.endsWith(".xlsx")) {
    const { default: readXlsxFile } = await import("read-excel-file/browser");
    const sheets = await readXlsxFile(f);
    return { sheets: sheets.map((s) => ({ name: s.sheet, rows: s.data as Cell[][] })) };
  }
  if (lower.endsWith(".csv") || lower.endsWith(".txt") || f.type === "text/csv") return { sheets: [{ name: f.name, rows: parseCsvRows(await f.text()) }] };
  throw new Error("Choose an Excel (.xlsx) or CSV file.");
}

/** Downloads every row of an import (or one preview group) as CSV, 5,000 at a time. */
async function downloadRows(importId: number, group: string | null, fileName: string) {
  const all: Record<string, unknown>[] = [];
  let after = 0;
  for (;;) {
    const r = await importRowsPage(importId, group, after);
    if (!r.ok) { toast.error(r.error); return; }
    all.push(...r.data);
    if (r.data.length < 5000) break;
    after = Number(r.data[r.data.length - 1]!.row_no);
  }
  download(`${fileName.replace(/\.[^.]+$/, "")}-${group ?? "all"}.csv`,
    toCsv(all, ["row_no", "name", "phone", "email", "course", "preview", "problems", "existing_lead_id", "status", "action", "lead_id", "error"]));
}

export function ImportWizard({ templates, resume }: { templates: IntakeOverview["templates"]; resume: { id: number; status: string; file_name: string } | null }) {
  const router = useRouter();
  const [step, setStep] = useState<Step>("upload");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const [fileName, setFileName] = useState("");
  const [sheets, setSheets] = useState<{ name: string; rows: Cell[][] }[]>([]);
  const [sheet, setSheet] = useState(0);
  const [table, setTable] = useState<FileTable | null>(null);
  const [mapping, setMapping] = useState<Mapping>({});
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [templateName, setTemplateName] = useState("");

  const [importId, setImportId] = useState<number | null>(null);
  const [staged, setStaged] = useState(0);
  const [courses, setCourses] = useState<CourseMatch[]>([]);
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [run, setRun] = useState<{ done: number; total: number; status: string } | null>(null);
  const stop = useRef(false);

  const loadAfterStaging = useCallback(async (id: number) => {
    const [c, p] = await Promise.all([importCourses(id), importPreview(id)]);
    if (!c.ok) throw new Error(c.error);
    if (!p.ok) throw new Error(p.error);
    setCourses(c.data);
    setPreview(p.data);
    return p.data;
  }, []);

  const keepRunning = useCallback(async (id: number) => {
    stop.current = false;
    for (let i = 0; i < 400 && !stop.current; i++) {
      const r = await continueImport(id);
      if (!r.ok) { setError(r.error); break; }
      const p = await importPreview(id);
      if (p.ok) {
        setPreview(p.data);
        const total = p.data.import.total_rows;
        setRun({ done: total - (p.data.status.staged ?? 0), total, status: p.data.import.status });
      }
      if (r.data.status === "done" || r.data.left === 0) { router.refresh(); break; }
    }
  }, [router]);

  // resuming an import from the history list
  useEffect(() => {
    if (!resume) return;
    let live = true;
    (async () => {
      setBusy("Opening the import…");
      setImportId(resume.id);
      setFileName(resume.file_name);
      try {
        const p = await loadAfterStaging(resume.id);
        if (!live) return;
        if (p.import.status === "staging") setStep("courses");
        else { setStep("run"); setRun({ done: p.import.total_rows - (p.status.staged ?? 0), total: p.import.total_rows, status: p.import.status });
               if (p.import.status === "committing") void keepRunning(resume.id); }
      } catch (e) { setError(e instanceof Error ? e.message : "Could not open the import."); }
      finally { setBusy(null); }
    })();
    return () => { live = false; stop.current = true; };
  }, [resume, loadAfterStaging, keepRunning]);

  const pickTable = (rows: Cell[][]) => {
    const t = tableFromRows(rows);
    setTable(t);
    const tpl = templates.find((x) => x.id === templateId);
    setMapping(tpl ? Object.fromEntries(t.headers.map((h) => [h, tpl.mapping[h] ?? "ignore"])) : suggestMapping(t.headers));
  };

  const onFile = async (f: File | undefined) => {
    setError(null);
    if (!f) return;
    if (f.size > MAX_IMPORT_BYTES) { setError("The file is larger than 15 MB. Split it into smaller files."); return; }
    setBusy("Reading the file…");
    try {
      const r = await readFile(f);
      const nonEmpty = r.sheets.filter((s) => s.rows.length > 0);
      if (nonEmpty.length === 0) throw new Error("The file is empty.");
      setFileName(f.name);
      setSheets(nonEmpty);
      setSheet(0);
      pickTable(nonEmpty[0]!.rows);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not read the file.");
    } finally { setBusy(null); }
  };

  const applyTemplate = (id: number | null) => {
    setTemplateId(id);
    if (!table) return;
    const tpl = templates.find((x) => x.id === id);
    setMapping(tpl ? Object.fromEntries(table.headers.map((h) => [h, tpl.mapping[h] ?? "ignore"])) : suggestMapping(table.headers));
  };

  const problem = useMemo(() => mappingProblem(mapping), [mapping]);
  const usedFields = useMemo(() => new Set(Object.values(mapping)), [mapping]);

  const upload = async () => {
    if (!table || problem) return;
    setError(null);
    setBusy("Uploading rows…");
    setStaged(0);
    try {
      const c = await createImport(fileName, mapping, { name: templateName || undefined, id: templateId ?? undefined });
      if (!c.ok) throw new Error(c.error);
      setImportId(c.data);
      const parts = chunk(table.rows, CHUNK_ROWS);
      for (let i = 0; i < parts.length; i++) {
        const r = await stageRows(c.data, i * CHUNK_ROWS + 1, parts[i]!);
        if (!r.ok) throw new Error(r.error);
        setStaged(Math.min(table.rows.length, (i + 1) * CHUNK_ROWS));
      }
      await loadAfterStaging(c.data);
      setStep("courses");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not upload the rows.");
    } finally { setBusy(null); }
  };

  const choose = async (text: string, key: string | null) => {
    if (!importId) return;
    setCourses((cur) => cur.map((c) => (c.text === text ? { ...c, choice: key } : c)));
    const r = await setImportCourse(importId, text, key);
    if (!r.ok) toast.error(r.error);
  };

  const acceptSuggestions = async () => {
    if (!importId) return;
    setBusy("Saving the matches…");
    for (const c of courses) if (c.key && (c.confidence ?? 0) < 1 && !c.choice) await choose(c.text, c.key);
    setBusy(null);
  };

  // ---------- confirm ----------
  const today = new Date().toISOString().slice(0, 10);
  const [form, setForm] = useState<CommitForm>({
    source_label: "", campaign: "", routing_choice: "hold", b2c_lane: "sales",
    consent: { where: "", when: today, text: "", purposes: ["sales", "partner_share"] },
  });
  const purposes = form.consent.purposes as string[];
  const togglePurpose = (p: "partner_share" | "marketing", on: boolean) =>
    setForm((f) => ({ ...f, consent: { ...f.consent, purposes: on ? [...(f.consent.purposes as string[]), p] : (f.consent.purposes as string[]).filter((x) => x !== p) } as CommitForm["consent"] }));

  const commit = async () => {
    if (!importId) return;
    setError(null);
    setBusy("Starting the import…");
    try {
      const r = await commitImport(importId, { ...form, b2c_lane: form.routing_choice === "b2c" ? form.b2c_lane : undefined, consent: { ...form.consent, when: new Date(form.consent.when + "T12:00:00+05:30").toISOString() } });
      if (!r.ok) { setError(r.error); return; }
      setStep("run");
      const total = preview?.import.total_rows ?? 0;
      setRun({ done: total - r.data.left, total, status: r.data.status });
      if (r.data.status !== "done") void keepRunning(importId); else { const p = await importPreview(importId); if (p.ok) setPreview(p.data); router.refresh(); }
    } finally { setBusy(null); }
  };

  const reset = () => {
    stop.current = true;
    setStep("upload"); setError(null); setFileName(""); setSheets([]); setTable(null); setMapping({}); setImportId(null); setCourses([]); setPreview(null); setRun(null);
    setTemplateName(""); setTemplateId(null);
    if (resume) router.replace("/intake?tab=import");
  };

  const pv = preview?.preview ?? {};
  const toWrite = (pv.new ?? 0) + (pv.merge ?? 0) + (pv.reopen ?? 0) + (pv.duplicate_in_file ?? 0) + (pv.test ?? 0);
  const skipped = (pv.invalid ?? 0) + (pv.blocked ?? 0);
  const noCourse = preview?.problems["no course"] ?? 0;
  const unsure = courses.filter((c) => (c.confidence ?? 0) < 0.6 && !c.choice);

  return (
    <div>
      <Steps step={step} />
      <div className="space-y-4 p-5">
        {error && <Notice tone="error">{error}</Notice>}

        {step === "upload" && (
          <>
            <label className={cn("flex cursor-pointer flex-col items-center justify-center gap-2 rounded-[var(--radius-card)] border-2 border-dashed border-border bg-surface-2/40 px-6 py-10 text-center transition-colors hover:border-border-strong",
              busy && "pointer-events-none opacity-60")}
              onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); void onFile(e.dataTransfer.files[0]); }}>
              {busy ? <LoaderCircle className="size-6 animate-spin text-muted" /> : <Upload className="size-6 text-muted" />}
              <span className="text-[13.5px] font-medium text-fg">{busy ?? "Choose an Excel or CSV file, or drop it here"}</span>
              <span className="text-[12px] text-muted">.xlsx or .csv, up to {MAX_IMPORT_ROWS.toLocaleString("en-IN")} rows and 15 MB. The first row with two or more filled cells is the header.</span>
              <input type="file" accept=".xlsx,.csv,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" className="sr-only"
                onChange={(e) => { void onFile(e.target.files?.[0]); e.target.value = ""; }} />
            </label>
            {table && (
              <div className="space-y-3">
                <div className="flex flex-wrap items-center gap-3 text-[13px]">
                  <FileSpreadsheet className="size-4 text-muted" />
                  <span className="font-medium text-fg">{fileName}</span>
                  <span className="tabular text-muted">{table.rows.length.toLocaleString("en-IN")} rows · {table.headers.length} columns</span>
                  {sheets.length > 1 && (
                    <select className={"h-8 w-auto rounded-lg border border-border bg-surface px-2 text-[13px] text-fg"} value={sheet} aria-label="Sheet"
                      onChange={(e) => { const i = Number(e.target.value); setSheet(i); pickTable(sheets[i]!.rows); }}>
                      {sheets.map((s, i) => <option key={s.name} value={i}>{s.name}</option>)}
                    </select>
                  )}
                </div>
                {table.truncated && <Notice tone="warning">Only the first {MAX_IMPORT_ROWS.toLocaleString("en-IN")} rows will be imported. Split the file for the rest.</Notice>}
                {table.rows.length === 0 && <Notice tone="warning">No data rows were found under the header.</Notice>}
                <div className="overflow-x-auto rounded-lg border border-border">
                  <table className="w-full min-w-[560px] text-left text-[12px]">
                    <thead className="bg-surface-2/60 text-subtle"><tr>{table.headers.map((h) => <th key={h} scope="col" className="whitespace-nowrap px-3 py-1.5 font-medium">{h}</th>)}</tr></thead>
                    <tbody className="divide-y divide-border">
                      {table.rows.slice(0, 5).map((r, i) => <tr key={i}>{table.headers.map((h) => <td key={h} className="max-w-48 truncate whitespace-nowrap px-3 py-1.5 text-fg">{r[h]}</td>)}</tr>)}
                    </tbody>
                  </table>
                </div>
                <div className="flex justify-end"><Button onClick={() => setStep("map")} disabled={table.rows.length === 0}>Map the columns <ArrowRight className="size-4" /></Button></div>
              </div>
            )}
          </>
        )}

        {step === "map" && table && (
          <>
            <div className="flex flex-wrap items-end gap-3">
              <label className="block w-64 space-y-1">
                <span className={label}>Saved mapping</span>
                <select className={field} value={templateId ?? ""} onChange={(e) => applyTemplate(e.target.value ? Number(e.target.value) : null)}>
                  <option value="">Suggested from the headers</option>
                  {templates.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </label>
              <label className="block w-64 space-y-1">
                <span className={label}>Save this mapping as <span className="font-normal text-subtle">(optional)</span></span>
                <input className={field} value={templateName} maxLength={80} placeholder="e.g. College fair sheet" onChange={(e) => setTemplateName(e.target.value)} />
              </label>
            </div>
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="w-full text-left text-[12.5px] sm:min-w-[620px]">
                <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                  <tr><th scope="col" className="px-3 py-2 font-medium">Column in the file</th><th scope="col" className="hidden px-3 py-2 font-medium sm:table-cell">Examples</th><th scope="col" className="w-48 px-3 py-2 font-medium sm:w-64">Lead field</th></tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {table.headers.map((h) => {
                    const ex = table.rows.map((r) => r[h]).filter(Boolean).slice(0, 3);
                    const v = mapping[h] ?? "ignore";
                    return (
                      <tr key={h} className={v === "ignore" ? "text-muted" : undefined}>
                        <td className="px-3 py-2 font-medium text-fg">{h}</td>
                        <td className="hidden max-w-72 truncate px-3 py-2 text-muted sm:table-cell" title={ex.join(" · ")}>{ex.join(" · ") || <span className="text-subtle">empty</span>}</td>
                        <td className="px-3 py-1.5">
                          <select className={fieldSm} value={v} aria-label={`Lead field for ${h}`} onChange={(e) => setMapping((m) => ({ ...m, [h]: e.target.value as Mapping[string] }))}>
                            <option value="ignore">Do not import</option>
                            {(["Student", "Interest", "Background", "Attribution"] as const).map((g) => (
                              <optgroup key={g} label={g}>
                                {IMPORT_FIELDS.filter((f) => f.group === g).map((f) => (
                                  <option key={f.key} value={f.key} disabled={usedFields.has(f.key) && v !== f.key}>{f.label}</option>
                                ))}
                              </optgroup>
                            ))}
                          </select>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {problem ? <Notice tone="warning">{problem}</Notice>
              : !usedFields.has("course") && <Notice tone="info">No column is mapped to the course. Leads without a course cannot be matched to a programme and are not passed to partners until a course is added.</Notice>}
            {busy && <Bar value={staged} total={table.rows.length} />}
            <div className="flex justify-between gap-2">
              <Button variant="secondary" onClick={() => setStep("upload")} disabled={Boolean(busy)}><ArrowLeft className="size-4" /> Back</Button>
              <Button onClick={upload} disabled={Boolean(problem) || Boolean(busy)}>
                {busy && <LoaderCircle className="size-4 animate-spin" />} Check {table.rows.length.toLocaleString("en-IN")} rows <ArrowRight className="size-4" />
              </Button>
            </div>
          </>
        )}

        {step === "courses" && preview && (
          <>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <p className="max-w-2xl text-[13px] text-muted">
                Each course as written in the file, matched to the catalogue. Exact names and synonyms match by themselves; for the rest pick the course, or keep it as written
                (it is matched again when the lead is routed). {noCourse > 0 && <><span className="tabular font-medium text-fg">{noCourse}</span> rows have no course.</>}
              </p>
              {courses.some((c) => c.key && (c.confidence ?? 0) < 1 && !c.choice) && (
                <Button variant="secondary" size="sm" onClick={acceptSuggestions} disabled={Boolean(busy)}><Wand2 className="size-3.5" /> Use every suggested match</Button>
              )}
            </div>
            {courses.length === 0 ? <Notice tone="info">No courses in this file.</Notice> : (
              <div className="overflow-x-auto rounded-lg border border-border">
                <table className="w-full min-w-[640px] text-left text-[12.5px]">
                  <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                    <tr><th scope="col" className="px-3 py-2 font-medium">As written</th><th scope="col" className="px-3 py-2 text-right font-medium">Rows</th>
                      <th scope="col" className="px-3 py-2 font-medium">Match</th><th scope="col" className="w-72 px-3 py-2 font-medium">Import as</th></tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {courses.map((c) => {
                      const conf = c.confidence ?? 0;
                      const opts = [...c.candidates];
                      if (c.key && !opts.some((o) => o.key === c.key)) opts.unshift({ key: c.key, label: c.label ?? c.key, s: conf });
                      return (
                        <tr key={c.text} className={conf < 0.6 && !c.choice ? "bg-warning-bg/40" : undefined}>
                          <td className="px-3 py-2 font-medium text-fg">{c.text}</td>
                          <td className="tabular px-3 py-2 text-right text-muted">{c.rows}</td>
                          <td className="px-3 py-2">
                            {conf === 1 ? <Badge tone="success">Exact: {c.label}</Badge>
                              : c.key ? <Badge tone={conf >= 0.6 ? "info" : "warning"}>{c.label} · {Math.round(conf * 100)}%</Badge>
                              : <Badge tone="danger">No match: not passed unless you pick one</Badge>}
                          </td>
                          <td className="px-3 py-1.5">
                            <select className={fieldSm} value={c.choice ?? ""} aria-label={`Course for ${c.text}`} onChange={(e) => void choose(c.text, e.target.value || null)}>
                              <option value="">{conf === 1 ? "As matched" : "Keep as written"}</option>
                              {opts.map((o) => <option key={o.key} value={o.key}>{o.label} ({Math.round(o.s * 100)}%)</option>)}
                            </select>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
            {unsure.length > 0 && <Notice tone="warning">{unsure.length} {unsure.length === 1 ? "course needs" : "courses need"} a look (highlighted). You can still go on; those leads wait as programme mismatch until fixed.</Notice>}
            <div className="flex justify-end"><Button onClick={() => setStep("preview")}>See duplicates <ArrowRight className="size-4" /></Button></div>
          </>
        )}

        {step === "preview" && preview && importId && (
          <>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
              {GROUPS.map((g) => (
                <div key={g} className="rounded-lg border border-border p-3" title={PREVIEW_LABEL[g]!.hint}>
                  <Badge tone={PREVIEW_LABEL[g]!.tone}>{PREVIEW_LABEL[g]!.label}</Badge>
                  <p className="tabular mt-1.5 text-xl font-semibold text-fg">{(pv[g] ?? 0).toLocaleString("en-IN")}</p>
                  {(pv[g] ?? 0) > 0 && (
                    <button type="button" className="mt-1 inline-flex items-center gap-1 text-[11.5px] text-info hover:underline" onClick={() => void downloadRows(importId, g, fileName)}>
                      <Download className="size-3" /> List
                    </button>
                  )}
                </div>
              ))}
            </div>
            <ul className="space-y-1 text-[12.5px] text-muted">
              {GROUPS.filter((g) => (pv[g] ?? 0) > 0).map((g) => <li key={g}><span className="font-medium text-fg">{PREVIEW_LABEL[g]!.label}:</span> {PREVIEW_LABEL[g]!.hint}</li>)}
            </ul>
            {Object.keys(preview.problems).length > 0 && (
              <p className="text-[12.5px] text-muted">Problems found: {Object.entries(preview.problems).map(([k, n]) => `${k} (${n})`).join(", ")}.</p>
            )}
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="w-full min-w-[640px] text-left text-[12.5px]">
                <caption className="px-3 py-2 text-left text-[12px] text-subtle">First {preview.sample.length} rows, those with problems first</caption>
                <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                  <tr>{["Row", "Name", "Phone", "Course", "Result", "Problems"].map((h) => <th key={h} scope="col" className="px-3 py-2 font-medium">{h}</th>)}</tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {preview.sample.map((r) => (
                    <tr key={r.row_no}>
                      <td className="tabular px-3 py-1.5 text-muted">{r.row_no}</td>
                      <td className="px-3 py-1.5 text-fg">{r.lead.full_name ?? "—"}</td>
                      <td className="tabular px-3 py-1.5 text-muted">{r.lead.phone ?? "—"}</td>
                      <td className="max-w-40 truncate px-3 py-1.5 text-muted">{r.lead.course ?? "—"}</td>
                      <td className="px-3 py-1.5">{r.preview && <Badge tone={PREVIEW_LABEL[r.preview]?.tone ?? "neutral"}>{PREVIEW_LABEL[r.preview]?.label ?? r.preview}</Badge>}
                        {r.existing_lead_id && <a href={`/leads?lead=${r.existing_lead_id}`} target="_blank" rel="noreferrer" className="ml-1.5 text-[11.5px] text-info hover:underline">#{r.existing_lead_id}</a>}</td>
                      <td className="px-3 py-1.5 text-[12px] text-warning">{r.problems.join(", ")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="flex flex-wrap justify-between gap-2">
              <div className="flex gap-2">
                <Button variant="secondary" onClick={() => setStep("courses")}><ArrowLeft className="size-4" /> Back</Button>
                <Button variant="secondary" onClick={() => void downloadRows(importId, null, fileName)}><Download className="size-4" /> Download every row</Button>
              </div>
              <Button onClick={() => setStep("confirm")} disabled={toWrite === 0}>Consent and routing <ArrowRight className="size-4" /></Button>
            </div>
          </>
        )}

        {step === "confirm" && preview && (
          <>
            <Notice tone="info">
              <span className="tabular font-medium">{toWrite.toLocaleString("en-IN")}</span> rows will be written ({pv.new ?? 0} new, {(pv.merge ?? 0) + (pv.duplicate_in_file ?? 0)} merged,{" "}
              {pv.reopen ?? 0} reopened, {pv.test ?? 0} test){skipped > 0 && <>; <span className="tabular">{skipped}</span> skipped (invalid or blocked phone)</>}. You can roll back the new leads for 24 hours if nothing has routed them.
            </Notice>
            <div className="grid gap-4 md:grid-cols-2">
              <label className="block space-y-1">
                <span className={label}>Source label</span>
                <input className={field} value={form.source_label} maxLength={60} placeholder="e.g. college_fair_oct" onChange={(e) => setForm({ ...form, source_label: e.target.value })} />
                <span className="text-xs text-muted">Shown as the lead source; used in reports.</span>
              </label>
              <label className="block space-y-1">
                <span className={label}>Campaign <span className="font-normal text-subtle">(optional)</span></span>
                <input className={field} value={form.campaign ?? ""} maxLength={120} onChange={(e) => setForm({ ...form, campaign: e.target.value })} />
                <span className="text-xs text-muted">Used where a row has no campaign of its own.</span>
              </label>
            </div>
            <fieldset className="space-y-3 rounded-lg border border-border p-4">
              <legend className="px-1 text-[13px] font-semibold text-fg">Consent basis</legend>
              <p className="text-[12.5px] text-muted">Every lead needs a record of how the student agreed to be contacted (spec B10). This is stored on each lead.</p>
              <div className="grid gap-4 md:grid-cols-[1fr_12rem]">
                <label className="block space-y-1">
                  <span className={label}>Where they agreed</span>
                  <input className={field} value={form.consent.where} maxLength={300} placeholder="e.g. sign-up sheet at the Delhi education fair"
                    onChange={(e) => setForm({ ...form, consent: { ...form.consent, where: e.target.value } })} />
                </label>
                <label className="block space-y-1">
                  <span className={label}>When</span>
                  <input type="date" className={field} value={form.consent.when} max={today} onChange={(e) => setForm({ ...form, consent: { ...form.consent, when: e.target.value } })} />
                </label>
              </div>
              <label className="block space-y-1">
                <span className={label}>The consent text they saw</span>
                <textarea className={area} value={form.consent.text} maxLength={2000} placeholder="e.g. I agree to be contacted by Eduwit and its partner universities about courses."
                  onChange={(e) => setForm({ ...form, consent: { ...form.consent, text: e.target.value } })} />
              </label>
              <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-[13px]">
                <label className="flex items-center gap-2 text-muted"><input type="checkbox" checked disabled className="accent-[var(--primary)]" /> Contact about courses</label>
                <label className="flex items-center gap-2"><input type="checkbox" checked={purposes.includes("partner_share")} className="accent-[var(--primary)]" onChange={(e) => togglePurpose("partner_share", e.target.checked)} /> Share with partner institutions</label>
                <label className="flex items-center gap-2"><input type="checkbox" checked={purposes.includes("marketing")} className="accent-[var(--primary)]" onChange={(e) => togglePurpose("marketing", e.target.checked)} /> Marketing messages</label>
              </div>
            </fieldset>
            <fieldset className="space-y-2">
              <legend className="mb-1 text-[13px] font-semibold text-fg">What happens to the leads</legend>
              {(Object.keys(ROUTE_CHOICE) as (keyof typeof ROUTE_CHOICE)[]).map((k) => (
                <label key={k} className={cn("flex cursor-pointer gap-3 rounded-lg border p-3", form.routing_choice === k ? "border-amber bg-amber/5" : "border-border hover:border-border-strong")}>
                  <input type="radio" name="routing" className="mt-0.5 accent-[var(--primary)]" checked={form.routing_choice === k} onChange={() => setForm({ ...form, routing_choice: k })} />
                  <span><span className="block text-[13px] font-medium text-fg">{ROUTE_CHOICE[k].label}</span><span className="block text-[12.5px] text-muted">{ROUTE_CHOICE[k].hint}</span></span>
                </label>
              ))}
              {form.routing_choice === "b2c" && (
                <label className="ml-7 block w-64 space-y-1">
                  <span className={label}>B2C lane</span>
                  <select className={field} value={form.b2c_lane} onChange={(e) => setForm({ ...form, b2c_lane: e.target.value as "sales" | "nurture" })}>
                    <option value="sales">Sales (call them now)</option><option value="nurture">Nurture (keep warm)</option>
                  </select>
                </label>
              )}
              {form.routing_choice === "route" && !purposes.includes("partner_share") && <Notice tone="warning">To route to partners the consent must cover sharing with partner institutions.</Notice>}
            </fieldset>
            <div className="flex justify-between gap-2">
              <Button variant="secondary" onClick={() => setStep("preview")} disabled={Boolean(busy)}><ArrowLeft className="size-4" /> Back</Button>
              <Button onClick={commit} disabled={Boolean(busy)}>{busy && <LoaderCircle className="size-4 animate-spin" />} Import {toWrite.toLocaleString("en-IN")} leads</Button>
            </div>
          </>
        )}

        {step === "run" && run && preview && (
          <>
            <div className="flex items-center gap-2 text-[13.5px] font-medium text-fg">
              {run.status === "done" || preview.import.status === "done" ? <Check className="size-4 text-success" /> : <LoaderCircle className="size-4 animate-spin text-muted" />}
              {preview.import.status === "done" ? `${preview.import.file_name}: imported` : preview.import.status === "rolled_back" ? `${preview.import.file_name}: rolled back` : `Importing ${preview.import.file_name}…`}
            </div>
            <Bar value={run.done} total={run.total} />
            {preview.import.status === "committing" && <p className="text-[12.5px] text-muted">You can leave this screen; the import carries on in the background (every minute).</p>}
            {preview.import.status === "done" && (
              <>
                <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
                  {(["created", "merged", "reopened", "imported", "skipped", "errors"] as const).map((k) => (
                    <div key={k} className="rounded-lg border border-border p-3">
                      <dt className="text-[12px] capitalize text-muted">{k}</dt>
                      <dd className={cn("tabular mt-0.5 text-xl font-semibold", k === "errors" && (preview.import.counts[k] ?? 0) > 0 ? "text-danger" : "text-fg")}>{preview.import.counts[k] ?? 0}</dd>
                    </div>
                  ))}
                </dl>
                {preview.import.routing_choice === "hold" && (
                  <Notice tone="info">The leads are held in the pre-routing pool. Release them when you are ready:{" "}
                    <button type="button" className="font-medium underline" onClick={async () => { const r = await releaseHeld(importId, null); if (r.ok) toast.success(`${r.data} leads released`); else toast.error(r.error); }}>release all now</button>.
                  </Notice>
                )}
              </>
            )}
            <div className="flex flex-wrap gap-2">
              {importId && <Button variant="secondary" onClick={() => void downloadRows(importId, null, preview.import.file_name)}><Download className="size-4" /> Download the result</Button>}
              <Button variant="secondary" onClick={reset}>Import another file</Button>
            </div>
          </>
        )}

        {busy && step !== "upload" && step !== "map" && <p className="flex items-center gap-2 text-[12.5px] text-muted"><LoaderCircle className="size-3.5 animate-spin" /> {busy}</p>}
      </div>
    </div>
  );
}
