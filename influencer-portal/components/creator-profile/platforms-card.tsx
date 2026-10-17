"use client";
import { ExternalLink, Pencil, Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { deletePlatform, savePlatform } from "@/lib/actions/creator-profile";
import { PLATFORMS, type Platform } from "@/lib/creators/schemas";
import { formatCompact } from "@/lib/format";
import type { PlatformRow } from "./types";

const toNum = (v: string) => (v.trim() === "" ? null : Number(v));

function PlatformDialog({
  creatorId,
  initial,
  trigger,
}: {
  creatorId: string;
  initial?: PlatformRow;
  trigger: ReactNode;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const { pending, run } = useAction();
  const [v, setV] = useState({
    platform: (initial?.platform ?? "instagram") as Platform,
    url: initial?.url ?? "",
    handle: initial?.handle ?? "",
    followers: initial?.followers?.toString() ?? "",
    avgViews: initial?.avg_views?.toString() ?? "",
    engagementRate: initial?.engagement_rate?.toString() ?? "",
  });
  const set = <K extends keyof typeof v>(k: K, value: (typeof v)[K]) =>
    setV((x) => ({ ...x, [k]: value }));
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent
        title={initial ? t("profile.platforms.edit") : t("profile.platforms.add")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                savePlatform(creatorId, {
                  id: initial?.id,
                  platform: v.platform,
                  url: v.url,
                  handle: v.handle,
                  followers: toNum(v.followers),
                  avgViews: toNum(v.avgViews),
                  engagementRate: toNum(v.engagementRate),
                }),
              () => setOpen(false),
            );
          }}
        >
          <Field id="pl-platform" label={t("profile.platforms.platform")} required>
            <Select
              id="pl-platform"
              value={v.platform}
              onChange={(e) => set("platform", e.target.value as Platform)}
            >
              {PLATFORMS.map((p) => (
                <option key={p} value={p}>
                  {t(`platforms.${p}`)}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="pl-handle" label={t("profile.platforms.handle")} required>
            <Input
              id="pl-handle"
              value={v.handle}
              onChange={(e) => set("handle", e.target.value)}
              required
              maxLength={100}
            />
          </Field>
          <Field
            id="pl-url"
            label={t("profile.platforms.url")}
            hint={t("profile.platforms.urlHint")}
            required
          >
            <Input
              id="pl-url"
              type="url"
              inputMode="url"
              value={v.url}
              onChange={(e) => set("url", e.target.value)}
              required
              pattern="https://.+"
              maxLength={500}
            />
          </Field>
          <div className="grid grid-cols-3 gap-3">
            <Field id="pl-followers" label={t("profile.platforms.followers")}>
              <Input
                id="pl-followers"
                type="number"
                inputMode="numeric"
                min={0}
                value={v.followers}
                onChange={(e) => set("followers", e.target.value)}
              />
            </Field>
            <Field id="pl-views" label={t("profile.platforms.avgViews")}>
              <Input
                id="pl-views"
                type="number"
                inputMode="numeric"
                min={0}
                value={v.avgViews}
                onChange={(e) => set("avgViews", e.target.value)}
              />
            </Field>
            <Field id="pl-er" label={t("profile.platforms.engagement")}>
              <Input
                id="pl-er"
                type="number"
                inputMode="decimal"
                min={0}
                max={100}
                step="0.01"
                value={v.engagementRate}
                onChange={(e) => set("engagementRate", e.target.value)}
              />
            </Field>
          </div>
          <Button type="submit" disabled={pending}>
            {t("common.save")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function PlatformsCard({
  creatorId,
  platforms,
  canEdit,
}: {
  creatorId: string;
  platforms: PlatformRow[];
  canEdit: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const add = canEdit ? (
    <PlatformDialog
      creatorId={creatorId}
      trigger={
        <Button size="sm" variant="secondary">
          <Plus /> {t("profile.platforms.add")}
        </Button>
      }
    />
  ) : null;
  return (
    <Card>
      <CardHeader
        title={t("profile.platforms.title")}
        description={t("profile.platforms.hint")}
        actions={add}
      />
      {platforms.length === 0 ? (
        <EmptyState
          title={t("profile.platforms.empty")}
          description={canEdit ? t("profile.platforms.emptyHint") : undefined}
        />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {platforms.map((p) => (
            <li key={p.id} className="flex items-center gap-3 py-3">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">
                  {t(`platforms.${p.platform as Platform}`)} · @{p.handle}
                </p>
                <p className="text-xs text-muted">
                  {[
                    p.followers !== null
                      ? t("profile.platforms.followersCount", { count: formatCompact(p.followers) })
                      : null,
                    p.avg_views !== null
                      ? t("profile.platforms.viewsCount", { count: formatCompact(p.avg_views) })
                      : null,
                    p.engagement_rate !== null
                      ? t("profile.platforms.erValue", { value: p.engagement_rate })
                      : null,
                  ]
                    .filter(Boolean)
                    .join(" · ") || t("profile.platforms.noStats")}
                </p>
              </div>
              <Button asChild variant="ghost" size="icon">
                <a
                  href={p.url}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  aria-label={t("profile.platforms.open", { handle: p.handle })}
                >
                  <ExternalLink />
                </a>
              </Button>
              {canEdit ? (
                <>
                  <PlatformDialog
                    creatorId={creatorId}
                    initial={p}
                    trigger={
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={t("profile.platforms.editOne", { handle: p.handle })}
                      >
                        <Pencil />
                      </Button>
                    }
                  />
                  <ConfirmDialog
                    title={t("profile.platforms.removeTitle", { handle: p.handle })}
                    actionLabel={t("common.remove")}
                    pending={pending}
                    onConfirm={(_, close) => run(() => deletePlatform(creatorId, p.id), close)}
                    trigger={
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={t("profile.platforms.removeOne", { handle: p.handle })}
                      >
                        <Trash2 />
                      </Button>
                    }
                  />
                </>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
