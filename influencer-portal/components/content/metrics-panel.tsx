"use client";
// Metrics at checkpoints after going live (24 hours, 7 days, 30 days by default), entered by the creator with a
// screenshot of their insights. Platform APIs can fill the same table later.
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input, Select } from "@/components/ui/input";
import { Table, Td, Th } from "@/components/ui/table";
import { useAction } from "@/components/ui/use-action";
import { submitMetrics } from "@/lib/actions/content";
import type { MetricSnapshot } from "@/lib/content/data";
import { METRIC_FIELDS, type MetricField } from "@/lib/content/schemas";
import { formatDateTime, formatNumber } from "@/lib/format";
import { UploadField } from "./upload-field";
import type { Uploaded } from "./uploader";

export function checkpointLabel(cp: string, t: ReturnType<typeof useTranslations>): string {
  if (cp === "adhoc") return t("content.metrics.adhoc");
  const h = Number.parseInt(cp, 10);
  return h % 24 === 0 ? t("content.metrics.days", { count: h / 24 }) : t("content.metrics.hours", { count: h });
}

export function MetricsForm({
  deliverableId,
  checkpoints,
  done,
}: {
  deliverableId: string;
  checkpoints: number[];
  done: string[];
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const options = [...checkpoints.map((h) => `${String(h)}h`), "adhoc"];
  const [checkpoint, setCheckpoint] = useState(options.find((o) => !done.includes(o)) ?? "adhoc");
  const [values, setValues] = useState<Record<MetricField, string>>(
    Object.fromEntries(METRIC_FIELDS.map((f) => [f, ""])) as Record<MetricField, string>,
  );
  const [shots, setShots] = useState<Uploaded[]>([]);
  const [busy, setBusy] = useState(false);
  const num = (s: string) => (s.trim() === "" ? null : Math.max(0, Math.round(Number(s.replace(/,/g, "")) || 0)));
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        run(
          () =>
            submitMetrics({
              deliverableId,
              checkpoint,
              ...(Object.fromEntries(METRIC_FIELDS.map((f) => [f, num(values[f])])) as Record<
                MetricField,
                number | null
              >),
              screenshots: shots.map((s) => s.path),
            }),
          () => {
            setValues(Object.fromEntries(METRIC_FIELDS.map((f) => [f, ""])) as Record<MetricField, string>);
            setShots([]);
            router.refresh();
          },
        );
      }}
    >
      <Field id="mt-cp" label={t("content.metrics.checkpoint")}>
        <Select id="mt-cp" value={checkpoint} onChange={(e) => setCheckpoint(e.target.value)}>
          {options.map((o) => (
            <option key={o} value={o}>
              {checkpointLabel(o, t)}
              {done.includes(o) ? ` ${t("content.metrics.alreadyIn")}` : ""}
            </option>
          ))}
        </Select>
      </Field>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {METRIC_FIELDS.map((f) => (
          <Field key={f} id={`mt-${f}`} label={t(`content.metrics.fields.${f}`)}>
            <Input
              id={`mt-${f}`}
              inputMode="numeric"
              value={values[f]}
              onChange={(e) => setValues({ ...values, [f]: e.target.value })}
            />
          </Field>
        ))}
      </div>
      <UploadField
        id="mt-shots"
        deliverableId={deliverableId}
        value={shots}
        onChange={setShots}
        max={5}
        accept={["image/jpeg", "image/png", "image/webp"]}
        label={t("content.metrics.screenshots")}
        onBusy={setBusy}
      />
      <Button
        type="submit"
        className="self-start"
        disabled={pending || busy || METRIC_FIELDS.every((f) => values[f].trim() === "")}
      >
        {t("content.metrics.save")}
      </Button>
    </form>
  );
}

export function MetricsTable({ rows, links }: { rows: MetricSnapshot[]; links: Record<string, string> }) {
  const t = useTranslations();
  if (!rows.length) return <p className="text-sm text-muted">{t("content.metrics.none")}</p>;
  const shown = METRIC_FIELDS.filter((f) => rows.some((r) => r[f] !== null));
  return (
    <Table>
      <thead>
        <tr>
          <Th>{t("content.metrics.checkpoint")}</Th>
          {shown.map((f) => (
            <Th key={f} className="text-right">
              {t(`content.metrics.fields.${f}`)}
            </Th>
          ))}
          <Th>{t("content.metrics.proof")}</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.id}>
            <Td className="whitespace-nowrap">
              {checkpointLabel(r.checkpoint, t)}
              <span className="block text-xs text-muted">{formatDateTime(r.captured_at)}</span>
            </Td>
            {shown.map((f) => (
              <Td key={f} className="text-right tabular-nums">
                {r[f] === null ? "—" : formatNumber(r[f])}
              </Td>
            ))}
            <Td>
              {r.screenshot_paths.length
                ? r.screenshot_paths.map((p, i) =>
                    links[p] ? (
                      <a
                        key={p}
                        href={links[p]}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="mr-2 text-primary hover:underline"
                      >
                        {t("content.metrics.shot", { n: i + 1 })}
                      </a>
                    ) : null,
                  )
                : t(`content.metrics.sources.${r.source}`)}
            </Td>
          </tr>
        ))}
      </tbody>
    </Table>
  );
}
