"use client";
// Start a deal: creator, optional campaign, title, dates and a preset to begin from. The terms are then edited in the
// builder on the deal page.
import { Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { searchCreators } from "@/lib/actions/creators";
import { createDeal } from "@/lib/actions/deals";
import type { CompConfig } from "@/lib/compensation/schema";

type Hit = { id: string; name: string; handle: string };

export function NewDealForm({
  presets,
  campaigns,
  initialCreator,
  initialCampaignId,
  today,
}: {
  presets: { id: string; name: string; config: CompConfig; default: boolean }[];
  campaigns: { id: string; name: string; startsOn: string | null; endsOn: string | null; presetId: string | null }[];
  initialCreator: Hit | null;
  initialCampaignId: string;
  today: string;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [creator, setCreator] = useState<Hit | null>(initialCreator);
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const camp0 = campaigns.find((c) => c.id === initialCampaignId);
  const [campaignId, setCampaignId] = useState(camp0?.id ?? "");
  const [title, setTitle] = useState(camp0?.name ?? "");
  const [startsOn, setStartsOn] = useState(camp0?.startsOn && camp0.startsOn > today ? camp0.startsOn : today);
  const [endsOn, setEndsOn] = useState(camp0?.endsOn ?? "");
  const [presetId, setPresetId] = useState(
    camp0?.presetId ?? presets.find((p) => p.default)?.id ?? presets[0]?.id ?? "",
  );
  const [notes, setNotes] = useState("");
  const active = q.trim().length >= 2;
  useEffect(() => {
    if (!active) return;
    let live = true;
    const id = setTimeout(() => {
      void searchCreators(q).then((r) => {
        if (live) setHits(r);
      });
    }, 250);
    return () => {
      live = false;
      clearTimeout(id);
    };
  }, [q, active]);
  const preset = presets.find((p) => p.id === presetId);

  return (
    <Card>
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (!creator || !preset) return;
          run(
            () =>
              createDeal({
                creatorId: creator.id,
                campaignId,
                title,
                startsOn,
                endsOn,
                presetId,
                config: preset.config,
                internalNotes: notes,
              }),
            (data) => {
              if (data) router.push(`/admin/deals/${data.id}?tab=terms`);
            },
          );
        }}
      >
        <Field id="nd-creator" label={t("deals.new.creator")} required>
          {creator ? (
            <div className="flex items-center justify-between rounded-xl px-3 py-2 ring-1 ring-line ring-inset">
              <span>
                {creator.name} <span className="text-muted">@{creator.handle}</span>
              </span>
              <Button type="button" variant="ghost" size="sm" onClick={() => setCreator(null)}>
                {t("deals.new.change")}
              </Button>
            </div>
          ) : (
            <div className="relative">
              <Search
                className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
                aria-hidden
              />
              <Input
                id="nd-creator"
                className="pl-9"
                placeholder={t("deals.new.searchCreator")}
                value={q}
                onChange={(e) => setQ(e.target.value)}
                maxLength={80}
                autoComplete="off"
              />
              {active && hits.length ? (
                <ul
                  role="listbox"
                  aria-label={t("deals.new.creator")}
                  className="mt-1 max-h-60 overflow-y-auto rounded-xl ring-1 ring-line ring-inset"
                >
                  {hits.map((h) => (
                    <li key={h.id}>
                      <button
                        type="button"
                        role="option"
                        aria-selected={false}
                        className="w-full px-3 py-2 text-left text-sm hover:bg-surface-2"
                        onClick={() => {
                          setCreator(h);
                          setQ("");
                        }}
                      >
                        {h.name} <span className="text-muted">@{h.handle}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              ) : active ? (
                <p className="mt-1 text-xs text-muted">{t("deals.new.noCreators")}</p>
              ) : null}
            </div>
          )}
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field id="nd-campaign" label={t("deals.new.campaign")} hint={t("deals.new.campaignHint")}>
            <Select
              id="nd-campaign"
              value={campaignId}
              onChange={(e) => {
                const c = campaigns.find((x) => x.id === e.target.value);
                setCampaignId(e.target.value);
                if (c) {
                  if (!title) setTitle(c.name);
                  if (c.endsOn) setEndsOn(c.endsOn);
                  if (c.presetId) setPresetId(c.presetId);
                }
              }}
            >
              <option value="">{t("deals.new.alwaysOn")}</option>
              {campaigns.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="nd-title" label={t("deals.new.title")} required>
            <Input id="nd-title" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} />
          </Field>
          <Field id="nd-start" label={t("deals.new.startsOn")} required>
            <Input id="nd-start" type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
          </Field>
          <Field id="nd-end" label={t("deals.new.endsOn")} hint={t("deals.new.endsOnHint")}>
            <Input id="nd-end" type="date" value={endsOn} min={startsOn} onChange={(e) => setEndsOn(e.target.value)} />
          </Field>
          <Field id="nd-preset" label={t("deals.new.preset")} hint={t("deals.new.presetHint")} required>
            <Select id="nd-preset" value={presetId} onChange={(e) => setPresetId(e.target.value)}>
              {presets.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <Field id="nd-notes" label={t("deals.new.notes")} hint={t("deals.new.notesHint")}>
          <Textarea id="nd-notes" value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={4000} />
        </Field>
        <div className="flex justify-end">
          <Button type="submit" disabled={pending || !creator || !preset || title.trim().length < 3 || !startsOn}>
            {t("deals.new.create")}
          </Button>
        </div>
      </form>
    </Card>
  );
}
