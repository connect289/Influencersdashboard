"use client";
import { Plus } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input, Select, Textarea } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { saveTask, setTaskStatus } from "@/lib/actions/creators";
import { istToIso, TASK_PRIORITIES } from "@/lib/creators/crm";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { Option } from "./creator-filters";

export interface TaskRow {
  id: string;
  title: string;
  description: string | null;
  assignee_id: string | null;
  assignee_name: string | null;
  due_at: string | null;
  priority: string;
  status: string;
  related_type: string | null;
  related_id: string | null;
  related_label: string | null;
}

type Priority = (typeof TASK_PRIORITIES)[number];

export function TaskDialog({
  owners,
  related,
  initial,
  trigger,
}: {
  owners: Option[];
  related?: { type: "creator"; id: string };
  initial?: TaskRow;
  trigger: ReactNode;
}) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const { pending, run } = useAction();
  const due = initial?.due_at ? new Date(initial.due_at) : null;
  const ist = due ? new Date(due.getTime() + 330 * 60_000).toISOString() : "";
  const [v, setV] = useState({
    title: initial?.title ?? "",
    description: initial?.description ?? "",
    assigneeId: initial?.assignee_id ?? "",
    date: ist.slice(0, 10),
    time: ist ? ist.slice(11, 16) : "10:00",
    priority: (initial?.priority ?? "normal") as Priority,
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent
        title={initial ? t("tasks.edit") : t("tasks.add")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                saveTask({
                  id: initial?.id,
                  title: v.title,
                  description: v.description,
                  assigneeId: v.assigneeId,
                  dueAt: v.date ? istToIso(v.date, v.time) : "",
                  priority: v.priority,
                  relatedType: related?.type,
                  relatedId: related?.id,
                }),
              () => {
                setOpen(false);
                if (!initial) setV((x) => ({ ...x, title: "", description: "", date: "" }));
              },
            );
          }}
        >
          <Field id="t-title" label={t("tasks.fields.title")} required>
            <Input
              id="t-title"
              value={v.title}
              onChange={(e) => setV({ ...v, title: e.target.value })}
              required
              minLength={2}
              maxLength={200}
            />
          </Field>
          <Field id="t-desc" label={t("tasks.fields.description")}>
            <Textarea
              id="t-desc"
              value={v.description}
              onChange={(e) => setV({ ...v, description: e.target.value })}
              maxLength={4000}
            />
          </Field>
          <div className="grid gap-3 md:grid-cols-2">
            <Field id="t-assignee" label={t("tasks.fields.assignee")}>
              <Select
                id="t-assignee"
                value={v.assigneeId}
                onChange={(e) => setV({ ...v, assigneeId: e.target.value })}
              >
                <option value="">{t("tasks.unassigned")}</option>
                {owners.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="t-priority" label={t("tasks.fields.priority")}>
              <Select
                id="t-priority"
                value={v.priority}
                onChange={(e) => setV({ ...v, priority: e.target.value as Priority })}
              >
                {TASK_PRIORITIES.map((p) => (
                  <option key={p} value={p}>
                    {t(`tasks.priorities.${p}`)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id="t-date" label={t("tasks.fields.dueDate")}>
              <Input
                id="t-date"
                type="date"
                value={v.date}
                onChange={(e) => setV({ ...v, date: e.target.value })}
              />
            </Field>
            <Field id="t-time" label={t("tasks.fields.dueTime")}>
              <Input
                id="t-time"
                type="time"
                value={v.time}
                onChange={(e) => setV({ ...v, time: e.target.value })}
                disabled={!v.date}
              />
            </Field>
          </div>
          <Button type="submit" disabled={pending || v.title.trim().length < 2}>
            {t("common.save")}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** A list of tasks with complete / reopen, used on the Tasks page and the Creator 360 page. */
export function TaskList({
  tasks,
  owners,
  canWrite,
  related,
  showRelated = true,
}: {
  tasks: TaskRow[];
  owners: Option[];
  canWrite: boolean;
  related?: { type: "creator"; id: string };
  showRelated?: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  return (
    <div className="flex flex-col gap-3">
      {canWrite ? (
        <div>
          <TaskDialog
            owners={owners}
            related={related}
            trigger={
              <Button size="sm" variant="secondary">
                <Plus /> {t("tasks.add")}
              </Button>
            }
          />
        </div>
      ) : null}
      {tasks.length === 0 ? (
        <EmptyState title={t("tasks.empty")} />
      ) : (
        <ul className="flex flex-col divide-y divide-line">
          {tasks.map((task) => {
            const overdue =
              task.status === "open" && task.due_at && new Date(task.due_at) < new Date();
            return (
              <li key={task.id} className="flex items-start gap-3 py-3">
                <input
                  type="checkbox"
                  className="mt-1 size-4 accent-[var(--primary)]"
                  checked={task.status === "done"}
                  disabled={pending || task.status === "cancelled"}
                  aria-label={
                    task.status === "done"
                      ? t("tasks.reopen", { title: task.title })
                      : t("tasks.complete", { title: task.title })
                  }
                  onChange={(e) =>
                    run(() => setTaskStatus(task.id, e.target.checked ? "done" : "open"))
                  }
                />
                <div className="min-w-0 flex-1">
                  <p
                    className={cn(
                      "text-sm font-medium",
                      task.status === "done" && "text-muted line-through",
                    )}
                  >
                    {task.title}
                  </p>
                  <p className="flex flex-wrap gap-x-3 text-xs text-muted">
                    {task.assignee_name ? (
                      <span>{task.assignee_name}</span>
                    ) : (
                      <span>{t("tasks.unassigned")}</span>
                    )}
                    {task.due_at ? (
                      <span className={cn(overdue && "font-medium text-danger")}>
                        {t("tasks.due", { date: formatDateTime(task.due_at) })}
                      </span>
                    ) : null}
                    {showRelated && task.related_type === "creator" && task.related_id ? (
                      <Link
                        href={`/admin/creators/${task.related_id}`}
                        className="text-primary hover:underline"
                      >
                        {task.related_label ?? t("tasks.relatedCreator")}
                      </Link>
                    ) : null}
                  </p>
                </div>
                {task.priority === "high" ? (
                  <Badge family="attention">{t("tasks.priorities.high")}</Badge>
                ) : null}
                {canWrite && task.status === "open" ? (
                  <TaskDialog
                    owners={owners}
                    initial={task}
                    trigger={
                      <Button size="sm" variant="ghost">
                        {t("common.edit")}
                      </Button>
                    }
                  />
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
