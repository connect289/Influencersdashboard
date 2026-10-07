"use client";
import { useState, useTransition } from "react";
import { LoaderCircle, Send } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { DIM_LABEL, parseFormula, type CatalogueMetric } from "@/lib/analytics";
import { saveAlertSettings, saveMetric, saveMetricAlert, saveSchedule, setMetricAlertActive, setScheduleActive, testAlert } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";

function L({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return <label className="block space-y-1"><span className="text-[12px] text-muted">{label}</span>{children}{hint && <span className="block text-[11.5px] text-subtle">{hint}</span>}</label>;
}
function useSubmit() {
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const run = (fn: () => Promise<string | void>, ok: string, after?: () => void) => start(async () => {
    const err = await fn();
    if (err) { setError(err); return; }
    setError(null); toast.success(ok); after?.();
  });
  return { busy, error, run };
}
function Footer({ busy, error, label }: { busy: boolean; error: string | null; label: string }) {
  return (
    <div className="flex items-center justify-end gap-3">
      {error && <span role="alert" className="mr-auto text-[13px] text-danger">{error}</span>}
      <Button type="submit" size="sm" disabled={busy}>{busy && <LoaderCircle className="size-3.5 animate-spin" />} {label}</Button>
    </div>
  );
}

export function MetricForm({ metrics }: { metrics: CatalogueMetric[] }) {
  const system = metrics.filter((m) => !m.calculated);
  const [formula, setFormula] = useState("");
  const parsed = formula ? parseFormula(formula, new Set(system.map((m) => m.key))) : null;
  const { busy, error, run } = useSubmit();
  return (
    <form className="space-y-3" onSubmit={(e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget);
      run(() => saveMetric({ key: String(f.get("key")), label: String(f.get("label")), unit: String(f.get("unit")), formula, higher_is_better: f.get("hib") === "on",
                             description: String(f.get("description") ?? "") }, system.map((m) => m.key)), "Metric saved");
    }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <L label="Name"><input name="label" maxLength={80} placeholder="Commission per attempt" className={field} /></L>
        <L label="Key" hint="lower-case, digits and _"><input name="key" maxLength={60} placeholder="commission_per_attempt" className={field} /></L>
        <L label="Unit">
          <select name="unit" className={field} defaultValue="number">
            <option value="number">Number</option><option value="inr">Rupees</option><option value="pct">Percent</option><option value="count">Count</option>
            <option value="hours">Hours</option><option value="days">Days</option><option value="minutes">Minutes</option><option value="usd">US dollars</option>
          </select>
        </L>
      </div>
      <L label="Formula" hint="Metric keys with + − × ÷ and brackets, e.g. commission_realised / allocations. Breakdowns work when the metrics share them.">
        <input value={formula} onChange={(e) => setFormula(e.target.value)} className={`${field} font-mono`} placeholder="commission_realised / allocations" />
      </L>
      {typeof parsed === "string" && <p className="text-[12px] text-warning">{parsed}</p>}
      <details className="text-[12px] text-muted"><summary className="cursor-pointer">Metric keys</summary>
        <p className="mt-1 font-mono leading-6">{system.map((m) => m.key).join(" · ")}</p></details>
      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto]">
        <L label="Description (optional)"><input name="description" maxLength={300} className={field} /></L>
        <label className="flex items-end gap-2 pb-2 text-[13px]"><input type="checkbox" name="hib" defaultChecked className="size-4 accent-[var(--primary)]" /> Higher is better</label>
      </div>
      <Footer busy={busy} error={error} label="Save metric" />
    </form>
  );
}

