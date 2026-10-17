"use client";
import { Bookmark, Columns3, Filter, List, Search, Trash2, X } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { DEAL_MODELS } from "@/lib/deals/schemas";
import { useEffect, useState, useTransition } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { deleteCreatorView, saveCreatorView } from "@/lib/actions/creators";
import {
  activeFilterCount,
  creatorFilterSchema,
  creatorFiltersToQuery,
  CREATOR_STATUSES,
  PIPELINE_STAGES,
  type CreatorFilters as Filters,
} from "@/lib/creators/crm";
import { PLATFORMS } from "@/lib/creators/schemas";
import { cn } from "@/lib/utils";

export interface Option {
  id: string;
  name: string;
}

export interface SavedView {
  id: string;
  name: string;
  query: string;
  is_shared: boolean;
  mine: boolean;
}

/** Search, filters, saved views and the table/kanban switch. All state lives in the URL. */
export function CreatorFilters({
  filters,
  view,
  owners,
  tiers,
  savedViews,
}: {
  filters: Filters;
  view: "table" | "kanban";
  owners: Option[];
  tiers: Option[];
  savedViews: SavedView[];
}) {
  const t = useTranslations();
  const router = useRouter();
  const path = usePathname();
  const [, startNav] = useTransition();
  const [q, setQ] = useState(filters.q ?? "");
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<Filters>(filters);
  const [saveOpen, setSaveOpen] = useState(false);
  const [viewName, setViewName] = useState("");
  const [shared, setShared] = useState(false);
  const { pending, run } = useAction();

  const go = (f: Partial<Filters>, v = view) =>
    startNav(() => {
      const query = creatorFiltersToQuery({ ...f, page: undefined }, { view: v === "kanban" ? "kanban" : undefined });
      router.replace(query ? `${path}?${query}` : path, { scroll: false });
    });

  // Debounced search.
  useEffect(() => {
    if ((filters.q ?? "") === q) return;
    const id = setTimeout(() => {
      go({ ...filters, q: q.trim() || undefined });
    }, 300);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only the typed text should restart the timer
  }, [q]);

  const count = activeFilterCount(filters);
  const toggle = <K extends "stage" | "status">(k: K, v: Filters[K][number]) =>
    setDraft((d) => {
      const cur = d[k] as string[];
      return { ...d, [k]: cur.includes(v) ? cur.filter((x) => x !== v) : [...cur, v] };
    });

  return (
    <div className="mb-4 flex flex-col gap-2 md:flex-row md:items-center">
      <div className="relative flex-1">
        <Search
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-faint"
          aria-hidden
        />
        <Input
          type="search"
          aria-label={t("creators.search")}
          placeholder={t("creators.searchPlaceholder")}
          value={q}
          onChange={(e) => setQ(e.target.value)}
          className="pl-9"
          maxLength={80}
        />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Dialog
          open={open}
          onOpenChange={(o) => {
            setOpen(o);
            if (o) setDraft(filters);
          }}
        >
          <DialogTrigger asChild>
            <Button variant="secondary">
              <Filter /> {t("creators.filters.title")}
              {count ? <Badge family="progress">{count}</Badge> : null}
            </Button>
          </DialogTrigger>
          <DialogContent title={t("creators.filters.title")} closeLabel={t("common.close")} className="md:max-w-2xl">
            <form
              className="flex flex-col gap-4"
              onSubmit={(e) => {
                e.preventDefault();
                setOpen(false);
                go({ ...draft, q: filters.q });
              }}
            >
              <fieldset>
                <legend className="mb-1.5 text-sm font-medium">{t("creators.filters.stage")}</legend>
                <div className="flex flex-wrap gap-1.5">
                  {PIPELINE_STAGES.map((s) => (
                    <button
                      type="button"
                      key={s}
                      aria-pressed={draft.stage.includes(s)}
                      onClick={() => toggle("stage", s)}
                      className={cn(
                        "rounded-full px-3 py-1 text-sm ring-1 ring-line-strong ring-inset",
                        draft.stage.includes(s) && "bg-primary text-on-primary ring-primary",
                      )}
                    >
                      {t(`creators.stages.${s}`)}
                    </button>
                  ))}
                </div>
              </fieldset>
              <fieldset>
                <legend className="mb-1.5 text-sm font-medium">{t("creators.filters.status")}</legend>
                <div className="flex flex-wrap gap-1.5">
                  {CREATOR_STATUSES.map((s) => (
                    <button
                      type="button"
                      key={s}
                      aria-pressed={draft.status.includes(s)}
                      onClick={() => toggle("status", s)}
                      className={cn(
                        "rounded-full px-3 py-1 text-sm ring-1 ring-line-strong ring-inset",
                        draft.status.includes(s) && "bg-primary text-on-primary ring-primary",
                      )}
                    >
                      {t(`creators.statuses.${s}`)}
                    </button>
                  ))}
                </div>
              </fieldset>
              <div className="grid gap-3 md:grid-cols-3">
                <Field id="f-platform" label={t("profile.platforms.platform")}>
                  <Select
                    id="f-platform"
                    value={draft.platform ?? ""}
                    onChange={(e) =>
                      setDraft({
                        ...draft,
                        platform: (e.target.value || undefined) as Filters["platform"],
                      })
                    }
                  >
                    <option value="">{t("creators.filters.any")}</option>
                    {PLATFORMS.map((p) => (
                      <option key={p} value={p}>
                        {t(`platforms.${p}`)}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Field id="f-fmin" label={t("creators.filters.followersMin")}>
                  <Input
                    id="f-fmin"
                    type="number"
                    min={0}
                    inputMode="numeric"
                    value={draft.followers_min ?? ""}
                    onChange={(e) =>
                      setDraft({
                        ...draft,
                        followers_min: e.target.value ? Number(e.target.value) : undefined,
                      })
                    }
                  />
                </Field>
                <Field id="f-fmax" label={t("creators.filters.followersMax")}>
                  <Input
                    id="f-fmax"
                    type="number"
                    min={0}
                    inputMode="numeric"
                    value={draft.followers_max ?? ""}
                    onChange={(e) =>
                      setDraft({
                        ...draft,
                        followers_max: e.target.value ? Number(e.target.value) : undefined,
                      })
                    }
                  />
                </Field>
                <Field id="f-niche" label={t("creators.filters.niche")}>
                  <Input
                    id="f-niche"
                    value={draft.niche ?? ""}
                    onChange={(e) => setDraft({ ...draft, niche: e.target.value || undefined })}
                    maxLength={40}
                  />
                </Field>
                <Field id="f-lang" label={t("creators.filters.language")}>
                  <Input
                    id="f-lang"
                    value={draft.language ?? ""}
                    onChange={(e) => setDraft({ ...draft, language: e.target.value || undefined })}
                    maxLength={40}
                  />
                </Field>
                <Field id="f-tag" label={t("creators.filters.tag")}>
                  <Input
                    id="f-tag"
                    value={draft.tag ?? ""}
                    onChange={(e) => setDraft({ ...draft, tag: e.target.value || undefined })}
                    maxLength={40}
                  />
                </Field>
                <Field id="f-city" label={t("profile.fields.city")}>
                  <Input
                    id="f-city"
                    value={draft.city ?? ""}
                    onChange={(e) => setDraft({ ...draft, city: e.target.value || undefined })}
                    maxLength={80}
                  />
                </Field>
                <Field id="f-state" label={t("profile.fields.state")}>
                  <Input
                    id="f-state"
                    value={draft.state ?? ""}
                    onChange={(e) => setDraft({ ...draft, state: e.target.value || undefined })}
                    maxLength={80}
                  />
                </Field>
                <Field id="f-owner" label={t("creators.fields.owner")}>
                  <Select
                    id="f-owner"
                    value={draft.owner_id ?? ""}
                    onChange={(e) => setDraft({ ...draft, owner_id: e.target.value || undefined })}
                  >
                    <option value="">{t("creators.filters.anyone")}</option>
                    <option value="me">{t("creators.filters.me")}</option>
                    <option value="none">{t("creators.filters.noOwner")}</option>
                    {owners.map((o) => (
                      <option key={o.id} value={o.id}>
                        {o.name}
                      </option>
                    ))}
                  </Select>
                </Field>
                {tiers.length ? (
                  <Field id="f-tier" label={t("creators.fields.tier")}>
                    <Select
                      id="f-tier"
                      value={draft.tier_id ?? ""}
                      onChange={(e) => setDraft({ ...draft, tier_id: e.target.value || undefined })}
                    >
                      <option value="">{t("creators.filters.any")}</option>
                      {tiers.map((o) => (
                        <option key={o.id} value={o.id}>
                          {o.name}
                        </option>
                      ))}
                    </Select>
                  </Field>
                ) : null}
                <Field id="f-deal" label={t("creators.filters.dealType")}>
                  <Select
                    id="f-deal"
                    value={draft.deal_model ?? ""}
                    onChange={(e) =>
                      setDraft({
                        ...draft,
                        deal_model: (e.target.value || undefined) as Filters["deal_model"],
                      })
                    }
                  >
                    <option value="">{t("creators.filters.any")}</option>
                    {DEAL_MODELS.map((m) => (
                      <option key={m} value={m}>
                        {t(`deals.models.${m}`)}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Field id="f-follow" label={t("creators.filters.followUp")}>
                  <Select
                    id="f-follow"
                    value={draft.follow_up ?? ""}
                    onChange={(e) =>
                      setDraft({
                        ...draft,
                        follow_up: (e.target.value || undefined) as Filters["follow_up"],
                      })
                    }
                  >
                    <option value="">{t("creators.filters.any")}</option>
                    <option value="overdue">{t("creators.filters.overdue")}</option>
                    <option value="today">{t("creators.filters.dueToday")}</option>
                  </Select>
                </Field>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  className="size-4 accent-[var(--primary)]"
                  checked={draft.include_blocked ?? false}
                  onChange={(e) => setDraft({ ...draft, include_blocked: e.target.checked || undefined })}
                />
                {t("creators.filters.includeBlocked")}
              </label>
              <div className="flex justify-end gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => setDraft(creatorFilterSchema.parse({ q: filters.q }))}
                >
                  {t("common.clear")}
                </Button>
                <Button type="submit">{t("common.apply")}</Button>
              </div>
            </form>
          </DialogContent>
        </Dialog>
        {count ? (
          <Button variant="ghost" onClick={() => go({ q: filters.q, status: [], stage: [] })}>
            <X /> {t("creators.filters.clearAll")}
          </Button>
        ) : null}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="secondary">
              <Bookmark /> {t("creators.views.title")}
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-56">
            {savedViews.length === 0 ? (
              <p className="px-3 py-2 text-sm text-muted">{t("creators.views.empty")}</p>
            ) : (
              savedViews.map((v) => (
                <div key={v.id} className="flex items-center">
                  <DropdownMenuItem className="flex-1" onSelect={() => router.replace(`${path}?${v.query}`)}>
                    {v.name}
                    {v.is_shared ? <span className="ml-2 text-xs text-muted">{t("creators.views.shared")}</span> : null}
                  </DropdownMenuItem>
                  {v.mine ? (
                    <button
                      type="button"
                      className="rounded-lg p-2 text-muted hover:bg-surface-2"
                      aria-label={t("creators.views.delete", { name: v.name })}
                      onClick={() => run(() => deleteCreatorView(v.id))}
                    >
                      <Trash2 className="size-4" />
                    </button>
                  ) : null}
                </div>
              ))
            )}
            <DropdownMenuItem onSelect={() => setSaveOpen(true)}>{t("creators.views.saveCurrent")}</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <Dialog open={saveOpen} onOpenChange={setSaveOpen}>
          <DialogContent title={t("creators.views.saveCurrent")} closeLabel={t("common.close")}>
            <form
              className="flex flex-col gap-4"
              onSubmit={(e) => {
                e.preventDefault();
                run(
                  () => saveCreatorView(viewName, { ...filters }, shared),
                  () => {
                    setSaveOpen(false);
                    setViewName("");
                  },
                );
              }}
            >
              <Field id="view-name" label={t("creators.views.name")} required>
                <Input
                  id="view-name"
                  value={viewName}
                  onChange={(e) => setViewName(e.target.value)}
                  maxLength={60}
                  required
                />
              </Field>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  className="size-4 accent-[var(--primary)]"
                  checked={shared}
                  onChange={(e) => setShared(e.target.checked)}
                />
                {t("creators.views.shareWithTeam")}
              </label>
              <Button type="submit" disabled={pending || !viewName.trim()}>
                {t("common.save")}
              </Button>
            </form>
          </DialogContent>
        </Dialog>
        <div
          className="flex rounded-xl ring-1 ring-line-strong ring-inset"
          role="group"
          aria-label={t("creators.layout")}
        >
          <Button
            variant="ghost"
            size="icon"
            aria-pressed={view === "table"}
            aria-label={t("creators.tableView")}
            className={cn(view === "table" && "bg-surface-2")}
            onClick={() => go(filters, "table")}
          >
            <List />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            aria-pressed={view === "kanban"}
            aria-label={t("creators.kanbanView")}
            className={cn(view === "kanban" && "bg-surface-2")}
            onClick={() => go(filters, "kanban")}
          >
            <Columns3 />
          </Button>
        </div>
      </div>
    </div>
  );
}
