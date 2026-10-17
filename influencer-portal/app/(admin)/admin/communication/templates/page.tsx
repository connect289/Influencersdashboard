import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CommNav } from "@/components/communication/comm-nav";
import { TemplateEditor } from "@/components/communication/template-editor";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadTemplates } from "@/lib/communication/data";
import { env } from "@/lib/env";
import { EVENT_GROUPS } from "@/lib/notify/catalogue";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("communication.sections.templates") };
}

/** Notification templates (spec 14, Super Admin): every catalogue event, its versions, variables and preview. */
export default async function TemplatesPage({ searchParams }: { searchParams: Promise<{ event?: string }> }) {
  const { supabase, me } = await requireStaff("notification_template.write");
  const t = await getTranslations();
  const sp = await searchParams;
  const events = await loadTemplates(supabase).catch(() => null);
  const selected = events?.find((e) => e.event === sp.event) ?? null;
  return (
    <>
      <PageHeader
        title={t("communication.title")}
        description={t("communication.templates.subtitle")}
        help="/admin/help/super-admin#communication"
      />
      <CommNav current="templates" permissions={me.permissions} />
      {!events ? (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[280px_1fr]">
          <Card className="max-h-[70vh] overflow-y-auto">
            <nav aria-label={t("communication.templates.events")} className="flex flex-col gap-3">
              {EVENT_GROUPS.map((g) => {
                const list = events.filter((e) => e.group === g);
                if (!list.length) return null;
                return (
                  <div key={g}>
                    <p className="mb-1 text-xs font-semibold text-muted uppercase">{t(`notifications.groups.${g}`)}</p>
                    <ul className="flex flex-col">
                      {list.map((e) => (
                        <li key={e.event}>
                          <Link
                            href={`/admin/communication/templates?event=${encodeURIComponent(e.event)}`}
                            aria-current={selected?.event === e.event ? "page" : undefined}
                            className={cn(
                              "flex items-center justify-between gap-2 rounded-lg px-2 py-1 text-sm",
                              selected?.event === e.event ? "bg-primary-soft text-primary" : "hover:bg-surface-2",
                            )}
                            scroll={false}
                          >
                            <span className="truncate">
                              {t(
                                `notifications.events.${e.event.replace(/\./g, "_")}` as "notifications.events.announcement",
                              )}
                            </span>
                            {e.templates.some((x) => x.active) ? (
                              <span className="text-xs text-primary">{t("communication.templates.custom")}</span>
                            ) : null}
                          </Link>
                        </li>
                      ))}
                    </ul>
                  </div>
                );
              })}
            </nav>
          </Card>
          {selected ? (
            <TemplateEditor key={selected.event} ev={selected} liveMode={env().LIVE_MODE === "on"} />
          ) : (
            <EmptyState title={t("communication.templates.pick")} description={t("communication.templates.pickHint")} />
          )}
        </div>
      )}
    </>
  );
}
