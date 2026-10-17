import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ClauseEditor } from "@/components/contracts/clause-editor";
import { DocView } from "@/components/contracts/doc-view";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { loadClauseHistory, loadLibrary } from "@/lib/contracts/data";
import { EDITABLE_CATEGORIES, type EditableCategory } from "@/lib/contracts/schemas";
import { DEAL_MODELS, type DealModel } from "@/lib/deals/schemas";
import { formatDateTime } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.area.clauses") };
}

export default async function ClausePage({ params }: { params: Promise<{ clauseId: string }> }) {
  const { clauseId } = await params;
  if (!z.uuid().safeParse(clauseId).success) notFound();
  const { supabase, me } = await requireStaff("contract.read");
  const t = await getTranslations();
  const [library, history] = await Promise.all([
    loadLibrary(supabase, true),
    loadClauseHistory(supabase, clauseId),
  ]);
  const c = library.find((x) => x.id === clauseId);
  if (!c) notFound();
  const category = (EDITABLE_CATEGORIES as readonly string[]).includes(c.category)
    ? (c.category as EditableCategory)
    : "other";
  return (
    <>
      <Link
        href="/admin/contracts/clauses"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" /> {t("contracts.area.clauses")}
      </Link>
      <PageHeader
        title={c.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <code>{c.key}</code>
            <span>{t("contracts.library.versionLabel", { version: c.version })}</span>
            {c.archived ? <Badge>{t("contracts.library.archivedBadge")}</Badge> : null}
          </span>
        }
        help="/admin/help/influencer-manager#contracts"
      />
      <ClauseEditor
        key={`${c.id}:${String(c.version)}`}
        initial={{
          id: c.id,
          key: c.key,
          category,
          dealTypes: c.deal_types.filter((d): d is DealModel =>
            (DEAL_MODELS as readonly string[]).includes(d),
          ),
          title: c.title,
          body: c.body,
          required: c.required,
          negotiable: c.negotiable,
          locked: c.locked,
        }}
        version={c.version}
        reviewed={c.reviewed_at !== null}
        archived={c.archived}
        canWrite={me.permissions.has("clause.write")}
        canReview={me.permissions.has("clause.legal_review")}
      />
      <Card className="mt-4">
        <CardHeader
          title={t("contracts.library.history")}
          description={t("contracts.library.historyHint")}
        />
        <ol className="flex flex-col gap-2">
          {history.map((v, i) => (
            <li key={v.version}>
              <details open={i === 0} className="rounded-lg border border-line p-3">
                <summary className="flex cursor-pointer flex-wrap items-center gap-2 text-sm">
                  <span className="font-medium">
                    {t("contracts.library.versionLabel", { version: v.version })}
                  </span>
                  <span className="text-muted">{formatDateTime(v.created_at)}</span>
                  {v.reviewed_at ? (
                    <Badge family="success">{t("contracts.library.reviewedBadge")}</Badge>
                  ) : (
                    <Badge family="attention">{t("contracts.library.unreviewedBadge")}</Badge>
                  )}
                </summary>
                <p className="mt-2 font-medium">{v.title}</p>
                <DocView blocks={v.body.content} className="mt-2 text-sm" />
              </details>
            </li>
          ))}
        </ol>
      </Card>
    </>
  );
}
