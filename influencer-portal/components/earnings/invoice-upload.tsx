"use client";
// A GST-registered creator raises their tax invoice for a payout: the form is prefilled with the payout's taxable
// value and GST, checked here with the same rules as the database (lib/ledger/invoice.ts), and the file goes straight
// to the private invoices bucket before the invoice is submitted.
import { FileUp } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { invoiceUploadUrl, submitInvoice } from "@/lib/actions/payouts";
import { INVOICE_MAX_BYTES, INVOICE_TYPES, INVOICES_BUCKET } from "@/lib/ledger/files";
import { invoiceProblems } from "@/lib/ledger/invoice";
import { formatPaise, istToday } from "@/lib/format";
import { createClient } from "@/lib/supabase/browser";

type InvoiceType = (typeof INVOICE_TYPES)[number];
const isInvoiceType = (t: string): t is InvoiceType => (INVOICE_TYPES as readonly string[]).includes(t);
const rupees = (paise: number) => (paise / 100).toFixed(2);
const toPaise = (s: string) => Math.round(Number(s || "0") * 100);

export function InvoiceUpload({
  payout,
  gstin,
  again,
}: {
  payout: { id: string; ref: string; gst_base_paise: number; gst_paise: number; created_at: string };
  gstin: string;
  again: boolean;
}) {
  const t = useTranslations();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [number, setNumber] = useState("");
  const [issuedOn, setIssuedOn] = useState(istToday());
  const [gst, setGst] = useState(gstin);
  const [taxable, setTaxable] = useState(rupees(payout.gst_base_paise));
  const [tax, setTax] = useState(rupees(payout.gst_paise));
  const [file, setFile] = useState<File | null>(null);
  const [tried, setTried] = useState(false);

  const problems = invoiceProblems(
    { number, issued_on: issuedOn, gstin: gst, taxable_paise: toPaise(taxable), gst_paise: toPaise(tax) },
    {
      gst_base_paise: payout.gst_base_paise,
      gst_paise: payout.gst_paise,
      created_on: istToday(new Date(payout.created_at)),
    },
    gstin,
    istToday(),
  );
  const problem = (keys: readonly string[]) => {
    const p = tried ? problems.find((x) => keys.includes(x)) : undefined;
    return p ? t(`earnings.invoice.problems.${p}`) : null;
  };
  const fileError =
    file && (!isInvoiceType(file.type) || file.size > INVOICE_MAX_BYTES) ? t("earnings.invoice.fileRule") : null;

  async function submit() {
    setTried(true);
    if (problems.length || !file || fileError || !isInvoiceType(file.type)) return;
    setBusy(true);
    try {
      const signed = await invoiceUploadUrl({
        payoutId: payout.id,
        fileName: file.name,
        type: file.type,
        size: file.size,
      });
      if (!signed.ok || !signed.data) {
        toast.error(signed.ok ? t("errors.generic") : signed.error);
        return;
      }
      const up = await createClient()
        .storage.from(INVOICES_BUCKET)
        .uploadToSignedUrl(signed.data.path, signed.data.token, file, { contentType: file.type });
      if (up.error) {
        toast.error(t("earnings.invoice.uploadFailed"));
        return;
      }
      const r = await submitInvoice({
        payoutId: payout.id,
        number: number.trim(),
        issuedOn,
        gstin: gst,
        taxableRupees: Number(taxable),
        gstRupees: Number(tax),
        filePath: signed.data.path,
      });
      if (r.ok) {
        toast.success(r.message ?? "");
        setOpen(false);
        router.refresh();
      } else toast.error(r.error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant={again ? "secondary" : "primary"}>
          <FileUp /> {again ? t("earnings.invoice.again") : t("earnings.invoice.upload")}
        </Button>
      </DialogTrigger>
      <DialogContent title={t("earnings.invoice.title", { ref: payout.ref })} closeLabel={t("common.close")}>
        <form
          className="flex flex-col gap-3"
          noValidate
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <p className="text-sm text-muted">
            {t("earnings.invoice.hint", {
              taxable: formatPaise(payout.gst_base_paise),
              gst: formatPaise(payout.gst_paise),
            })}
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field id="inv-number" label={t("earnings.invoice.number")} error={problem(["number"])} required>
              <Input id="inv-number" value={number} maxLength={16} onChange={(e) => setNumber(e.target.value)} />
            </Field>
            <Field
              id="inv-date"
              label={t("earnings.invoice.date")}
              error={problem(["date_future", "date_before_payout"])}
              required
            >
              <Input id="inv-date" type="date" value={issuedOn} onChange={(e) => setIssuedOn(e.target.value)} />
            </Field>
          </div>
          <Field id="inv-gstin" label="GSTIN" error={problem(["gstin_invalid", "gstin_mismatch"])} required>
            <Input
              id="inv-gstin"
              className="font-mono uppercase"
              value={gst}
              maxLength={15}
              onChange={(e) => setGst(e.target.value.toUpperCase())}
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field
              id="inv-taxable"
              label={t("earnings.invoice.taxable")}
              error={problem(["taxable_mismatch"])}
              required
            >
              <Input
                id="inv-taxable"
                inputMode="decimal"
                value={taxable}
                onChange={(e) => setTaxable(e.target.value.replace(/[^0-9.]/g, ""))}
              />
            </Field>
            <Field id="inv-gst" label={t("earnings.invoice.gst")} error={problem(["gst_mismatch"])} required>
              <Input
                id="inv-gst"
                inputMode="decimal"
                value={tax}
                onChange={(e) => setTax(e.target.value.replace(/[^0-9.]/g, ""))}
              />
            </Field>
          </div>
          <Field
            id="inv-file"
            label={t("earnings.invoice.file")}
            hint={t("earnings.invoice.fileRule")}
            error={fileError ?? (tried && !file ? t("earnings.invoice.fileMissing") : null)}
            required
          >
            <Input
              id="inv-file"
              type="file"
              accept={INVOICE_TYPES.join(",")}
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={busy}>
              {t("earnings.invoice.submit")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
