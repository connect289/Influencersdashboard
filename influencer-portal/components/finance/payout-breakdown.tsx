// One payout in full: what it pays (entries), gross, TDS per section, GST and net, the creator's bank and tax
// details (masked), invoices and the payment advice.
import { useTranslations } from "next-intl";
import { Amount } from "@/components/ledger/ledger-table";
import { StatusBadge } from "@/components/ui/badge";
import { fileHref } from "@/lib/ledger/files";
import type { PayoutDetail } from "@/lib/ledger/data";
import { formatDate, formatPaise } from "@/lib/format";

export function PayoutBreakdown({ p }: { p: PayoutDetail }) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-4 text-sm">
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
        <dt className="text-muted">{t("finance.payouts.columns.status")}</dt>
        <dd>
          <StatusBadge status={p.status} label={t(`finance.payoutStatuses.${p.status}`)} />
          {p.status_reason ? <span className="ml-2 text-muted">{p.status_reason}</span> : null}
        </dd>
        <dt className="text-muted">{t("finance.payouts.bank")}</dt>
        <dd>{p.bank_last4 ? `•••• ${p.bank_last4} · ${p.ifsc ?? ""}` : "—"}</dd>
        <dt className="text-muted">{t("finance.payouts.pan")}</dt>
        <dd>{p.pan_last4 ? `•••••${p.pan_last4}` : t("finance.payouts.noPan")}</dd>
        {p.gstin ? (
          <>
            <dt className="text-muted">GSTIN</dt>
            <dd className="font-mono">{p.gstin}</dd>
          </>
        ) : null}
        {p.utr ? (
          <>
            <dt className="text-muted">{t("finance.payouts.utr")}</dt>
            <dd className="font-mono">
              {p.utr} · {p.paid_on ? formatDate(p.paid_on) : ""}
            </dd>
          </>
        ) : null}
      </dl>
      <section>
        <h3 className="mb-1 font-semibold">{t("finance.payouts.items")}</h3>
        <ul className="flex flex-col divide-y divide-line">
          {p.items.map((i) => (
            <li key={i.entry_id} className="flex justify-between gap-3 py-1.5">
              <span>
                {i.note ?? t(`finance.types.${i.type}`)}
                <span className="block text-xs text-muted">{[i.deal_title, i.period].filter(Boolean).join(" · ")}</span>
              </span>
              <Amount paise={Math.abs(i.amount_paise)} direction={i.amount_paise < 0 ? "debit" : "credit"} />
            </li>
          ))}
        </ul>
      </section>
      <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 border-t border-line pt-2">
        <dt>{t("finance.payouts.gross")}</dt>
        <dd className="text-right tabular-nums">{formatPaise(p.gross_paise)}</dd>
        {p.sections
          .filter((s) => s.tds_paise > 0)
          .map((s) => (
            <div key={s.code} className="contents">
              <dt className="text-muted">
                {t("finance.payouts.tdsLine", { section: s.code, rate: (s.rate_bps / 100).toLocaleString("en-IN") })}
                {s.borne_by === "eduwit" ? ` (${t("finance.payouts.borneByEduwit")})` : ""}
              </dt>
              <dd className="text-right text-danger tabular-nums">
                {s.borne_by === "eduwit" ? "" : "−"}
                {formatPaise(s.tds_paise)}
              </dd>
            </div>
          ))}
        {p.gst_paise > 0 ? (
          <>
            <dt className="text-muted">{t("finance.payouts.gst")}</dt>
            <dd className="text-right tabular-nums">{formatPaise(p.gst_paise)}</dd>
          </>
        ) : null}
        <dt className="font-semibold">{t("finance.payouts.net")}</dt>
        <dd className="text-right font-semibold tabular-nums">{formatPaise(p.net_paise)}</dd>
      </dl>
      {p.invoices.length || p.advice_path ? (
        <section>
          <h3 className="mb-1 font-semibold">{t("finance.payouts.documents")}</h3>
          <ul className="flex flex-col gap-1">
            {p.invoices.map((i) => (
              <li key={i.id} className="flex flex-wrap items-center gap-2">
                <span>
                  {t(`finance.invoiceKinds.${i.kind}`)} {i.number}
                </span>
                <StatusBadge status={i.status} label={t(`finance.invoiceStatuses.${i.status}`)} />
                {i.file_path ? (
                  <a
                    href={fileHref(i.file_path)}
                    className="text-primary hover:underline"
                    target="_blank"
                    rel="noreferrer"
                  >
                    {t("finance.open")}
                  </a>
                ) : null}
              </li>
            ))}
            {p.advice_path ? (
              <li>
                <a
                  href={fileHref(p.advice_path)}
                  className="text-primary hover:underline"
                  target="_blank"
                  rel="noreferrer"
                >
                  {t("finance.payouts.advice")}
                </a>
              </li>
            ) : null}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
