"use client";
import { History, ShieldCheck } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Banner, ListSkeleton } from "@/components/ui/states";
import { confirmSetting, saveSetting, settingHistory, type HistoryRow } from "@/lib/actions/settings";
import { formatDateTime } from "@/lib/format";
import { SchemaFields, type JsonSchema } from "./schema-form";

export interface SettingRow {
  key: string;
  label: string;
  description: string;
  json_schema: JsonSchema;
  value: Record<string, unknown>;
  version: number;
  is_default: boolean;
  can_edit: boolean;
  needs_confirmation: string | null;
  confirmed_at: string | null;
  updated_by_name: string | null;
  updated_at: string | null;
}

export function SettingCard({ row }: { row: SettingRow }) {
  const t = useTranslations();
  const [value, setValue] = useState<Record<string, unknown>>(row.value);
  const [version, setVersion] = useState(row.version);
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [pending, start] = useTransition();
  const dirty = JSON.stringify(value) !== JSON.stringify(row.value);

  return (
    <Card id={row.key} className="scroll-mt-24">
      <CardHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {row.label}
            {row.is_default ? (
              <Badge>{t("settings.default")}</Badge>
            ) : (
              <Badge family="progress">{t("settings.versionBadge", { version })}</Badge>
            )}
            {!row.can_edit ? <Badge family="closed">{t("settings.readOnly")}</Badge> : null}
          </span>
        }
        description={row.description}
        actions={<HistoryButton settingKey={row.key} />}
      />
      {row.key === "contracts.signing" ? (
        // Spec 8.4: a standing note, shown whether or not the setting has been confirmed.
        <div className="mb-4">
          <Banner tone="info">{t("settings.stampDutyNote")}</Banner>
        </div>
      ) : null}
      {row.needs_confirmation && !row.confirmed_at ? (
        <div className="mb-4 flex flex-col gap-2">
          <Banner tone="warning">{row.needs_confirmation}</Banner>
          {row.can_edit ? (
            <div className="flex flex-col gap-2 sm:flex-row">
              <Input
                aria-label={t("settings.confirmNote")}
                placeholder={t("settings.confirmNote")}
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
              <Button
                variant="secondary"
                disabled={pending || note.trim().length < 3}
                onClick={() =>
                  start(async () => {
                    const r = await confirmSetting(row.key, note);
                    if (r.ok) toast.success(r.message ?? "");
                    else toast.error(r.error);
                  })
                }
              >
                <ShieldCheck /> {t("settings.confirm")}
              </Button>
            </div>
          ) : null}
        </div>
      ) : null}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          start(async () => {
            const r = await saveSetting(row.key, value, reason, version);
            if (r.ok) {
              toast.success(r.message ?? "");
              setVersion(r.data?.version ?? version);
              setReason("");
            } else toast.error(r.error);
          });
        }}
        className="flex flex-col gap-4"
      >
        <SchemaFields
          schema={row.json_schema}
          value={value}
          onChange={setValue}
          disabled={!row.can_edit || pending}
          idPrefix={row.key.replace(".", "-")}
        />
        {row.can_edit ? (
          <div className="flex flex-col gap-2 border-t border-line pt-4 sm:flex-row sm:items-center">
            <Input
              aria-label={t("settings.reason")}
              placeholder={t("settings.reason")}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              disabled={!dirty || pending}
            />
            <div className="flex gap-2">
              <Button variant="ghost" disabled={!dirty || pending} onClick={() => setValue(row.value)}>
                {t("settings.reset")}
              </Button>
              <Button type="submit" disabled={!dirty || pending || reason.trim().length < 3}>
                {t("settings.save")}
              </Button>
            </div>
          </div>
        ) : null}
        {row.updated_at ? (
          <p className="text-xs text-muted">
            {t("settings.lastChanged", {
              who: row.updated_by_name ?? t("settings.someone"),
              when: formatDateTime(row.updated_at),
            })}
          </p>
        ) : null}
      </form>
    </Card>
  );
}

function HistoryButton({ settingKey }: { settingKey: string }) {
  const t = useTranslations();
  const [rows, setRows] = useState<HistoryRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  return (
    <Dialog
      onOpenChange={(open) => {
        if (open && rows === null)
          void settingHistory(settingKey).then((r) => {
            if (r.ok) setRows(r.data ?? []);
            else setError(r.error);
          });
      }}
    >
      <DialogTrigger asChild>
        <Button variant="ghost" size="sm" aria-label={t("settings.history")}>
          <History /> <span className="hidden sm:inline">{t("settings.history")}</span>
        </Button>
      </DialogTrigger>
      <DialogContent title={t("settings.history")} closeLabel={t("common.close")}>
        {error ? <Banner tone="danger">{error}</Banner> : null}
        {!error && rows === null ? <ListSkeleton rows={3} label={t("common.loading")} /> : null}
        {rows?.length === 0 ? <p className="text-sm text-muted">{t("settings.noHistory")}</p> : null}
        <ol className="flex flex-col gap-3">
          {rows?.map((r) => (
            <li key={r.version} className="rounded-xl bg-surface-2 p-3 text-sm">
              <p className="font-medium">
                {t("settings.historyItem", {
                  version: r.version,
                  who: r.actor_name ?? t("settings.someone"),
                  when: formatDateTime(r.at),
                })}
              </p>
              <p className="text-muted">{r.reason}</p>
              <pre className="mt-2 max-h-40 overflow-auto text-xs whitespace-pre-wrap">
                {JSON.stringify(r.value, null, 2)}
              </pre>
            </li>
          ))}
        </ol>
      </DialogContent>
    </Dialog>
  );
}
