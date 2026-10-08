"use client";
import { useMemo, useState } from "react";
import Link from "next/link";
import { Check, CircleDashed, LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, CardHeader } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { formatDateTime } from "@/lib/format";
import {
  ATTRIBUTION_LIST_FIELDS, STAGES, STAGE_LABEL, STRENGTH_LABEL, VALUE_STAGES, attributionDefaults, attributionProblems, formatInr, settingsProblems, valuesProblems,
  type AttributionForm, type AttributionListField, type CapiAttribution, type CapiOverview, type GoogleMap, type MetaMap, type SignalValues, type ValueStage,
} from "@/lib/capi";
import { saveAttributionSettings, saveCapiSettings } from "./actions";

const base = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const area = "w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const label = "text-[13px] font-medium text-fg";

const IsSet = ({ on }: { on: boolean }) => on ? <Badge tone="success"><Check className="size-3" /> Set</Badge> : <Badge><CircleDashed className="size-3" /> Not set</Badge>;

function Text({ id, l, value, onChange, error, hint, placeholder, mono }: { id: string; l: string; value: string; onChange: (v: string) => void; error?: string; hint?: string; placeholder?: string; mono?: boolean }) {
  return (
    <label htmlFor={id} className="block space-y-1">
      <span className={label}>{l}</span>
      <input id={id} className={cn(base, mono && "font-mono text-[12.5px]")} value={value} placeholder={placeholder} aria-invalid={Boolean(error)} onChange={(e) => onChange(e.target.value)} />
      {error ? <span className="block text-xs text-danger">{error}</span> : hint && <span className="block text-xs text-muted">{hint}</span>}
    </label>
  );
}

function Secret({ id, l, value, onChange, on, hint }: { id: string; l: string; value: string; onChange: (v: string) => void; on: boolean; hint: string }) {
  return (
    <label htmlFor={id} className="block space-y-1">
      <span className={cn(label, "flex items-center justify-between gap-2")}>{l} <IsSet on={on} /></span>
      <input id={id} type="password" autoComplete="off" className={base} value={value} placeholder={on ? "Leave empty to keep the current one" : ""} onChange={(e) => onChange(e.target.value)} />
      <span className="block text-xs text-muted">{hint}</span>
    </label>
  );
}

const pct = (n: number) => String(Math.round(n * 1000) / 10);

function Strength({ st }: { st: (typeof STAGES)[number] }) {
  const k = STAGE_LABEL[st].strength;
  return k ? <Badge tone={k === "strongest" ? "success" : k === "strong" ? "info" : "neutral"} className="ml-1.5 align-middle">{STRENGTH_LABEL[k]}</Badge> : null;
}

// ---------- Attribution: what counts as a paid lead (Addendum 3, D38; b2b.attribution_settings_save) ----------

const ATTRIBUTION_FIELD: Record<AttributionListField, { label: string; hint: string; placeholder: string; mono?: boolean }> = {
  influencer_lead_sources: {
    label: "Influencer or referral lead sources",
    hint: "Lead sources (the lead's own, or a touchpoint's) that mean an influencer or a referral brought the student. A referral code on the lead counts on its own.",
    placeholder: "influencer, referral, affiliate",
  },
  influencer_utm_values: {
    label: "Influencer or referral UTM values",
    hint: "utm_source or utm_medium values that mean the same.",
    placeholder: "influencer, referral, affiliate",
  },
  exclude_campaigns: {
    label: "Campaigns never paid",
    hint: "A campaign whose name contains one of these is never paid, whatever the click carries: for example a brand or retargeting campaign you do not want reported.",
    placeholder: "brand-awareness, retargeting",
  },
  meta_ad_params: {
    label: "Meta ad parameters",
    hint: "A Meta click (fbclid, or the fbc cookie) is paid only when the click data or landing URL also carries one of these. Lower-case letters, digits and underscores.",
    placeholder: "ad_id, adset_id, campaign_id, utm_id, fb_ad_id",
    mono: true,
  },
};

/** The 'attribution' setting, saved on its own with a reason (a new version each time). Mounted with key={a.version} so a save
 *  re-reads the stored, normalised lists. */
