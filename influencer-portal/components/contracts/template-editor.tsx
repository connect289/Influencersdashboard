"use client";
// Contract template editor: title, header and footer (with variables), the ordered clauses from the library with an
// optional condition each, and a live preview against sample deals, so staff see which clauses appear for each deal
// type and whether any variable is unknown before a real contract uses the template.
import { ArrowDown, ArrowUp, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { Banner, EmptyState } from "@/components/ui/states";
import { SwitchField } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { archiveTemplate, saveTemplate } from "@/lib/actions/contracts";
import { assembleContract } from "@/lib/contracts/assemble";
import type { RichDoc } from "@/lib/contracts/doc";
import { SAMPLE_KINDS, sampleContext, type SampleKind } from "@/lib/contracts/sample";
import type { LibraryOption } from "@/lib/contracts/library-options";
import { CONDITION } from "@/lib/contracts/schemas";
import { VARIABLES } from "@/lib/contracts/variables";
import { istToday } from "@/lib/format";
import { DocView } from "./doc-view";
import { RichEditor } from "./rich-editor";

export interface TemplateFormValue {
  id?: string;
  name: string;
  description: string;
  title: string;
  header: RichDoc;
  footer: RichDoc;
  isDefault: boolean;
  clauses: { clauseId: string; condition: string }[];
}

const FLAGS = VARIABLES.filter((v) => v.kind === "flag");

export function TemplateEditor({
  initial,
  library,
  archived,
  canWrite,
}: {
  initial: TemplateFormValue;
  library: LibraryOption[];
  archived: boolean;
  canWrite: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [v, setV] = useState(initial);
  const [sample, setSample] = useState<SampleKind>("full");
  const [adding, setAdding] = useState("");
  const byId = useMemo(() => new Map(library.map((c) => [c.id, c])), [library]);
  const readOnly = !canWrite || archived;
  const isNew = !v.id;
  const set = <K extends keyof TemplateFormValue>(k: K, x: TemplateFormValue[K]) => setV((p) => ({ ...p, [k]: x }));
  const setClauses = (f: (cs: TemplateFormValue["clauses"]) => TemplateFormValue["clauses"]) =>
    setV((p) => ({ ...p, clauses: f(p.clauses) }));
  const missingRequired = library.filter((c) => c.required && !v.clauses.some((x) => x.clauseId === c.id));
  const badConditions = v.clauses.filter((c) => c.condition !== "" && !CONDITION.test(c.condition));

  const preview = useMemo(() => {
    const clauses = v.clauses.flatMap((c) => {
      const lib = byId.get(c.clauseId);
      return lib
        ? [
            {
              clause_id: lib.id,
              version: lib.version,
              key: lib.key,
              category: lib.category,
              title: lib.title,
              body: lib.body,
              negotiable: lib.negotiable,
              locked: lib.locked,
              required: lib.required,
              reviewed: lib.reviewed,
              condition: CONDITION.test(c.condition) ? c.condition : null,
            },
          ]
        : [];
    });
    return assembleContract(
      { title: v.title, header: v.header, footer: v.footer, clauses },
      sampleContext(sample, istToday()),
    );
  }, [v, byId, sample]);

  const available = library.filter((c) => !v.clauses.some((x) => x.clauseId === c.id));

  return (
    <div className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <div className="flex flex-col gap-4">
        <Card>
          <form
            id="template-form"
            className="flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              run(
                () => saveTemplate(v),
                (d) => {
                  if (isNew && d) router.push(`/admin/contracts/templates/${d.id}`);
                  else router.refresh();
                },
              );
            }}
          >
            <div className="grid gap-4 md:grid-cols-2">
              <Field id="tp-name" label={t("contracts.templates.fields.name")} required>
                <Input
                  id="tp-name"
                  value={v.name}
                  onChange={(e) => set("name", e.target.value)}
                  maxLength={120}
                  required
                  disabled={readOnly}
                />
              </Field>
              <Field
                id="tp-title"
                label={t("contracts.templates.fields.title")}
                hint={t("contracts.templates.fields.titleHint")}
                required
              >
                <Input
                  id="tp-title"
                  value={v.title}
                  onChange={(e) => set("title", e.target.value)}
                  maxLength={200}
                  required
                  disabled={readOnly}
                />
              </Field>
            </div>
            <Field id="tp-desc" label={t("contracts.templates.fields.description")}>
              <Textarea
                id="tp-desc"
                value={v.description}
                onChange={(e) => set("description", e.target.value)}
                maxLength={500}
                disabled={readOnly}
              />
            </Field>
            <SwitchField
              id="tp-default"
              label={t("contracts.templates.fields.default")}
              hint={t("contracts.templates.fields.defaultHint")}
              checked={v.isDefault}
              disabled={readOnly}
              onCheckedChange={(c) => set("isDefault", c)}
            />
            <Field id="tp-header" label={t("contracts.templates.fields.header")}>
              {readOnly ? (
                <DocView blocks={v.header.content} className="rounded-lg border border-line p-3 text-sm" />
              ) : (
                <RichEditor
                  id="tp-header"
                  label={t("contracts.templates.fields.header")}
                  value={v.header}
                  onChange={(d) => set("header", d)}
                  variables
                />
              )}
            </Field>
            <Field id="tp-footer" label={t("contracts.templates.fields.footer")}>
              {readOnly ? (
                <DocView blocks={v.footer.content} className="rounded-lg border border-line p-3 text-sm" />
              ) : (
                <RichEditor
                  id="tp-footer"
                  label={t("contracts.templates.fields.footer")}
                  value={v.footer}
                  onChange={(d) => set("footer", d)}
                  variables
                />
              )}
            </Field>
          </form>
        </Card>

        <Card>
          <CardHeader title={t("contracts.templates.clauses")} description={t("contracts.templates.clausesHint")} />
          {v.clauses.length === 0 ? (
            <EmptyState
              title={t("contracts.templates.noClauses")}
              description={t("contracts.templates.noClausesHint")}
            />
          ) : (
            <ol className="flex flex-col gap-2">
              {v.clauses.map((c, i) => {
                const lib = byId.get(c.clauseId);
                const condId = `tp-cond-${String(i)}`;
                return (
                  <li key={c.clauseId} className="rounded-lg border border-line p-3">
                    <div className="flex items-start gap-2">
                      <span className="tabular w-6 shrink-0 pt-0.5 text-sm text-muted">{i + 1}.</span>
                      <div className="min-w-0 flex-1">
                        <p className="font-medium">{lib?.title ?? t("contracts.templates.missingClause")}</p>
                        <p className="flex flex-wrap gap-1 text-xs text-muted">
                          <span>{lib?.key}</span>
                          {lib?.required ? <Badge>{t("contracts.flags.required")}</Badge> : null}
                          {lib?.negotiable ? <Badge family="progress">{t("contracts.flags.negotiable")}</Badge> : null}
                          {lib && !lib.reviewed ? (
                            <Badge family="attention">{t("contracts.library.unreviewedBadge")}</Badge>
                          ) : null}
                        </p>
                      </div>
                      {readOnly ? null : (
                        <div className="flex shrink-0 gap-0.5">
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            aria-label={t("contracts.templates.moveUp")}
                            disabled={i === 0}
                            onClick={() =>
                              setClauses((cs) => {
                                const n = [...cs];
                                const [x] = n.splice(i, 1);
                                if (x) n.splice(i - 1, 0, x);
                                return n;
                              })
                            }
                          >
                            <ArrowUp />
                          </Button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            aria-label={t("contracts.templates.moveDown")}
                            disabled={i === v.clauses.length - 1}
                            onClick={() =>
                              setClauses((cs) => {
                                const n = [...cs];
                                const [x] = n.splice(i, 1);
                                if (x) n.splice(i + 1, 0, x);
                                return n;
                              })
                            }
                          >
                            <ArrowDown />
                          </Button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon"
                            aria-label={t("contracts.templates.remove")}
                            onClick={() => setClauses((cs) => cs.filter((_, j) => j !== i))}
                          >
                            <X />
                          </Button>
                        </div>
                      )}
                    </div>
                    <div className="mt-2 pl-8">
                      <label htmlFor={condId} className="text-xs text-muted">
                        {t("contracts.templates.condition")}
                      </label>
                      <Select
                        id={condId}
                        value={
                          FLAGS.some((f) => f.key === c.condition || `!${f.key}` === c.condition) || c.condition === ""
                            ? c.condition
                            : "custom"
                        }
                        disabled={readOnly}
                        onChange={(e) =>
                          setClauses((cs) =>
                            cs.map((x, j) =>
                              j === i
                                ? { ...x, condition: e.target.value === "custom" ? x.condition : e.target.value }
                                : x,
                            ),
                          )
                        }
                      >
                        <option value="">{t("contracts.templates.always")}</option>
                        {FLAGS.map((f) => (
                          <option key={f.key} value={f.key}>
                            {t("contracts.templates.when", { flag: f.label })}
                          </option>
                        ))}
                        {FLAGS.map((f) => (
                          <option key={`!${f.key}`} value={`!${f.key}`}>
                            {t("contracts.templates.unless", { flag: f.label })}
                          </option>
                        ))}
                        <option value="custom">{t("contracts.templates.custom")}</option>
                      </Select>
                      {c.condition !== "" &&
                      !FLAGS.some((f) => f.key === c.condition || `!${f.key}` === c.condition) ? (
                        <Input
                          aria-label={t("contracts.templates.customCondition")}
                          className="mt-1"
                          value={c.condition}
                          maxLength={120}
                          disabled={readOnly}
                          placeholder='deal.model == "hybrid"'
                          onChange={(e) =>
                            setClauses((cs) => cs.map((x, j) => (j === i ? { ...x, condition: e.target.value } : x)))
                          }
                        />
                      ) : null}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
          {readOnly ? null : (
            <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-end">
              <Field id="tp-add" label={t("contracts.templates.addClause")} className="flex-1">
                <Select id="tp-add" value={adding} onChange={(e) => setAdding(e.target.value)}>
                  <option value="">{t("contracts.templates.pickClause")}</option>
                  {available.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.title} ({t(`contracts.categories.${c.category as "other"}`)})
                    </option>
                  ))}
                </Select>
              </Field>
              <Button
                type="button"
                variant="secondary"
                disabled={!adding}
                onClick={() => {
                  setClauses((cs) => [...cs, { clauseId: adding, condition: "" }]);
                  setAdding("");
                }}
              >
                {t("contracts.templates.add")}
              </Button>
            </div>
          )}
          {missingRequired.length ? (
            <div className="mt-3">
              <Banner tone="warning">
                {t("contracts.templates.missingRequired", { list: missingRequired.map((c) => c.title).join(", ") })}
              </Banner>
            </div>
          ) : null}
          {badConditions.length ? (
            <div className="mt-3">
              <Banner tone="danger">{t("contracts.errors.condition")}</Banner>
            </div>
          ) : null}
        </Card>

        {canWrite ? (
          <div className="flex flex-wrap justify-end gap-2">
            {!isNew ? (
              <ConfirmDialog
                trigger={
                  <Button type="button" variant="secondary">
                    {archived ? t("contracts.templates.restore") : t("contracts.templates.archive")}
                  </Button>
                }
                title={archived ? t("contracts.templates.restore") : t("contracts.templates.archive")}
                description={archived ? undefined : t("contracts.templates.archiveHint")}
                actionLabel={archived ? t("contracts.templates.restore") : t("contracts.templates.archive")}
                danger={!archived}
                pending={pending}
                onConfirm={(_r, close) =>
                  run(
                    () => archiveTemplate(initial.id ?? "", !archived),
                    () => {
                      close();
                      router.refresh();
                    },
                  )
                }
              />
            ) : null}
            {archived ? null : (
              <Button type="submit" form="template-form" disabled={pending || badConditions.length > 0}>
                {isNew ? t("contracts.templates.create") : t("contracts.templates.save")}
              </Button>
            )}
          </div>
        ) : null}
      </div>

      <Card className="xl:sticky xl:top-4">
        <CardHeader
          title={t("contracts.templates.preview")}
          description={t("contracts.templates.previewHint")}
          actions={
            <Select
              aria-label={t("contracts.templates.sample")}
              value={sample}
              onChange={(e) => setSample(e.target.value as SampleKind)}
            >
              {SAMPLE_KINDS.map((k) => (
                <option key={k} value={k}>
                  {t(`contracts.templates.samples.${k}`)}
                </option>
              ))}
            </Select>
          }
        />
        <div className="flex flex-col gap-2">
          {preview.unknown.length ? (
            <Banner tone="danger">{t("contracts.editor.unknown", { list: preview.unknown.join(", ") })}</Banner>
          ) : null}
          {preview.errors.length ? (
            <Banner tone="danger">{t("contracts.editor.errors", { list: preview.errors.join(", ") })}</Banner>
          ) : null}
          {preview.unreviewed.length ? (
            <Banner tone="warning">
              {t("contracts.templates.unreviewedInPreview", { count: preview.unreviewed.length })}
            </Banner>
          ) : null}
        </div>
        <article className="mt-3 max-h-[70vh] overflow-y-auto rounded-lg border border-line p-4 text-sm">
          <h2 className="text-lg font-semibold">{preview.content.title}</h2>
          <DocView blocks={preview.content.header} className="mt-2" />
          {preview.content.sections.map((s) => (
            <section key={s.key} className="mt-4">
              <h3 className="font-semibold">
                {s.number}. {s.title}
              </h3>
              <DocView blocks={s.blocks} className="mt-1" />
            </section>
          ))}
          <DocView blocks={preview.content.footer} className="mt-4" />
        </article>
      </Card>
    </div>
  );
}
