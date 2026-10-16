import Link from "next/link";

export type Bucket = "not_worked" | "overdue" | "today" | "upcoming";
export const BUCKETS: [Bucket, string][] = [["not_worked", "Not worked yet"], ["overdue", "Overdue"], ["today", "Due today"], ["upcoming", "Upcoming"]];

/** The four follow-up buckets (spec B8.3). Red numbers mean work is late. */
export function FollowupCards({ counts, active, query = "" }: { counts: Record<Bucket, number>; active?: Bucket; query?: string }) {
  return (
    <div className="fu-cards">
      {BUCKETS.map(([k, label]) => (
        <Link
          key={k}
          href={`/s/followups?b=${k}${query}`}
          className={`fu-card${(k === "overdue" || k === "not_worked") && counts[k] > 0 ? " alert" : ""}`}
          aria-pressed={active ? active === k : undefined}
          aria-current={active === k ? "page" : undefined}
          style={{ textDecoration: "none", color: "inherit" }}
        >
          <b>{counts[k] ?? 0}</b>
          <span>{label}</span>
        </Link>
      ))}
    </div>
  );
}
