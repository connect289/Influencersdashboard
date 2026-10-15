"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Upload } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { adImport, adMap } from "../ads-actions";

export function AdImportButton() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [platform, setPlatform] = useState<"meta" | "google">("meta");
  const [file, setFile] = useState<File | null>(null);
  const [busy, start] = useTransition();
  return (
    <>
      <button type="button" className="btn primary sm" onClick={() => setOpen(true)}><Upload className="icon s" aria-hidden />Import spend</button>
      {open && (
        <Sheet title="Import ad spend" onClose={() => setOpen(false)}>
          <div className="stack">
            <label className="field"><span>Platform</span>
              <select className="input" value={platform} onChange={(e) => setPlatform(e.target.value as "meta" | "google")}><option value="meta">Meta (Facebook and Instagram)</option><option value="google">Google Ads</option></select></label>
            <label className="field"><span>CSV export</span><input className="input" type="file" accept=".csv,text/csv" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></label>
            <p className="note">{platform === "meta"
              ? "Ads Manager → Campaigns → Breakdown: By time → Day → Export table data (CSV). Keep Campaign name, Campaign ID, Amount spent, Impressions, Link clicks and Leads."
              : "Google Ads → Campaigns → Segment: Time → Day → Download (CSV). Keep Campaign, Campaign ID, Cost, Impr., Clicks, Conversions and Currency code."}
              {" "}Spend must be in INR. Importing the same days again replaces them.</p>
            <button type="button" className="btn primary block" disabled={busy || !file} onClick={() => file && start(async () => {
              const r = await adImport(platform, file.name, await file.text());
              if (!r.ok) return void toast.error(r.error);
              toast.success(r.notice ?? "Imported.");
              setOpen(false);
              router.refresh();
            })}>Import</button>
          </div>
        </Sheet>
      )}
    </>
  );
}

/** Ties a platform campaign to the leads it brings: their source value, or their campaign value. */
export function AdMapButton({ platform, campaignId, campaign, current, values }: {
  platform: string; campaignId: string; campaign: string; current: { lead_source: string | null; lead_campaign: string | null } | null;
  values: { source: string | null; campaign: string | null; leads: number }[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [source, setSource] = useState(current?.lead_source ?? "");
  const [camp, setCamp] = useState(current?.lead_campaign ?? "");
  const [busy, start] = useTransition();
  const sources = [...new Set(values.map((v) => v.source).filter(Boolean))] as string[];
  const campaigns = [...new Set(values.map((v) => v.campaign).filter(Boolean))] as string[];
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}>{current ? "Change match" : "Match leads"}</button>
      {open && (
        <Sheet title={`Which leads come from “${campaign}”?`} onClose={() => setOpen(false)}>
          <div className="stack">
            <p className="note">Leads whose campaign value equals the platform campaign&apos;s id or name match by themselves. Otherwise name the campaign value the leads carry, or (if this campaign is the only one with that source) their source.</p>
            <label className="field"><span>Leads&apos; campaign value</span>
              <input className="input" list="ad-camps" value={camp} onChange={(e) => setCamp(e.target.value)} placeholder="e.g. mba_oct_delhi" />
              <datalist id="ad-camps">{campaigns.map((c) => <option key={c} value={c} />)}</datalist></label>
            <label className="field"><span>or the leads&apos; source</span>
              <input className="input" list="ad-sources" value={source} onChange={(e) => setSource(e.target.value)} placeholder="e.g. google_ads" disabled={!!camp.trim()} />
              <datalist id="ad-sources">{sources.map((c) => <option key={c} value={c} />)}</datalist></label>
            <button type="button" className="btn primary block" disabled={busy || (!camp.trim() && !source.trim())} onClick={() => start(async () => {
              const r = await adMap({ platform, campaign_id: campaignId, lead_campaign: camp.trim() || undefined, lead_source: camp.trim() ? undefined : source.trim() || undefined });
              if (!r.ok) return void toast.error(r.error);
              toast.success(r.notice ?? "Saved.");
              setOpen(false);
              router.refresh();
            })}>Save</button>
          </div>
        </Sheet>
      )}
    </>
  );
}
