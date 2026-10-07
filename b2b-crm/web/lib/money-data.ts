import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { EnrollmentList, InvoiceDetail, InvoiceRow, MoneyOverview, ReceiptsData, StatementDetail, StatementRow } from "@/lib/money";

/** Money reads as the signed-in Admin; every b2b.money_* function re-checks b2b.is_admin(). */
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

/** Not-found reads (P0002) come back as null so the page can 404. */
async function rpcOrNull<T>(fn: string, args: Record<string, unknown>): Promise<T | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error?.code === "P0002") return null;
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const moneyOverview = () => rpc<MoneyOverview>("money_overview");
export const moneyEnrollments = (p: { status: string; partner_id: number | null; q: string | null; offset: number }) =>
  rpc<EnrollmentList>("money_enrollments", { p: { ...p, limit: 50 } });
export const moneyInvoices = (status: string | null, partnerId: number | null) => rpc<InvoiceRow[]>("money_invoices", { p: { status, partner_id: partnerId } });
export const invoiceDetail = (id: number) => rpcOrNull<InvoiceDetail>("invoice_detail", { p_id: id });
export const moneyReceipts = (partnerId: number | null) => rpc<ReceiptsData>("money_receipts", { p: { partner_id: partnerId } });
export const moneyStatements = () => rpc<StatementRow[]>("money_statements");
export const statementDetail = (id: number) => rpcOrNull<StatementDetail>("statement_detail", { p_id: id });
