import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { FollowUpsWidget } from "@/components/creators/follow-ups-widget";
import { TaskList } from "@/components/creators/tasks";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadPickers } from "@/lib/creators/staff-data";
import { loadTasks } from "@/lib/creators/tasks-data";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.tasks") };
}

export default async function TasksPage({
  searchParams,
}: {
  searchParams: Promise<{ show?: string }>;
}) {
  const { supabase, me } = await requireStaff();
  const t = await getTranslations();
  const show = (await searchParams).show;
  const scope =
    show === "all" && me.permissions.has("task.write") ? "all" : show === "done" ? "done" : "mine";
  const canWrite = me.permissions.has("task.write");
  const [tasks, pickers, follow] = await Promise.all([
    loadTasks(supabase, {
      status: scope === "done" ? "done" : "open",
      assignee: scope === "mine" || scope === "done" ? me.userId : undefined,
    }),
    loadPickers(supabase),
    me.permissions.has("creator.read")
      ? supabase.rpc("follow_ups_due", { p_scope: scope === "all" ? "all" : "mine", p_limit: 30 })
      : Promise.resolve({ data: null, error: null }),
  ]);
  const tabs = [
    { key: "mine", label: t("tasks.tabs.mine") },
    ...(canWrite ? [{ key: "all", label: t("tasks.tabs.all") }] : []),
    { key: "done", label: t("tasks.tabs.done") },
  ];
  return (
    <>
      <PageHeader title={t("nav.admin.tasks")} description={t("tasks.subtitle")} />
      <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
        <Card>
          <CardHeader title={t("tasks.title")} />
          <nav className="mb-3 flex gap-1" aria-label={t("tasks.title")}>
            {tabs.map((tab) => (
              <Link
                key={tab.key}
                href={tab.key === "mine" ? "/admin/tasks" : `/admin/tasks?show=${tab.key}`}
                aria-current={scope === tab.key ? "page" : undefined}
                className={cn(
                  "rounded-lg px-3 py-1.5 text-sm",
                  scope === tab.key
                    ? "bg-primary-soft font-medium text-primary"
                    : "text-muted hover:bg-surface-2",
                )}
              >
                {tab.label}
              </Link>
            ))}
          </nav>
          {tasks.error ? (
            <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
          ) : (
            <TaskList
              tasks={tasks.tasks}
              owners={pickers.owners}
              canWrite={canWrite && scope !== "done"}
            />
          )}
        </Card>
        {follow.data ? (
          <FollowUpsWidget items={follow.data} scope={scope === "all" ? "all" : "mine"} />
        ) : null}
      </div>
    </>
  );
}
