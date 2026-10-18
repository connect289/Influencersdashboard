import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { AUDIT_PAGE_SIZE, auditFilterSchema, auditQueryString, istDayEnd, istDayStart } from "@/lib/audit";
import { requireStaff } from "@/lib/auth/guards";
import { formatDateTime } from "@/lib/format";

interface AuditRow {
  id: number;
  at: string;
  actor_id: string | null;
  actor_role: string | null;
  entity_type: string;
  entity_id: string | null;
  action: string;
  before: unknown;
  after: unknown;
  ip: string | null;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.audit") };
}

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireStaff("audit.read");
  const t = await getTranslations();
  const f = auditFilterSchema.parse(await searchParams);
  let q = supabase
    .from("audit_log")
    .select("id, at, actor_id, actor_role, entity_type, entity_id, action, before, after, ip")
    .order("id", { ascending: false })
    .limit(AUDIT_PAGE_SIZE + 1);
  if (f.entity) q = q.eq("entity_type", f.entity);
  if (f.action) q = q.eq("action", f.action);
  if (f.actor) q = q.eq("actor_id", f.actor);
  if (f.record) q = q.eq("entity_id", f.record);
  if (f.from) q = q.gte("at", istDayStart(f.from));
  if (f.to) q = q.lt("at", istDayEnd(f.to));
  if (f.before) q = q.lt("id", f.before);
  const { data, error } = await q;
  const all = (data ?? []) as AuditRow[];
  const rows = all.slice(0, AUDIT_PAGE_SIZE);
  const hasMore = all.length > AUDIT_PAGE_SIZE;
  const actorIds = [...new Set(rows.map((r) => r.actor_id).filter((x): x is string => Boolean(x)))];
  const names = new Map<string, string>();
  if (actorIds.length) {
    const { data: people } = await supabase.from("staff_profiles").select("user_id, full_name").in("user_id", actorIds);
    for (const p of (people ?? []) as { user_id: string; full_name: string }[]) names.set(p.user_id, p.full_name);
  }
  const filtered = Boolean(f.entity ?? f.action ?? f.actor ?? f.record ?? f.from ?? f.to);
  return (
    <>
      <PageHeader title={t("nav.admin.audit")} description={t("audit.subtitle")} />
      <Card className="mb-4">
        <form className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6" method="get">
          <Input
            name="entity"
            defaultValue={f.entity}
            placeholder={t("audit.filters.entity")}
            aria-label={t("audit.filters.entity")}
          />
          <Input
            name="action"
            defaultValue={f.action}
            placeholder={t("audit.filters.action")}
            aria-label={t("audit.filters.action")}
          />
          <Input
            name="record"
            defaultValue={f.record}
            placeholder={t("audit.filters.record")}
            aria-label={t("audit.filters.record")}
          />
          <Input name="from" type="date" defaultValue={f.from} aria-label={t("audit.filters.from")} />
          <Input name="to" type="date" defaultValue={f.to} aria-label={t("audit.filters.to")} />
          <div className="flex gap-2">
            <Button type="submit" className="flex-1">
              {t("common.apply")}
            </Button>
            {filtered ? (
              <Button asChild variant="ghost">
                <Link href="/admin/audit">{t("common.clear")}</Link>
              </Button>
            ) : null}
          </div>
        </form>
      </Card>
      {error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      {!error && rows.length === 0 ? (
        filtered ? (
          <NoResults title={t("audit.noResults")} />
        ) : (
          <EmptyState title={t("audit.empty")} />
        )
      ) : null}
      {rows.length > 0 ? (
        <Card className="p-0 md:p-0">
          <Table>
            <thead>
              <tr>
                <Th>{t("audit.columns.when")}</Th>
                <Th>{t("audit.columns.who")}</Th>
                <Th>{t("audit.columns.what")}</Th>
                <Th>{t("audit.columns.change")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <Td className="whitespace-nowrap text-muted">{formatDateTime(r.at)}</Td>
                  <Td>
                    <span className="block font-medium">
                      {r.actor_id ? (names.get(r.actor_id) ?? t("audit.unknownActor")) : t("audit.system")}
                    </span>
                    <span className="block text-xs text-muted">
                      {r.actor_role}
                      {r.ip ? ` · ${r.ip}` : ""}
                    </span>
                  </Td>
                  <Td>
                    <Badge family="progress">{r.action}</Badge> <span className="text-sm">{r.entity_type}</span>
                    {r.entity_id ? (
                      <Link
                        href={`/admin/audit${auditQueryString({ record: r.entity_id })}`}
                        className="block max-w-48 truncate font-mono text-xs text-muted hover:underline"
                        title={t("audit.filters.recordHistory")}
                      >
                        {r.entity_id}
                      </Link>
                    ) : null}
                  </Td>
                  <Td>
                    <details>
                      <summary className="cursor-pointer text-sm text-primary">{t("audit.showChange")}</summary>
                      <div className="mt-2 grid gap-2 lg:grid-cols-2">
                        <pre className="max-h-48 overflow-auto rounded-lg bg-surface-2 p-2 text-xs whitespace-pre-wrap">
                          {r.before ? JSON.stringify(r.before, null, 2) : "—"}
                        </pre>
                        <pre className="max-h-48 overflow-auto rounded-lg bg-surface-2 p-2 text-xs whitespace-pre-wrap">
                          {r.after ? JSON.stringify(r.after, null, 2) : "—"}
                        </pre>
                      </div>
                    </details>
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
          <div className="flex justify-between gap-2 p-3">
            {f.before ? (
              <Button asChild variant="ghost" size="sm">
                <Link href={`/admin/audit${auditQueryString(f, { before: undefined })}`}>{t("common.newest")}</Link>
              </Button>
            ) : (
              <span />
            )}
            {hasMore ? (
              <Button asChild variant="secondary" size="sm">
                <Link href={`/admin/audit${auditQueryString(f, { before: rows.at(-1)?.id })}`}>
                  {t("common.older")}
                </Link>
              </Button>
            ) : null}
          </div>
        </Card>
      ) : null}
    </>
  );
}