export function AlertSettingsForm({ s, emailReady }: { s: { enabled: boolean; emails: string[]; whatsapp_numbers: string[]; whatsapp_template: string | null; digest_minutes: number }; emailReady: boolean }) {
  const { busy, error, run } = useSubmit();
  const [testing, startTest] = useTransition();
  return (
    <form className="space-y-3" onSubmit={(e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget);
      run(() => saveAlertSettings({ enabled: f.get("enabled") === "on", emails: String(f.get("emails")), whatsapp_numbers: String(f.get("wa")), whatsapp_template: String(f.get("tpl")),
                                    digest_minutes: Number(f.get("digest")) || 15, reason: String(f.get("reason")) }), "Alert settings saved");
    }}>
      <label className="flex items-start gap-2 text-[13px]"><input type="checkbox" name="enabled" defaultChecked={s.enabled} className="mt-0.5 size-4 accent-[var(--primary)]" />
        <span><span className="font-medium text-fg">Send alerts and reports</span><span className="block text-[12px] text-muted">While off, messages are queued and logged but not sent.
          {!emailReady && " The e-mail provider is not set up yet (Notifications → Providers)."}</span></span></label>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="E-mail recipients" hint="Up to 10, separated by commas."><input name="emails" defaultValue={s.emails.join(", ")} className={field} /></L>
        <L label="WhatsApp numbers" hint="Up to 5, with country code (e.g. 9198…)."><input name="wa" defaultValue={s.whatsapp_numbers.join(", ")} className={field} /></L>
        <L label="WhatsApp template" hint="A Meta-approved template with one body variable; empty: e-mail only."><input name="tpl" defaultValue={s.whatsapp_template ?? ""} className={field} /></L>
        <L label="Alert digest every (minutes)"><input name="digest" type="number" min={5} max={1440} defaultValue={s.digest_minutes} className={field} /></L>
      </div>
      <L label="Reason"><input name="reason" maxLength={300} className={field} /></L>
      <div className="flex items-center gap-2">
        <Button size="sm" variant="secondary" disabled={testing} onClick={() => startTest(async () => {
          const err = await testAlert();
          if (err) toast.error(err); else toast.success(s.enabled ? "Test queued" : "Test queued: it is sent only while 'Send alerts and reports' is on");
        })}>
          <Send className="size-3.5" /> Send a test
        </Button>
        <div className="flex-1"><Footer busy={busy} error={error} label="Save" /></div>
      </div>
    </form>
  );
}

