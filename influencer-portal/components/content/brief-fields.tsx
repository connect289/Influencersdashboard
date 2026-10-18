"use client";
// The fields shared by a brief and a brief template: objective, audience, key messages, disclosures, do's and
// don'ts, tone, languages, hashtags, mentions, call to action, FAQs and references.
import { Plus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { RichEditor } from "@/components/contracts/rich-editor";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input, Textarea } from "@/components/ui/input";
import type { BriefContent } from "@/lib/content/brief";
import { ListEditor } from "./list-editor";

export type SharedFields = Pick<
  BriefContent,
  | "objective"
  | "audience"
  | "key_messages"
  | "disclosures"
  | "dos"
  | "donts"
  | "tone"
  | "languages"
  | "hashtags"
  | "mentions"
  | "cta"
  | "faqs"
  | "references"
>;

export function BriefFields<V extends SharedFields>({ value, onChange }: { value: V; onChange: (v: V) => void }) {
  const t = useTranslations();
  const set = <K extends keyof SharedFields>(k: K, v: SharedFields[K]) => onChange({ ...value, [k]: v });
  return (
    <div className="flex flex-col gap-5">
      <Field id="bf-objective" label={t("content.brief.objective")} hint={t("content.brief.objectiveHint")}>
        <Textarea
          id="bf-objective"
          rows={3}
          maxLength={2000}
          value={value.objective}
          onChange={(e) => set("objective", e.target.value)}
        />
      </Field>
      <Field id="bf-audience" label={t("content.brief.audience")}>
        <Textarea
          id="bf-audience"
          rows={2}
          maxLength={2000}
          value={value.audience}
          onChange={(e) => set("audience", e.target.value)}
        />
      </Field>
      <div className="flex flex-col gap-1.5">
        <span className="text-sm font-medium" id="bf-km-label">
          {t("content.brief.keyMessages")}
        </span>
        <RichEditor
          id="bf-km"
          label={t("content.brief.keyMessages")}
          value={value.key_messages}
          onChange={(d) => set("key_messages", d)}
        />
      </div>
      <ListEditor
        id="bf-disc"
        label={t("content.brief.disclosures")}
        value={value.disclosures}
        max={20}
        onChange={(v) => set("disclosures", v)}
      />
      <div className="grid gap-5 md:grid-cols-2">
        <ListEditor
          id="bf-dos"
          label={t("content.brief.dos")}
          value={value.dos}
          max={30}
          onChange={(v) => set("dos", v)}
        />
        <ListEditor
          id="bf-donts"
          label={t("content.brief.donts")}
          value={value.donts}
          max={30}
          onChange={(v) => set("donts", v)}
        />
      </div>
      <div className="grid gap-5 md:grid-cols-2">
        <Field id="bf-tone" label={t("content.brief.tone")}>
          <Input id="bf-tone" maxLength={300} value={value.tone} onChange={(e) => set("tone", e.target.value)} />
        </Field>
        <Field id="bf-cta" label={t("content.brief.cta")} hint={t("content.brief.ctaHint")}>
          <Input
            id="bf-cta"
            maxLength={300}
            value={value.cta.text}
            onChange={(e) => set("cta", { text: e.target.value })}
          />
        </Field>
      </div>
      <div className="grid gap-5 md:grid-cols-3">
        <ListEditor
          id="bf-lang"
          label={t("content.brief.languages")}
          value={value.languages}
          max={10}
          maxLength={40}
          onChange={(v) => set("languages", v)}
        />
        <ListEditor
          id="bf-tags"
          label={t("content.brief.hashtags")}
          value={value.hashtags}
          max={30}
          maxLength={60}
          placeholder="#"
          onChange={(v) => set("hashtags", v)}
        />
        <ListEditor
          id="bf-ment"
          label={t("content.brief.mentions")}
          value={value.mentions}
          max={30}
          maxLength={60}
          placeholder="@"
          onChange={(v) => set("mentions", v)}
        />
      </div>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium">{t("content.brief.references")}</legend>
        {value.references.map((r, i) => (
          <div key={i} className="grid gap-2 md:grid-cols-[1fr_2fr_auto]">
            <Input
              aria-label={t("content.brief.referenceLabel")}
              placeholder={t("content.brief.referenceLabel")}
              maxLength={300}
              value={r.label}
              onChange={(e) =>
                set(
                  "references",
                  value.references.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)),
                )
              }
            />
            <Input
              aria-label={t("content.brief.referenceUrl")}
              placeholder="https://"
              inputMode="url"
              maxLength={1000}
              value={r.url}
              onChange={(e) =>
                set(
                  "references",
                  value.references.map((x, j) => (j === i ? { ...x, url: e.target.value } : x)),
                )
              }
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={t("common.remove")}
              onClick={() =>
                set(
                  "references",
                  value.references.filter((_, j) => j !== i),
                )
              }
            >
              <X />
            </Button>
          </div>
        ))}
        {value.references.length < 30 ? (
          <Button
            type="button"
            variant="secondary"
            size="sm"
            className="self-start"
            onClick={() => set("references", [...value.references, { label: "", url: "" }])}
          >
            <Plus /> {t("common.add")}
          </Button>
        ) : null}
      </fieldset>
      <fieldset className="flex flex-col gap-3">
        <legend className="mb-1 text-sm font-medium">{t("content.brief.faqs")}</legend>
        {value.faqs.map((f, i) => (
          <div key={i} className="flex flex-col gap-2 rounded-xl bg-surface-2 p-3">
            <div className="flex gap-2">
              <Input
                aria-label={t("content.brief.question")}
                placeholder={t("content.brief.question")}
                maxLength={300}
                value={f.q}
                onChange={(e) =>
                  set(
                    "faqs",
                    value.faqs.map((x, j) => (j === i ? { ...x, q: e.target.value } : x)),
                  )
                }
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                aria-label={t("common.remove")}
                onClick={() =>
                  set(
                    "faqs",
                    value.faqs.filter((_, j) => j !== i),
                  )
                }
              >
                <X />
              </Button>
            </div>
            <Textarea
              aria-label={t("content.brief.answer")}
              placeholder={t("content.brief.answer")}
              rows={2}
              maxLength={2000}
              value={f.a}
              onChange={(e) =>
                set(
                  "faqs",
                  value.faqs.map((x, j) => (j === i ? { ...x, a: e.target.value } : x)),
                )
              }
            />
          </div>
        ))}
        {value.faqs.length < 30 ? (
          <Button
            type="button"
            variant="secondary"
            size="sm"
            className="self-start"
            onClick={() => set("faqs", [...value.faqs, { q: "", a: "" }])}
          >
            <Plus /> {t("common.add")}
          </Button>
        ) : null}
      </fieldset>
    </div>
  );
}

/** Drops empty rows the editor leaves behind, so the schema accepts the result. */
export function cleanShared<V extends SharedFields>(v: V): V {
  const lines = (x: readonly string[]) => x.map((s) => s.trim()).filter(Boolean);
  return {
    ...v,
    disclosures: lines(v.disclosures),
    dos: lines(v.dos),
    donts: lines(v.donts),
    languages: lines(v.languages),
    hashtags: lines(v.hashtags),
    mentions: lines(v.mentions),
    references: v.references.filter((r) => r.label.trim() && r.url.trim()),
    faqs: v.faqs.filter((f) => f.q.trim() && f.a.trim()),
  };
}
