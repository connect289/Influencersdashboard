"use client";
// The banned-claims list (spec 16): phrases match as whole words; patterns (regex) are checked for safety before
// saving. "Block" stops approval until fixed or overridden; "warn" only flags it for the reviewer.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { saveBannedClaim } from "@/lib/actions/content";
import { scanClaims } from "@/lib/content/compliance";
import type { BannedClaimRow } from "@/lib/content/data";

type Draft = {
  id: string | null;
  pattern: string;
  kind: "phrase" | "regex";
  severity: "block" | "warn";
  note: string;
  active: boolean;
};
const EMPTY: Draft = { id: null, pattern: "", kind: "phrase", severity: "block", note: "", active: true };

export function ClaimsEditor({ rows, canEdit }: { rows: BannedClaimRow[]; canEdit: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [draft, setDraft] = useState<Draft>(EMPTY);
  const [sample, setSample] = useState("");
  const active = rows.filter((r) => r.active).map((r) => ({ ...r }));
  const hits = sample.trim() ? scanClaims(sample, active) : [];
  const save = (d: Draft) =>
    run(
      () => saveBannedClaim(d),
      () => {
        setDraft(EMPTY);
        router.refresh();
      },
    );
  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <Card>
        <CardHeader title={t("content.claims.listTitle", { count: rows.length })} />
        <ul className="flex flex-col divide-y divide-line">
          {rows.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center gap-2 py-2 text-sm">
              <span className={r.active ? "min-w-0 flex-1" : "min-w-0 flex-1 text-muted line-through"}>
                <span className="font-medium break-words">
                  {r.kind === "regex" ? <code>{r.pattern}</code> : r.pattern}
                </span>
                {r.note ? <span className="block text-xs text-muted">{r.note}</span> : null}
              </span>
              <Badge family={r.severity === "block" ? "problem" : "attention"}>
                {t(`content.checks.severity.${r.severity}`)}
              </Badge>
              {r.kind === "regex" ? <Badge>{t("content.claims.regex")}</Badge> : null}
              {canEdit ? (
                <>
                  <Switch
                    aria-label={t("content.claims.active")}
                    checked={r.active}
                    disabled={pending}
                    onCheckedChange={(on) =>
                      save({
                        id: r.id,
                        pattern: r.pattern,
                        kind: r.kind,
                        severity: r.severity,
                        note: r.note ?? "",
                        active: on,
                      })
                    }
                  />
                  <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={() =>
                      setDraft({
                        id: r.id,
                        pattern: r.pattern,
                        kind: r.kind,
                        severity: r.severity,
                        note: r.note ?? "",
                        active: r.active,
                      })
                    }
                  >
                    {t("common.edit")}
                  </Button>
                </>
              ) : null}
            </li>
          ))}
        </ul>
      </Card>
      <div className="flex flex-col gap-4">
        {canEdit ? (
          <Card>
            <CardHeader title={draft.id ? t("content.claims.edit") : t("content.claims.add")} />
            <form
              className="flex flex-col gap-3"
              onSubmit={(e) => {
                e.preventDefault();
                save(draft);
              }}
            >
              <Field
                id="cl-pattern"
                label={t("content.claims.pattern")}
                hint={draft.kind === "regex" ? t("content.claims.regexHint") : t("content.claims.phraseHint")}
              >
                <Input
                  id="cl-pattern"
                  required
                  minLength={2}
                  maxLength={200}
                  value={draft.pattern}
                  onChange={(e) => setDraft({ ...draft, pattern: e.target.value })}
                />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field id="cl-kind" label={t("content.claims.kind")}>
                  <Select
                    id="cl-kind"
                    value={draft.kind}
                    onChange={(e) => setDraft({ ...draft, kind: e.target.value === "regex" ? "regex" : "phrase" })}
                  >
                    <option value="phrase">{t("content.claims.phrase")}</option>
                    <option value="regex">{t("content.claims.regex")}</option>
                  </Select>
                </Field>
                <Field id="cl-sev" label={t("content.claims.severity")}>
                  <Select
                    id="cl-sev"
                    value={draft.severity}
                    onChange={(e) => setDraft({ ...draft, severity: e.target.value === "warn" ? "warn" : "block" })}
                  >
                    <option value="block">{t("content.checks.severity.block")}</option>
                    <option value="warn">{t("content.checks.severity.warn")}</option>
                  </Select>
                </Field>
              </div>
              <Field id="cl-note" label={t("content.claims.note")}>
                <Input
                  id="cl-note"
                  maxLength={300}
                  value={draft.note}
                  onChange={(e) => setDraft({ ...draft, note: e.target.value })}
                />
              </Field>
              <div className="flex justify-end gap-2">
                {draft.id ? (
                  <Button type="button" variant="ghost" onClick={() => setDraft(EMPTY)}>
                    {t("common.cancel")}
                  </Button>
                ) : null}
                <Button type="submit" disabled={pending || draft.pattern.trim().length < 2}>
                  {t("common.save")}
                </Button>
              </div>
            </form>
          </Card>
        ) : null}
        <Card>
          <CardHeader title={t("content.claims.tryTitle")} description={t("content.claims.tryHint")} />
          <Input
            aria-label={t("content.claims.tryTitle")}
            value={sample}
            maxLength={2000}
            onChange={(e) => setSample(e.target.value)}
          />
          {sample.trim() ? (
            hits.length ? (
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {hits.map((h, i) => (
                  <li key={i}>
                    <Badge family={h.severity === "block" ? "problem" : "attention"}>
                      {t(`content.checks.severity.${h.severity}`)}
                    </Badge>{" "}
                    “{h.text}”
                  </li>
                ))}
              </ul>
            ) : (
              <p className="mt-2 text-sm text-success">{t("content.claims.noHits")}</p>
            )
          ) : null}
        </Card>
      </div>
    </div>
  );
}
