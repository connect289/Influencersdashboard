import "server-only";
import { getTranslations } from "next-intl/server";
import { DEFAULT_LOCALE } from "@/i18n/request";
import type { FinancePdfLabels } from "./pdf";

/** Labels for the finance PDFs (also used by background jobs, so the locale is explicit). */
export async function financePdfLabels(): Promise<FinancePdfLabels> {
  const t = await getTranslations({ locale: DEFAULT_LOCALE });
  return {
    advice: t("earnings.pdf.advice"),
    statement: t("earnings.pdf.statement"),
    payee: t("earnings.pdf.payee"),
    name: t("earnings.pdf.name"),
    pan: t("finance.payouts.pan"),
    bank: t("finance.payouts.bank"),
    paidOn: t("earnings.pdf.paidOn"),
    utr: t("finance.payouts.utr"),
    payoutStatement: t("earnings.pdf.payoutStatement"),
    date: t("earnings.pdf.date"),
    description: t("earnings.pdf.description"),
    amount: t("earnings.pdf.amount"),
    gross: t("finance.payouts.gross"),
    tds: (section, rate) => t("finance.payouts.tdsLine", { section, rate }),
    gst: t("finance.payouts.gst"),
    net: t("finance.payouts.net"),
    opening: t("earnings.pdf.opening"),
    closing: t("earnings.pdf.closing"),
    earned: t("earnings.pdf.earned"),
    tdsTotal: t("earnings.pdf.tds"),
    paidOut: t("earnings.pdf.paidOut"),
    empty: t("earnings.pdf.empty"),
    adviceNote: t("earnings.pdf.adviceNote"),
    statementNote: t("earnings.pdf.statementNote"),
    page: (n, of) => t("earnings.pdf.page", { n, of }),
    type: (x) => t(`finance.types.${x}`),
  };
}