function AttributionCard({ a }: { a: CapiAttribution }) {
  const [f, setF] = useState<AttributionForm>({ ...attributionDefaults(a.value), reason: "" });
  const [tried, setTried] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const errors = useMemo(() => attributionProblems(f), [f]);
  const reasonError = tried ? errors.reason : undefined;

  const save = async () => {
    setTried(true);
    if (Object.keys(errors).length) { setError("Check the highlighted fields."); return; }
    setPending(true); setError(null);
    try {
      const r = await saveAttributionSettings(f);
      if (!r.ok) { setError(r.error); return; }
      toast.success(r.version ? `Attribution saved as version ${r.version}` : "Attribution saved");
      setF((x) => ({ ...x, reason: "" })); setTried(false);
    } finally { setPending(false); }
  };

  return (
    <Card id="attribution" className="min-w-0 scroll-mt-6">
      <CardHeader title="Attribution: what counts as a paid lead"
        description="One definition for the whole CRM (Addendum 3): the paid label on leads and hand-offs, this screen's campaigns and the analytics. Paid changes no routing." />
      <div className="space-y-5 p-5">
        <div className="grid gap-3 text-[12.5px] md:grid-cols-2">
          <div className="rounded-lg border border-border p-3">
            <p className="mb-1 font-medium text-fg">Paid: a Meta or Google ad brought the lead</p>
            <ul className="list-disc space-y-0.5 pl-4 text-muted">
              <li>a Meta lead form that Meta does not mark organic</li>
              <li>a Google Ads lead form</li>
              <li>a Google click ID: gclid, gbraid or wbraid</li>
              <li>a Meta click (fbclid or fbc) together with one of the Meta ad parameters below</li>
              <li>a Meta click-to-WhatsApp ad (ctwa_clid, or Witty&apos;s ad referral)</li>
            </ul>
          </div>
          <div className="rounded-lg border border-border p-3">
            <p className="mb-1 font-medium text-fg">Not paid</p>
            <ul className="list-disc space-y-0.5 pl-4 text-muted">
              <li>an influencer or referral marker, always, whatever else the lead carries</li>
              <li>a campaign on the never-paid list</li>
              <li>UTM tags only (utm_medium cpc, paid_social and the like no longer count)</li>
              <li>organic forms, and every other source</li>
            </ul>
          </div>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          {ATTRIBUTION_LIST_FIELDS.map((k) => {
            const d = ATTRIBUTION_FIELD[k];
            const err = errors[k];
            return (
              <label key={k} htmlFor={`a-${k}`} className="block space-y-1">
                <span className={label}>{d.label}</span>
                <textarea id={`a-${k}`} rows={2} className={cn(area, d.mono && "font-mono text-[12.5px]")} value={f[k]} placeholder={d.placeholder} spellCheck={false}
                  aria-invalid={Boolean(err)} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
                {err ? <span className="block text-xs text-danger">{err}</span>
                  : <span className="block text-xs text-muted">{d.hint} Comma- or line-separated, up to 50; saved in lower case.</span>}
              </label>
            );
          })}
        </div>
        <div className="flex flex-wrap items-end gap-3 border-t border-border pt-4">
          <label htmlFor="a-reason" className="block min-w-0 flex-1 basis-72 space-y-1">
            <span className={label}>Reason for the change</span>
            <input id="a-reason" className={base} value={f.reason} placeholder="e.g. new influencer code for the October campaign" aria-invalid={Boolean(reasonError)}
              onChange={(e) => setF({ ...f, reason: e.target.value })} />
            {reasonError ? <span className="block text-xs text-danger">{reasonError}</span>
              : <span className="block text-xs text-muted">
                  {a.version ? `Version ${a.version}` : "Not saved yet"}{a.updated_at && <> · last change {formatDateTime(a.updated_at)}</>}. Every save is a new version with your reason.
                </span>}
          </label>
          {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
          <Button onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-4 animate-spin" />} Save attribution</Button>
        </div>
      </div>
    </Card>
  );
}

// ---------- the CAPI setup (accounts, credentials, milestone maps, signal values) ----------

export function SetupForm({ s, v, a }: { s: CapiOverview["settings"]; v: SignalValues; a: CapiAttribution }) {
  const [consent, setConsent] = useState(s.consent);
  const [vals, setVals] = useState({ pct: { applied: pct(v.values.applied), interested: pct(v.values.interested), qualified: pct(v.values.qualified) } as Record<ValueStage, string>,
                                     base: String(v.base_value_inr) });
  const [meta, setMeta] = useState({ dataset_id: s.meta.dataset_id ?? "", api_version: s.meta.api_version ?? "v21.0", test_event_code: s.meta.test_event_code ?? "", token: "" });
  const [metaMap, setMetaMap] = useState<MetaMap>(s.meta.map);
  const [google, setGoogle] = useState({ customer_id: s.google.customer_id ?? "", login_customer_id: s.google.login_customer_id ?? "", api_version: s.google.api_version ?? "v21",
                                          client_id: s.google.client_id ?? "", client_secret: "", refresh_token: "", developer_token: "" });
  const [googleMap, setGoogleMap] = useState<GoogleMap>(s.google.map);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const errors = useMemo(() => ({ ...settingsProblems({ meta: { ...meta, map: metaMap }, google: { ...google, map: googleMap } }), ...valuesProblems(vals) }),
                         [meta, metaMap, google, googleMap, vals]);
  const baseInr = Number(vals.base) || 0;

  const save = async () => {
    if (Object.keys(errors).length) { setError("Check the highlighted fields."); return; }
    setPending(true); setError(null);
    try {
      const values = Object.fromEntries(VALUE_STAGES.map((k) => [k, Number(vals.pct[k]) / 100])) as Record<ValueStage, number>;
      const e = await saveCapiSettings({ consent, meta: { ...meta, map: metaMap }, google: { ...google, map: googleMap }, values, base_value_inr: Number(vals.base) });
      if (e) setError(e);
      else { toast.success("Saved"); setMeta((m) => ({ ...m, token: "" })); setGoogle((g) => ({ ...g, client_secret: "", refresh_token: "", developer_token: "" })); }
    } finally { setPending(false); }
  };

  return (
    <div className="space-y-6">
      <Card className="min-w-0">
        <CardHeader title="Setup" description="Accounts, credentials and which milestones each platform receives. Credentials are stored in the database vault and never shown again." />
        <div className="divide-y divide-border">
          <section className="space-y-3 p-5">
            <h3 className="text-[13.5px] font-semibold text-fg">Consent</h3>
            <p className="text-[12.5px] text-muted">A student&apos;s milestones are reported to the ad platforms only if they gave this consent. Others are logged as skipped and go if the consent arrives later.</p>
            <div className="flex flex-wrap gap-2">
              {([["marketing", "Marketing consent", "Safest: they agreed to marketing, which covers ad measurement."],
                 ["sales", "Contact consent", "Every student who agreed to be contacted about courses."]] as const).map(([k, l, h]) => (
                <label key={k} className={cn("flex max-w-sm flex-1 basis-64 cursor-pointer gap-3 rounded-lg border p-3", consent === k ? "border-amber bg-amber/5" : "border-border hover:border-border-strong")}>
                  <input type="radio" name="consent" className="mt-0.5 accent-[var(--primary)]" checked={consent === k} onChange={() => setConsent(k)} />
                  <span><span className="block text-[13px] font-medium text-fg">{l}</span><span className="block text-[12px] text-muted">{h}</span></span>
                </label>
              ))}
            </div>
            <p className="text-[12px] text-muted">The &ldquo;disqualified&rdquo; signal for junk is {s.junk_signal ? "on" : "off"}; change it under <Link href="/routing?tab=handoff" className="text-info hover:underline">Routing → Hand-off rules</Link>.</p>
          </section>

          <section className="space-y-4 p-5">
            <h3 className="text-[13.5px] font-semibold text-fg">Signals and their value</h3>
            <p className="text-[12.5px] text-muted">Only leads a <span className="font-medium text-fg">paid</span> Meta or Google ad brought are reported (what counts as paid: the <a href="#attribution" className="text-info hover:underline">Attribution card</a> below),
              and only to the platform whose ad brought them, tagged with the campaign. Each lead tells the platform how far it got, strongest first: <span className="text-fg">enrolled → applicant → interested → qualified</span>.
              The value tells the platform how much each step is worth, so it bids for students who enrol rather than for form fills.</p>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <label htmlFor="v-base" className="block space-y-1">
                <span className={label}>Commission per enrolment (₹)</span>
                <input id="v-base" inputMode="numeric" className={cn(base, "tabular")} value={vals.base} aria-invalid={Boolean(errors.base)}
                  onChange={(e) => setVals({ ...vals, base: e.target.value.replace(/[^\d.]/g, "") })} />
                {errors.base ? <span className="block text-xs text-danger">{errors.base}</span>
                  : <span className="block text-xs text-muted">Used when a lead has no expected commission from its allocation.</span>}
              </label>
              {VALUE_STAGES.map((k) => (
                <label key={k} htmlFor={`v-${k}`} className="block space-y-1">
                  <span className={label}>{STAGE_LABEL[k].label} <Strength st={k} /></span>
                  <span className="relative block">
                    <input id={`v-${k}`} inputMode="decimal" className={cn(base, "tabular pr-24")} value={vals.pct[k]} aria-invalid={Boolean(errors[`values.${k}`])}
                      onChange={(e) => setVals({ ...vals, pct: { ...vals.pct, [k]: e.target.value.replace(/[^\d.]/g, "") } })} />
                    <span className="pointer-events-none absolute inset-y-0 right-3 flex items-center text-[12px] text-muted">% · {formatInr((Number(vals.pct[k]) || 0) / 100 * baseInr)}</span>
                  </span>
                  {errors[`values.${k}`] ? <span className="block text-xs text-danger">{errors[`values.${k}`]}</span>
                    : <span className="block text-xs text-muted">of the lead&apos;s expected commission</span>}
                </label>
              ))}
            </div>
            {errors.order && <p className="text-[12px] text-warning">{errors.order}</p>}
            <p className="text-[12px] text-muted">Enrolled carries the expected commission itself, and Enrolment verified the realised one.
              Example at {formatInr(baseInr)}: qualified {formatInr((Number(vals.pct.qualified) || 0) / 100 * baseInr)}, interested {formatInr((Number(vals.pct.interested) || 0) / 100 * baseInr)},
              applicant {formatInr((Number(vals.pct.applied) || 0) / 100 * baseInr)}, enrolled {formatInr(baseInr)}.
              Qualified counts from the lead&apos;s class (an engine decision, a partner-sharing consent request or a partner allocation), not from a nurture hand-off.</p>
          </section>

          <section className="space-y-4 p-5">
            <h3 className="text-[13.5px] font-semibold text-fg">Meta Conversions API</h3>
            <p className="text-[12.5px] text-muted">In Events Manager, use the dataset (pixel) your lead forms and website report to, and generate a Conversions API access token there.
              A test event code sends everything to the Test events tab only; clear it to go for real.</p>
            <div className="grid gap-4 md:grid-cols-2">
              <Text id="m-ds" l="Dataset (pixel) ID" value={meta.dataset_id} onChange={(v) => setMeta({ ...meta, dataset_id: v })} error={errors["meta.dataset_id"]} placeholder="e.g. 123456789012345" mono />
              <Secret id="m-tok" l="Access token" value={meta.token} onChange={(v) => setMeta({ ...meta, token: v })} on={s.meta.token} hint="Generated in Events Manager → Settings → Conversions API." />
              <Text id="m-test" l="Test event code (optional)" value={meta.test_event_code} onChange={(v) => setMeta({ ...meta, test_event_code: v })} placeholder="e.g. TEST12345" mono
                hint={meta.test_event_code ? "Events go to Test events only." : "Empty: events count for real."} />
              <Text id="m-ver" l="Graph API version" value={meta.api_version} onChange={(v) => setMeta({ ...meta, api_version: v })} error={errors["meta.api_version"]} mono />
            </div>
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="w-full min-w-[560px] text-left text-[12.5px]">
                <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                  <tr><th scope="col" className="w-12 px-3 py-2 font-medium">Send</th><th scope="col" className="px-3 py-2 font-medium">Milestone</th><th scope="col" className="w-64 px-3 py-2 font-medium">Meta event name</th></tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {STAGES.map((st) => (
                    <tr key={st} className={metaMap[st]?.enabled ? undefined : "text-muted"}>
                      <td className="px-3 py-2"><input type="checkbox" aria-label={`Send ${STAGE_LABEL[st].label} to Meta`} className="accent-[var(--primary)]" checked={metaMap[st]?.enabled ?? false}
                        onChange={(e) => setMetaMap({ ...metaMap, [st]: { ...metaMap[st], enabled: e.target.checked } })} /></td>
                      <td className="px-3 py-2"><span className="font-medium text-fg">{STAGE_LABEL[st].label}</span><Strength st={st} /><span className="block text-[11.5px] text-subtle">{STAGE_LABEL[st].hint}</span></td>
                      <td className="px-3 py-1.5">
                        <input className={cn(base, "h-8")} value={metaMap[st]?.event ?? ""} aria-label={`Meta event for ${STAGE_LABEL[st].label}`} aria-invalid={Boolean(errors[`meta.map.${st}`])}
                          onChange={(e) => setMetaMap({ ...metaMap, [st]: { ...metaMap[st], event: e.target.value } })} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="text-[12px] text-muted">For Meta&apos;s conversion-leads optimisation, use the same names as the stages set up in Events Manager → your CRM integration,
              and optimise the campaigns for the strongest signal that gets enough events (about 50 a week): applicant or interested at first, enrolled once volume allows.</p>
          </section>

          <section className="space-y-4 p-5">
            <h3 className="text-[13.5px] font-semibold text-fg">Google Ads offline conversions</h3>
            <p className="text-[12.5px] text-muted">Conversions are uploaded with the click ID (gclid, gbraid or wbraid), plus hashed email and phone for enhanced conversions for leads.
              Create one &ldquo;Import → CRMs, files or other data sources&rdquo; conversion action per signal (Qualified lead, Interested, Applicant, Enrolled) and paste its resource name below.
              Make Enrolled (or Applicant) the primary action for bidding and keep the earlier ones secondary.</p>
            {s.google.token_error && <Notice tone="error">{s.google.token_error}</Notice>}
            <div className="grid gap-4 md:grid-cols-2">
              <Text id="g-cid" l="Customer ID" value={google.customer_id} onChange={(v) => setGoogle({ ...google, customer_id: v })} error={errors["google.customer_id"]} placeholder="123-456-7890" mono />
              <Text id="g-mcc" l="Manager account ID (optional)" value={google.login_customer_id} onChange={(v) => setGoogle({ ...google, login_customer_id: v })} error={errors["google.login_customer_id"]}
                hint="Only if access is through a manager (MCC) account." placeholder="123-456-7890" mono />
              <Secret id="g-dev" l="Developer token" value={google.developer_token} onChange={(v) => setGoogle({ ...google, developer_token: v })} on={s.google.developer_token} hint="Google Ads → Tools → API Center (basic access or higher)." />
              <Text id="g-client" l="OAuth client ID" value={google.client_id} onChange={(v) => setGoogle({ ...google, client_id: v })} placeholder="…apps.googleusercontent.com" mono />
              <Secret id="g-sec" l="OAuth client secret" value={google.client_secret} onChange={(v) => setGoogle({ ...google, client_secret: v })} on={s.google.client_secret} hint="From the Google Cloud OAuth client." />
              <Secret id="g-ref" l="Refresh token" value={google.refresh_token} onChange={(v) => setGoogle({ ...google, refresh_token: v })} on={s.google.refresh_token} hint="For a user with access to the Ads account, scope adwords." />
              <Text id="g-ver" l="Google Ads API version" value={google.api_version} onChange={(v) => setGoogle({ ...google, api_version: v })} error={errors["google.api_version"]} mono />
            </div>
            <div className="overflow-x-auto rounded-lg border border-border">
              <table className="w-full min-w-[620px] text-left text-[12.5px]">
                <thead className="bg-surface-2/60 text-[11px] uppercase tracking-wider text-subtle">
                  <tr><th scope="col" className="w-12 px-3 py-2 font-medium">Send</th><th scope="col" className="px-3 py-2 font-medium">Milestone</th><th scope="col" className="w-96 px-3 py-2 font-medium">Conversion action</th></tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {STAGES.map((st) => (
                    <tr key={st} className={googleMap[st]?.enabled ? undefined : "text-muted"}>
                      <td className="px-3 py-2"><input type="checkbox" aria-label={`Send ${STAGE_LABEL[st].label} to Google`} className="accent-[var(--primary)]" checked={googleMap[st]?.enabled ?? false}
                        onChange={(e) => setGoogleMap({ ...googleMap, [st]: { ...googleMap[st], enabled: e.target.checked } })} /></td>
                      <td className="px-3 py-2 font-medium text-fg">{STAGE_LABEL[st].label}<Strength st={st} /></td>
                      <td className="px-3 py-1.5">
                        <input className={cn(base, "h-8 font-mono text-[12px]")} value={googleMap[st]?.action ?? ""} placeholder="customers/1234567890/conversionActions/…"
                          aria-label={`Google conversion action for ${STAGE_LABEL[st].label}`} aria-invalid={Boolean(errors[`google.map.${st}`])}
                          onChange={(e) => setGoogleMap({ ...googleMap, [st]: { ...googleMap[st], action: e.target.value } })} />
                        {errors[`google.map.${st}`] && <span className="mt-0.5 block text-xs text-danger">{errors[`google.map.${st}`]}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="text-[12px] text-muted">A milestone that is ticked but has no conversion action is logged and held until you add one.</p>
          </section>

          <div className="flex items-center justify-end gap-3 bg-surface-2/40 px-5 py-3">
            {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
            <Button onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-4 animate-spin" />} Save settings</Button>
          </div>
        </div>
      </Card>

      <AttributionCard key={a.version ?? 0} a={a} />
    </div>
  );
}
