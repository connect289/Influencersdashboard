"use client";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { useAction } from "@/components/ui/use-action";
import { reviewInvoice } from "@/lib/actions/payouts";

export function InvoiceReview({ invoiceId }: { invoiceId: string }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  return (
    <span className="flex gap-1">
      <Button
        size="sm"
        disabled={pending}
        onClick={() =>
          run(
            () => reviewInvoice({ id: invoiceId, accept: true }),
            () => router.refresh(),
          )
        }
      >
        {t("finance.invoices.accept")}
      </Button>
      <ConfirmDialog
        trigger={
          <Button size="sm" variant="ghost">
            {t("finance.invoices.reject")}
          </Button>
        }
        title={t("finance.invoices.rejectTitle")}
        description={t("finance.invoices.rejectHint")}
        actionLabel={t("finance.invoices.reject")}
        reasonLabel={t("finance.reason")}
        danger
        pending={pending}
        onConfirm={(note, close) =>
          run(
            () => reviewInvoice({ id: invoiceId, accept: false, note }),
            () => (close(), router.refresh()),
          )
        }
      />
    </span>
  );
}
