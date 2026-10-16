"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { leaderboardOpt } from "@/app/s/perf-actions";
import { inr } from "@/lib/format";

type Row = { name: string; me: boolean; actual: { enrollments: number; commission: number; connected: number } };

/** The month's standing (spec B11.3). Names show only for those who opted in; everyone else is "A counsellor". */
export function Leaderboard({ rows, visible }: { rows: Row[]; visible: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const toggle = () => start(async () => {
    const r = await leaderboardOpt(!visible);
    if (!r.ok) return void toast.error(r.error);
    if (r.notice) toast.success(r.notice);
    router.refresh();
  });
  return (
    <div className="stack" style={{ gap: 6 }}>
      <ol className="list" style={{ margin: 0, paddingLeft: 0, listStyle: "none" }}>
        {rows.slice(0, 8).map((r, i) => (
          <li key={i} className="row small" style={{ padding: "4px 0", fontWeight: r.me ? 650 : undefined }}>
            <span className="num muted" style={{ width: 18 }}>{i + 1}</span>
            <span className="grow ellipsis">{r.me ? `${r.name} (you)` : r.name}</span>
            <span className="num">{r.actual.enrollments} enr.</span>
            <span className="num muted" style={{ minWidth: 72, textAlign: "right" }}>{inr(r.actual.commission)}</span>
          </li>
        ))}
      </ol>
      <label className="row small"><input type="checkbox" checked={visible} disabled={busy} onChange={toggle} /> Show my name to the team</label>
    </div>
  );
}
