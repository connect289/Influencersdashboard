import { getTranslations } from "next-intl/server";
import { AcceptTerms } from "@/components/creator/accept-terms";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { formatDate } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("terms.title") };
}

export default async function CreatorTerms() {
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("terms_pending");
  const pending = (data ?? []) as { id: string; kind: string; version: number; title: string; body: string; effective_at: string }[];
  return (
    <>
      <PageHeader title={t("terms.title")} description={t("terms.subtitle")} />
      {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      {!error && pending.length === 0 ? <EmptyState title={t("terms.allAccepted")} description={t("terms.allAcceptedHint")} /> : null}
      <div className="flex flex-col gap-4">
        {pending.map((p) => (
          <Card key={p.id}>
            <CardHeader title={p.title} description={t("terms.version", { version: p.version, date: formatDate(p.effective_at) })} />
            <div className="mb-4 max-h-80 overflow-y-auto rounded-xl bg-surface-2 p-4 text-sm whitespace-pre-line">{p.body}</div>
            <AcceptTerms id={p.id} />
          </Card>
        ))}
      </div>
    </>
  );
}