export function MetricAlertForm({ metrics }: { metrics: CatalogueMetric[] }) {
  const [metric, setMetric] = useState(metrics[0]?.key ?? "");
  const m = metrics.find((x) => x.key === metric);
  const [fdim, setFdim] = useState("");
  const [vol, setVol] = useState("");
  const counts = metrics.filter((x) => x.unit === "count" && !x.calculated && (!m?.fact || x.fact === m.fact));
  const { busy, error, run } = useSubmit();
  return (
    <form className="space-y-3" onSubmit={(e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget);
      const rawStr = String(f.get("threshold") ?? "").trim(); if (rawStr === "") return; const raw = Number(rawStr);
      const threshold = m?.unit === "pct" ? raw / 100 : raw;
      const vals = String(f.get("fval") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
      run(() => saveMetricAlert({ name: String(f.get("name")), metric, op: String(f.get("op")), threshold, window_hours: Number(f.get("window")) || 24,
                                  filters: fdim && vals.length ? { [fdim]: vals } : {}, channels: ["email", ...(f.get("wa") === "on" ? ["whatsapp"] : [])],
                                  cooldown_hours: Number(f.get("cooldown")) || 24,
                                  min_volume: vol ? Math.max(0, Math.trunc(Number(f.get("minvol")) || 0)) : 0, volume_metric: vol || null }),
          "Alert saved", () => { (e.target as HTMLFormElement).reset(); setVol(""); });
    }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Name"><input name="name" maxLength={80} placeholder="Duplicate rate above 20%" className={field} /></L>
        <L label="Metric"><select value={metric} onChange={(e) => { setMetric(e.target.value); setVol(""); }} className={field}>{metrics.map((x) => <option key={x.key} value={x.key}>{x.area}: {x.label}</option>)}</select></L>
      </div>
      <div className="grid gap-3 sm:grid-cols-4">
        <L label="When it is"><select name="op" className={field}><option value=">">above</option><option value=">=">at or above</option><option value="<">below</option><option value="<=">at or below</option></select></L>
        <L label={`Threshold${m?.unit === "pct" ? " (%)" : m?.unit === "inr" ? " (₹)" : ""}`}><input name="threshold" type="number" step="any" required className={field} /></L>
        <L label="Over the last (hours)"><input name="window" type="number" min={1} max={2160} defaultValue={24} className={field} /></L>
        <L label="Then wait (hours)"><input name="cooldown" type="number" min={1} max={720} defaultValue={24} className={field} /></L>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Only for (optional)">
          <select value={fdim} onChange={(e) => setFdim(e.target.value)} className={field}><option value="">Everything</option>{(m?.dims ?? []).filter((d) => !["day", "week", "month"].includes(d)).map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}</select>
        </L>
        <L label="Values" hint={fdim === "partner" ? "Partner IDs, comma-separated" : "Comma-separated"}><input name="fval" disabled={!fdim} className={field} /></L>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Only when at least" hint="e.g. 20 leads routed in the window"><input name="minvol" type="number" min={1} step={1} disabled={!vol} required={!!vol} className={field} /></L>
        <L label="Counted as"><select value={vol} onChange={(e) => setVol(e.target.value)} className={field}><option value="">No minimum</option>{counts.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}</select></L>
      </div>
      <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" name="wa" className="size-4 accent-[var(--primary)]" /> Also on WhatsApp</label>
      <Footer busy={busy} error={error} label="Add alert" />
    </form>
  );
}

export function ScheduleForm({ dashboards, reports, preset }: { dashboards: { id: number; name: string }[]; reports: { id: number; name: string }[]; preset?: string }) {
  const [freq, setFreq] = useState("weekly");
  const { busy, error, run } = useSubmit();
  return (
    <form className="space-y-3" onSubmit={(e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget);
      const what = String(f.get("what"));
      run(() => saveSchedule({ name: String(f.get("name")), dashboard_id: what.startsWith("d:") ? Number(what.slice(2)) : null, report_id: what.startsWith("r:") ? Number(what.slice(2)) : null,
                               frequency: freq, hour_ist: Number(f.get("hour")), weekday: freq === "weekly" ? Number(f.get("weekday")) : null,
                               monthday: freq === "monthly" ? Number(f.get("monthday")) : null, recipients: String(f.get("to")) }), "Schedule saved", () => (e.target as HTMLFormElement).reset());
    }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Name"><input name="name" maxLength={80} placeholder="Monday partner review" className={field} /></L>
        <L label="Send">
          <select name="what" defaultValue={preset} className={field}>
            <optgroup label="Dashboards">{dashboards.map((d) => <option key={d.id} value={`d:${d.id}`}>{d.name}</option>)}</optgroup>
            {reports.length > 0 && <optgroup label="Reports">{reports.map((r) => <option key={r.id} value={`r:${r.id}`}>{r.name}</option>)}</optgroup>}
          </select>
        </L>
      </div>
      <div className="grid gap-3 sm:grid-cols-4">
        <L label="How often"><select value={freq} onChange={(e) => setFreq(e.target.value)} className={field}><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option></select></L>
        {freq === "weekly" && <L label="On"><select name="weekday" className={field}>{["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map((d, i) => <option key={d} value={i + 1}>{d}</option>)}</select></L>}
        {freq === "monthly" && <L label="Day of the month"><input name="monthday" type="number" min={1} max={28} defaultValue={1} required className={field} /></L>}
        <L label="At (IST)"><select name="hour" defaultValue={9} className={field}>{Array.from({ length: 24 }, (_, h) => <option key={h} value={h}>{String(h).padStart(2, "0")}:00</option>)}</select></L>
      </div>
      <L label="To" hint="E-mail addresses, comma-separated (up to 20). Every widget's numbers in the e-mail; breakdowns attached as CSV."><input name="to" className={field} /></L>
      <Footer busy={busy} error={error} label="Add schedule" />
    </form>
  );
}

export function ActiveToggle({ kind, id, active }: { kind: "alert" | "schedule"; id: number; active: boolean }) {
  const [busy, start] = useTransition();
  return <Button size="sm" variant="secondary" disabled={busy} onClick={() => start(async () => {
    const err = await (kind === "alert" ? setMetricAlertActive(id, !active) : setScheduleActive(id, !active));
    if (err) toast.error(err); else toast.success(active ? "Switched off" : "Switched on"); })}>{active ? "Turn off" : "Turn on"}</Button>;
}
