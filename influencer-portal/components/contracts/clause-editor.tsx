"use client";
// Clause library editor: wording (with variables and conditionals), category, flags and deal types. Saving changed
// wording or flags creates a new version; contracts already generated keep the version they used. A Super Admin marks
// the current version legally reviewed.
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Banner } from "@/components/ui/states";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { archiveClause, markClauseReviewed, saveClause } from "@/lib/actions/contracts";
import { EMPTY_DOC, plainText, type RichDoc } from "@/lib/contracts/doc";
import { DRAFT_MARKER } from "@/lib/contracts/library";
import { docIssues, EDITABLE_CATEGORIES, type EditableCategory } from "@/lib/contracts/schemas";
import { DEAL_MODELS, type DealModel } from "@/lib/deals/schemas";
import { DocView } from "./doc-view";
import { RichEditor } from "./rich-editor";

export interface ClauseFormValue {
  id?: string;
  key: string;
  category: EditableCategory;
  dealTypes: DealModel[];
  title: string;
  body: RichDoc;
  required: boolean;
  negotiable: boolean;
  locked: boolean;
}

export const NEW_CLAUSE: ClauseFormValue = {
  key: "",
  category: "other",
  dealTypes: [],
  title: "",
  body: EMPTY_DOC,
  required: false,
  negotiable: false,
  locked: false,
};

