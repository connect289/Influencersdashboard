"use client";
import { Download, FileUp } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { Banner } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { useAction } from "@/components/ui/use-action";
import { importCreators, type ImportResult } from "@/lib/actions/creators";
import { IMPORT_FIELDS, IMPORT_MAX_BYTES } from "@/lib/creators/crm";

const TEMPLATE =
  "name,handle,email,phone,city,state,niches,languages,tags,platform,profile url,followers,source\r\n" +
  "Riya Sharma,riyalearns,riya@example.com,9876543210,Delhi,Delhi,MBA;Finance,English;Hindi,campus,instagram,https://instagram.com/riyalearns,120000,referral\r\n";

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

/** Upload a CSV, check it (dry run), then import. Duplicates and errors are reported row by row. */
export function ImportWizard() {
  const t = useTranslations();
  const fileRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<{ name: string; text: string } | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const { pending, run } = useAction();

  async function pick(f: File) {
    if (f.size > IMPORT_MAX_BYTES) {
      toast.error(t("creators.import.errors.tooBig"));
      return;
    }
    const text = await f.text();
    setFile({ name: f.name, text });
    setResult(null);
    run(
      () => importCreators(f.name, text, true),
      (r) => r && setResult(r),
    );
  }

  const done = result && !result.dry_run;
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader title={t("creators.import.step1")} description={t("creators.import.step1Hint")} />
        <div className="flex flex-wrap gap-2">
          <input
            ref={fileRef}
            type="file"
            accept=".csv,text/csv"
            className="sr-only"
            aria-label={t("creators.import.choose")}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void pick(f);
              e.target.value = "";
            }}
          />
          <Button onClick={() => fileRef.current?.click()} disabled={pending}>
            <FileUp /> {file ? t("creators.import.chooseAnother") : t("creators.import.choose")}
          </Button>
          <Button variant="secondary" onClick={() => download("creators-template.csv", TEMPLATE)}>
            <Download /> {t("creators.import.template")}
          </Button>
        </div>
        <p className="mt-3 text-xs text-muted">{t("creators.import.columns", { columns: IMPORT_FIELDS.join(", ") })}</p>
      </Card>
      {result ? (
        <Card>
          <CardHeader
            title={done ? t("creators.import.doneTitle") : t("creators.import.checkTitle", { file: file?.name ?? "" })}
            description={done ? undefined : t("creators.import.checkHint")}
          />
          <div className="mb-4 flex flex-wrap gap-2">
            <Badge family="success">
              {t(done ? "creators.import.created" : "creators.import.willCreate", { count: result.created })}
            </Badge>
            <Badge family="attention">{t("creators.import.duplicates", { count: result.duplicates })}</Badge>
            <Badge family="problem">{t("creators.import.errorsCount", { count: result.errors })}</Badge>
          </div>
          {done ? <Banner tone="success">{t("creators.import.doneBody", { count: result.created })}</Banner> : null}
          {result.report.some((r) => r.result !== "created") ? (
            <Table className="mt-3 min-w-[480px]">
              <thead>
                <tr>
                  <Th>{t("creators.import.row")}</Th>
                  <Th>{t("creators.fields.handle")}</Th>
                  <Th>{t("creators.import.result")}</Th>
                  <Th>{t("creators.import.reason")}</Th>
                </tr>
              </thead>
              <tbody>
                {result.report
                  .filter((r) => r.result !== "created")
                  .slice(0, 200)
                  .map((r) => (
                    <tr key={`${String(r.row)}-${r.result}`}>
                      <Td className="tabular-nums">{r.row}</Td>
                      <Td>{r.handle || "—"}</Td>
                      <Td>
                        <Badge family={r.result === "duplicate" ? "attention" : "problem"}>
                          {t(`creators.import.results.${r.result}`)}
                        </Badge>
                      </Td>
                      <Td className="text-xs">
                        {(r.reason ?? "")
                          .split(",")
                          .filter(Boolean)
                          .map((code) => t(`creators.import.reasons.${code.replace(":", "_") as "handle"}`))
                          .join("; ")}
                      </Td>
                    </tr>
                  ))}
              </tbody>
            </Table>
          ) : null}
          <div className="mt-4 flex flex-wrap gap-2">
            {!done && result.created > 0 && file ? (
              <Button
                disabled={pending}
                onClick={() =>
                  run(
                    () => importCreators(file.name, file.text, false),
                    (r) => r && setResult(r),
                  )
                }
              >
                {t("creators.import.run", { count: result.created })}
              </Button>
            ) : null}
            <Button variant="secondary" onClick={() => download("import-report.csv", result.reportCsv)}>
              <Download /> {t("creators.import.downloadReport")}
            </Button>
            {done ? (
              <Button asChild variant="link">
                <Link href="/admin/creators?sort=updated&dir=desc">{t("creators.import.viewCreators")}</Link>
              </Button>
            ) : null}
          </div>
        </Card>
      ) : null}
    </div>
  );
}
