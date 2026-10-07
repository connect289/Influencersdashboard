import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft } from "lucide-react";
import { PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { dayLabel } from "@/lib/money";
import { statementDetail } from "@/lib/money-data";
import { StatementPiles } from "./StatementPiles";

export const metadata: Metadata = { title: "Statement" };
type Props = { params: Promise<{ id: string }> };

export default async function StatementPage({ params }: Props) {
  await requireAdmin();
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const d = await statementDetail(id);
  if (!d) notFound();
  return (
    <>
      <Link href="/money?tab=statements" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Statements</Link>
      <PageHeader title={`${d.statement.partner_name} statement`}
        description={`${dayLabel(d.statement.period_from)} – ${dayLabel(d.statement.period_to)} · ${d.statement.file_name ?? "uploaded file"} · ${d.statement.row_count} rows. Each pile exports as a list to send the partner.`} />
      <StatementPiles d={d} />
    </>
  );
}
