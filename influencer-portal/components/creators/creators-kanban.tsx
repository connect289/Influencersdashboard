"use client";
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { CSS } from "@dnd-kit/utilities";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useOptimistic, useTransition } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { setCreatorStage } from "@/lib/actions/creators";
import { PIPELINE_STAGES, type CreatorListRow, type PipelineStage } from "@/lib/creators/crm";
import { formatCompact } from "@/lib/format";
import { cn } from "@/lib/utils";

function Card({ row, canWrite }: { row: CreatorListRow; canWrite: boolean }) {
  const t = useTranslations();
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: row.id,
    data: { stage: row.pipeline_stage },
    disabled: !canWrite,
  });
  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Translate.toString(transform) }}
      className={cn(
        "rounded-xl bg-surface p-3 shadow-[var(--shadow-card)] ring-1 ring-line",
        isDragging && "z-10 opacity-80 ring-primary",
        canWrite && "cursor-grab touch-none active:cursor-grabbing",
      )}
      {...attributes}
      {...listeners}
      aria-roledescription={t("creators.kanban.card")}
    >
      <Link
        href={`/admin/creators/${row.id}`}
        className="block truncate text-sm font-medium text-primary hover:underline"
        onPointerDown={(e) => e.stopPropagation()}
      >
        {row.display_name}
      </Link>
      <p className="truncate text-xs text-muted">@{row.handle}</p>
      <div className="mt-2 flex flex-wrap items-center gap-1 text-xs">
        {row.followers ? <Badge>{formatCompact(row.followers)}</Badge> : null}
        {row.owner_name ? <span className="text-muted">{row.owner_name.split(" ")[0]}</span> : null}
        {row.next_follow_up_at && new Date(row.next_follow_up_at) < new Date() ? (
          <Badge family="problem">{t("creators.kanban.overdue")}</Badge>
        ) : null}
      </div>
    </li>
  );
}

function Column({
  stage,
  rows,
  count,
  canWrite,
}: {
  stage: PipelineStage;
  rows: CreatorListRow[];
  count: number;
  canWrite: boolean;
}) {
  const t = useTranslations();
  const { setNodeRef, isOver } = useDroppable({ id: stage });
  return (
    <section
      ref={setNodeRef}
      aria-label={t(`creators.stages.${stage}`)}
      className={cn(
        "flex w-64 shrink-0 flex-col rounded-2xl bg-surface-2 p-2 transition-colors",
        isOver && "bg-primary-soft",
      )}
    >
      <h2 className="flex items-center justify-between px-1 pb-2 text-sm font-semibold">
        {t(`creators.stages.${stage}`)}
        <span className="text-xs font-normal text-muted tabular-nums">{count}</span>
      </h2>
      <ul className="flex min-h-24 flex-col gap-2">
        {rows.map((r) => (
          <Card key={r.id} row={r} canWrite={canWrite} />
        ))}
      </ul>
      {count > rows.length ? (
        <p className="px-1 pt-2 text-xs text-muted">
          {t("creators.kanban.more", { count: count - rows.length })}
        </p>
      ) : null}
    </section>
  );
}

/**
 * Pipeline board. Drag a card (mouse, touch, or keyboard: Space to pick up, arrows to move, Space to drop) to change
 * its stage. The move shows at once and rolls back if the server refuses it.
 */
export function CreatorsKanban({
  rows,
  counts,
  canWrite,
}: {
  rows: CreatorListRow[];
  counts: Record<string, number>;
  canWrite: boolean;
}) {
  const t = useTranslations();
  const [, start] = useTransition();
  const [optimistic, move] = useOptimistic(rows, (cur, m: { id: string; stage: string }) =>
    cur.map((r) => (r.id === m.id ? { ...r, pipeline_stage: m.stage } : r)),
  );
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 6 } }),
    useSensor(KeyboardSensor),
  );
  const onDragEnd = (e: DragEndEvent) => {
    const id = String(e.active.id);
    const to = e.over ? String(e.over.id) : null;
    const from = (e.active.data.current as { stage?: string } | undefined)?.stage;
    if (!to || to === from) return;
    start(async () => {
      move({ id, stage: to });
      const r = await setCreatorStage(id, to);
      if (r.ok) toast.success(r.message ?? "");
      else toast.error(r.error);
    });
  };
  const byStage = (s: string) => optimistic.filter((r) => r.pipeline_stage === s);
  const moved = (s: string) =>
    byStage(s).length - rows.filter((r) => r.pipeline_stage === s).length;
  return (
    <DndContext
      sensors={sensors}
      onDragEnd={onDragEnd}
      accessibility={{
        screenReaderInstructions: { draggable: t("creators.kanban.instructions") },
      }}
    >
      <div className="-mx-4 flex gap-3 overflow-x-auto px-4 pb-3 md:mx-0 md:px-0">
        {PIPELINE_STAGES.map((s) => (
          <Column
            key={s}
            stage={s}
            rows={byStage(s)}
            count={(counts[s] ?? 0) + moved(s)}
            canWrite={canWrite}
          />
        ))}
      </div>
    </DndContext>
  );
}