export function ClauseEditor({
  initial,
  version,
  reviewed,
  archived,
  canWrite,
  canReview,
}: {
  initial: ClauseFormValue;
  version: number | null;
  reviewed: boolean;
  archived: boolean;
  canWrite: boolean;
  canReview: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState(initial);
  const issues = useMemo(() => docIssues(v.body), [v.body]);
  const hasMarker = useMemo(() => plainText(v.body.content).includes(DRAFT_MARKER), [v.body]);
  const set = <K extends keyof ClauseFormValue>(k: K, x: ClauseFormValue[K]) =>
    setV((p) => ({ ...p, [k]: x }));
  const isNew = !v.id;
  const readOnly = !canWrite || archived;

  return (
    <div className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_320px]">
      <Card>
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () => saveClause(v),
              (d) => {
                if (isNew && d) router.push(`/admin/contracts/clauses/${d.id}`);
                else router.refresh();
              },
            );
          }}
        >
          <div className="grid gap-4 md:grid-cols-2">
            <Field id="cl-title" label={t("contracts.library.fields.title")} required>
              <Input
                id="cl-title"
                value={v.title}
                onChange={(e) => set("title", e.target.value)}
                maxLength={160}
                required
                disabled={readOnly}
              />
            </Field>
            <Field
              id="cl-key"
              label={t("contracts.library.fields.key")}
              hint={t("contracts.library.fields.keyHint")}
            >
              <Input
                id="cl-key"
                value={v.key}
                onChange={(e) =>
                  set("key", e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "_"))
                }
                pattern="[a-z][a-z0-9_]{1,59}"
                maxLength={60}
                required
                disabled={!isNew || readOnly}
              />
            </Field>
            <Field id="cl-cat" label={t("contracts.library.fields.category")}>
              <Select
                id="cl-cat"
                value={v.category}
                onChange={(e) => set("category", e.target.value as EditableCategory)}
                disabled={readOnly}
              >
                {EDITABLE_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {t(`contracts.categories.${c}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <fieldset className="flex flex-col gap-1.5">
              <legend className="mb-1.5 text-sm font-medium">
                {t("contracts.library.fields.dealTypes")}
              </legend>
              <div className="flex flex-wrap gap-x-4 gap-y-1">
                {DEAL_MODELS.map((m) => (
                  <label key={m} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={v.dealTypes.includes(m)}
                      disabled={readOnly}
                      onChange={(e) =>
                        set(
                          "dealTypes",
                          e.target.checked
                            ? [...v.dealTypes, m]
                            : v.dealTypes.filter((x) => x !== m),
                        )
                      }
                    />
                    {t(`deals.models.${m}`)}
                  </label>
                ))}
              </div>
              <p className="text-xs text-muted">{t("contracts.library.fields.dealTypesHint")}</p>
            </fieldset>
          </div>
          <Field
            id="cl-body"
            label={t("contracts.library.fields.body")}
            hint={t("contracts.library.fields.bodyHint")}
          >
            {readOnly ? (
              <div className="rounded-lg border border-line p-3">
                <DocView blocks={v.body.content} />
              </div>
            ) : (
              <RichEditor
                id="cl-body"
                label={t("contracts.library.fields.body")}
                value={v.body}
                onChange={(d) => set("body", d)}
                variables
                invalid={issues.unknown.length > 0 || issues.errors.length > 0}
              />
            )}
          </Field>
          {issues.unknown.length ? (
            <Banner tone="danger">
              {t("contracts.editor.unknown", { list: issues.unknown.join(", ") })}
            </Banner>
          ) : null}
          {issues.errors.length ? (
            <Banner tone="danger">
              {t("contracts.editor.errors", { list: issues.errors.join(", ") })}
            </Banner>
          ) : null}
          <div className="flex flex-col gap-3">
            <SwitchField
              id="cl-required"
              label={t("contracts.flags.required")}
              hint={t("contracts.flags.requiredHint")}
              checked={v.required}
              disabled={readOnly}
              onCheckedChange={(c) => set("required", c)}
            />
            <SwitchField
              id="cl-negotiable"
              label={t("contracts.flags.negotiable")}
              hint={t("contracts.flags.negotiableHint")}
              checked={v.negotiable}
              disabled={readOnly}
              onCheckedChange={(c) =>
                setV((p) => ({ ...p, negotiable: c, locked: c ? false : p.locked }))
              }
            />
            <SwitchField
              id="cl-locked"
              label={t("contracts.flags.locked")}
              hint={t("contracts.flags.lockedHint")}
              checked={v.locked}
              disabled={readOnly}
              onCheckedChange={(c) =>
                setV((p) => ({ ...p, locked: c, negotiable: c ? false : p.negotiable }))
              }
            />
          </div>
          {canWrite && !archived ? (
            <div className="flex flex-wrap justify-end gap-2">
              <Button type="submit" disabled={pending}>
                {isNew ? t("contracts.library.create") : t("contracts.library.saveVersion")}
              </Button>
            </div>
          ) : null}
        </form>
      </Card>
      <div className="flex flex-col gap-4">
        {!isNew ? (
          <Card>
            <CardHeader
              title={t("contracts.library.reviewTitle")}
              description={version ? t("contracts.library.versionLabel", { version }) : undefined}
            />
            <div className="flex flex-col gap-3 text-sm">
              {reviewed ? (
                <Badge family="success">{t("contracts.library.reviewedBadge")}</Badge>
              ) : (
                <Badge family="attention">{t("contracts.library.unreviewedBadge")}</Badge>
              )}
              {hasMarker ? <p className="text-muted">{t("contracts.library.markerHint")}</p> : null}
              {canReview && !reviewed && version ? (
                <ConfirmDialog
                  trigger={
                    <Button variant="secondary">{t("contracts.library.markReviewed")}</Button>
                  }
                  title={t("contracts.library.markReviewed")}
                  description={t("contracts.library.markReviewedHint", { version })}
                  actionLabel={t("contracts.library.markReviewed")}
                  danger={false}
                  pending={pending}
                  onConfirm={(_r, close) =>
                    run(
                      () => markClauseReviewed(initial.id ?? "", version),
                      () => {
                        close();
                        router.refresh();
                      },
                    )
                  }
                />
              ) : null}
              {!canReview && !reviewed ? (
                <p className="text-muted">{t("contracts.library.reviewWho")}</p>
              ) : null}
            </div>
          </Card>
        ) : null}
        {!isNew && canWrite ? (
          <Card>
            <CardHeader
              title={archived ? t("contracts.library.restore") : t("contracts.library.archive")}
            />
            <p className="mb-3 text-sm text-muted">
              {archived ? t("contracts.library.restoreHint") : t("contracts.library.archiveHint")}
            </p>
            <ConfirmDialog
              trigger={
                <Button variant="secondary">
                  {archived ? t("contracts.library.restore") : t("contracts.library.archive")}
                </Button>
              }
              title={archived ? t("contracts.library.restore") : t("contracts.library.archive")}
              actionLabel={
                archived ? t("contracts.library.restore") : t("contracts.library.archive")
              }
              danger={!archived}
              pending={pending}
              onConfirm={(_r, close) =>
                run(
                  () => archiveClause(initial.id ?? "", !archived),
                  () => {
                    close();
                    router.refresh();
                  },
                )
              }
            />
          </Card>
        ) : null}
      </div>
    </div>
  );
}
