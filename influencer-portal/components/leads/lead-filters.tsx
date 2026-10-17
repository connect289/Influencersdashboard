"use client";
// Filters for the lead pipeline (kept in the URL) and saved views.
import { LayoutGrid, List, Save, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { deleteLeadView, saveLeadView } from "@/lib/actions/leads";
import { CREATOR_STAGES } from "@/lib/attribution/stages";
import type { SavedView } from "@/lib/leads/data";

const KEYS = [
  "stage",
  "campaign",
  "deal",
  "deliverable",
  "link",
  "temperature",
  "city",
  "from",
  "to",
  "q",
] as const;

export function LeadFilters({
  options,
  views,
  canShare,
}: {
  options: {
    campaigns: [string, string][];
    deals: [string, string][];
    deliverables: [string, string][];
    links: [string, string][];
  };
  views: SavedView[];
  canShare: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const path = usePathname();
  const sp = useSearchParams();
  const { pending, run } = useAction();
  const [name, setName] = useState("");
  const layout = sp.get("layout") === "table" ? "table" : "board";
  const go = (patch: Record<string, string | null>) => {
    const u = new URLSearchParams(sp.toString());
    u.delete("lead");
    for (const [k, v] of Object.entries(patch)) {
      if (v) u.set(k, v);
      else u.delete(k);
    }
    const q = u.toString();
    router.push(q ? `${path}?${q}` : path, { scroll: false });
  };
  const current = Object.fromEntries(
    KEYS.filter((k) => sp.get(k)).map((k) => [k, sp.get(k) ?? ""]),
  );
  const select = (k: (typeof KEYS)[number], label: string, items: [string, string][]) => (
    <Field id={`lf-${k}`} label={label}>
      <Select
        id={`lf-${k}`}
        value={sp.get(k) ?? ""}
        onChange={(e) => go({ [k]: e.target.value || null })}
      >
        <option value="">{t("leads.filters.all")}</option>
        {items.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </Select>
    </Field>
  );
  return (
    <div className="mb-4 flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          variant={layout === "board" ? "secondary" : "ghost"}
          onClick={() => go({ layout: null })}
          aria-pressed={layout === "board"}
        >
          <LayoutGrid /> {t("leads.layout.board")}
        </Button>
        <Button
          size="sm"
          variant={layout === "table" ? "secondary" : "ghost"}
          onClick={() => go({ layout: "table" })}
          aria-pressed={layout === "table"}
        >
          <List /> {t("leads.layout.table")}
        </Button>
        {views.length ? (
          <Select
            aria-label={t("leads.views.open")}
            className="w-auto"
            value=""
            onChange={(e) => {
              const v = views.find((x) => x.id === e.target.value);
              if (v) go({ ...Object.fromEntries(KEYS.map((k) => [k, null])), ...v.filters });
            }}
          >
            <option value="">{t("leads.views.open")}</option>
            {views.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name}
                {v.shared ? ` (${t("leads.views.shared")})` : ""}
              </option>
            ))}
          </Select>
        ) : null}
        {Object.keys(current).length ? (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => go(Object.fromEntries(KEYS.map((k) => [k, null])))}
          >
            <X /> {t("leads.filters.clear")}
          </Button>
        ) : null}
      </div>
      <details className="rounded-xl bg-surface p-3 shadow-[var(--shadow-card)]">
        <summary className="cursor-pointer text-sm font-medium">{t("leads.filters.title")}</summary>
        <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {select(
            "stage",
            t("leads.filters.stage"),
            CREATOR_STAGES.map((s) => [s, t(`leads.stages.names.${s}`)]),
          )}
          {select("temperature", t("leads.filters.temperature"), [
            ["HOT", "HOT"],
            ["WARM", "WARM"],
            ["COLD", "COLD"],
          ])}
          {select("campaign", t("leads.filters.campaign"), options.campaigns)}
          {select("deal", t("leads.filters.deal"), options.deals)}
          {select("deliverable", t("leads.filters.deliverable"), options.deliverables)}
          {select("link", t("leads.filters.link"), options.links)}
          <Field id="lf-city" label={t("leads.filters.city")}>
            <Input
              id="lf-city"
              defaultValue={sp.get("city") ?? ""}
              maxLength={60}
              onBlur={(e) => go({ city: e.target.value.trim() || null })}
            />
          </Field>
          <Field id="lf-q" label={t("leads.filters.search")}>
            <Input
              id="lf-q"
              defaultValue={sp.get("q") ?? ""}
              maxLength={60}
              placeholder="L-… / CODE"
              onBlur={(e) => go({ q: e.target.value.trim() || null })}
            />
          </Field>
          <Field id="lf-from" label={t("leads.filters.from")}>
            <Input
              id="lf-from"
              type="date"
              value={sp.get("from") ?? ""}
              onChange={(e) => go({ from: e.target.value || null })}
            />
          </Field>
          <Field id="lf-to" label={t("leads.filters.to")}>
            <Input
              id="lf-to"
              type="date"
              value={sp.get("to") ?? ""}
              onChange={(e) => go({ to: e.target.value || null })}
            />
          </Field>
        </div>
        <form
          className="mt-3 flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => saveLeadView({ name, filters: current, shared: false }),
              () => (setName(""), router.refresh()),
            );
          }}
        >
          <Field id="lf-view" label={t("leads.views.name")}>
            <Input
              id="lf-view"
              value={name}
              maxLength={60}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>
          <Button type="submit" size="sm" variant="secondary" disabled={pending || !name.trim()}>
            <Save /> {t("leads.views.save")}
          </Button>
          {canShare && name.trim() ? (
            <Button
              type="button"
              size="sm"
              variant="ghost"
              disabled={pending}
              onClick={() =>
                run(
                  () => saveLeadView({ name, filters: current, shared: true }),
                  () => (setName(""), router.refresh()),
                )
              }
            >
              {t("leads.views.saveShared")}
            </Button>
          ) : null}
        </form>
        {views.filter((v) => v.mine).length ? (
          <ul className="mt-2 flex flex-wrap gap-2 text-xs">
            {views
              .filter((v) => v.mine)
              .map((v) => (
                <li
                  key={v.id}
                  className="inline-flex items-center gap-1 rounded-full bg-surface-2 px-2 py-0.5"
                >
                  {v.name}
                  <button
                    type="button"
                    aria-label={t("common.remove")}
                    onClick={() =>
                      run(
                        () => deleteLeadView(v.id),
                        () => router.refresh(),
                      )
                    }
                  >
                    <X className="size-3" />
                  </button>
                </li>
              ))}
          </ul>
        ) : null}
      </details>
    </div>
  );
}
