"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { FileUp, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Label, field } from "@/components/ui/Modal";
import { Notice } from "@/components/ui/Notice";
import { parseCsvRows, tableFromRows, type Cell, type FileTable } from "@/lib/intake";
import { STATEMENT_FIELDS, statementRows, suggestStatementMapping, type StatementField } from "@/lib/money";
import { importStatement } from "./actions";

async function readTable(f: File): Promise<FileTable> {
  const lower = f.name.toLowerCase();
  if (f.size > 10 * 1024 * 1024) throw new Error("The file is over 10 MB.");
  if (lower.endsWith(".xls")) throw new Error("Old .xls files cannot be read. Save it as .xlsx or CSV.");
  if (lower.endsWith(".xlsx")) {
    const { default: readXlsxFile } = await import("read-excel-file/browser");
    const sheets = await readXlsxFile(f);
    const best = sheets.reduce((a, b) => ((b.data?.length ?? 0) > (a.data?.length ?? 0) ? b : a), sheets[0]!);
    return tableFromRows(best.data as Cell[][]);
  }
  if (lower.endsWith(".csv") || f.type === "text/csv") return tableFromRows(parseCsvRows(await f.text(), 5100));
  throw new Error("Choose an Excel (.xlsx) or CSV file.");
}

/** Upload → pick the columns → the server matches each row and sorts it into piles. */
export function StatementUpload({ partners }: { partners: { id: number; name: string }[] }) {
  const router = useRouter();
  const [partner, setPartner] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [file, setFile] = useState<{ name: string; table: FileTable } | null>(null);
  const [map, setMap] = useState<Partial<Record<StatementField, string>>>({});
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const pick = async (f: File | undefined) => {
    setError(null); setFile(null);
    if (!f) return;
    try {
      const table = await readTable(f);
      if (table.rows.length === 0) throw new Error("No rows under the header row.");
      setFile({ name: f.name, table }); setMap(suggestStatementMapping(table.headers));
    } catch (e) { setError(e instanceof Error ? e.message : "Could not read the file."); }
  };
  const rows = file ? statementRows(file.table.rows, map) : [];
  const keyed = Boolean(map.reference || map.record_id || map.phone || map.name);
  const submit = async () => {
    if (!file) return;
    setPending(true); setError(null);
    try {
      const r = await importStatement({ partner_id: Number(partner), period_from: from, period_to: to, file_name: file.name, rows });
      if (!r.ok) { setError(r.error); return; }
      toast.success("Statement reconciled");
      router.push(`/money/statements/${r.data.statement.id}`);
    } finally { setPending(false); }
  };

  return (
    <div className="space-y-4 px-5 py-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <Label text="Partner">
          <select className={field} value={partner} onChange={(e) => setPartner(e.target.value)}>
            <option value="" disabled>Choose…</option>
            {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Label>
        <Label text="Period from"><input type="date" className={field} value={from} onChange={(e) => setFrom(e.target.value)} /></Label>
        <Label text="to"><input type="date" className={field} value={to} min={from} onChange={(e) => setTo(e.target.value)} /></Label>
      </div>
      <label className="flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-dashed border-border-strong px-4 py-5 text-[13px] text-muted hover:bg-surface-hover/60">
        <FileUp className="size-4" /> {file ? <span className="text-fg">{file.name} · {file.table.rows.length} rows</span> : "Choose the statement (.xlsx or CSV, up to 5,000 rows)"}
        <input type="file" accept=".xlsx,.csv,text/csv" className="sr-only" onChange={(e) => pick(e.target.files?.[0])} />
      </label>
      {file && (
        <div className="space-y-2">
          <p className="text-[12.5px] font-medium text-fg">Which column is which</p>
          <div className="grid gap-2 sm:grid-cols-2">
            {STATEMENT_FIELDS.map((fd) => (
              <label key={fd.key} className="flex items-center gap-2 text-[12.5px]">
                <span className="w-36 shrink-0 text-muted">{fd.label}</span>
                <select className={field} value={map[fd.key] ?? ""} onChange={(e) => setMap({ ...map, [fd.key]: e.target.value || undefined })}>
                  <option value="">Not in the file</option>
                  {file.table.headers.map((h) => <option key={h} value={h}>{h}</option>)}
                </select>
              </label>
            ))}
          </div>
          <p className="text-[12px] text-muted">{rows.length} rows to match{file.table.rows.length > rows.length ? ` (${file.table.rows.length - rows.length} without a reference, ID, phone or name are skipped, e.g. totals)` : ""}.
            The amount is compared with Eduwit&apos;s commission net of GST and with GST.</p>
        </div>
      )}
      {error && <Notice tone="error">{error}</Notice>}
      <Button size="sm" onClick={submit} disabled={pending || !file || !partner || !from || !to || !keyed || rows.length === 0}>
        {pending && <LoaderCircle className="size-3.5 animate-spin" />} Reconcile
      </Button>
    </div>
  );
}
