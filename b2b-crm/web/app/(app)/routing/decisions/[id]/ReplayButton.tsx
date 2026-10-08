"use client";
import { useState, useTransition } from "react";
import { LoaderCircle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { DecisionReplay } from "@/lib/routing-data";
import { pct } from "@/lib/segments";
import { replayDecision } from "../../actions";

/** Re-runs the decision from its logged seed and candidates and says whether it reproduces (b2b.decision_replay, C128).
 *  Addendum 3 decisions re-sort the stored scores and recompute the exploration lane; legacy decisions keep their M24 branches. */
export function ReplayButton({ id, names }: { id: number; names: Record<string, string> }) {
  const [busy, start] = useTransition();
  const [r, setR] = useState<DecisionReplay | { error: string } | null>(null);
  const name = (pid: number | null | undefined) => (pid == null ? "—" : names[String(pid)] ?? `partner #${pid}`);
  return (
    <div className="space-y-2">
      <Button size="sm" variant="secondary" disabled={busy} onClick={() => start(async () => {
        const x = await replayDecision(id);
        setR(x.ok ? x.replay : { error: x.error });
      })}>
        {busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />} Replay from the seed
      </Button>
      {r && (
        <p role="status" className="text-[12.5px] text-muted">
          {"error" in r ? <span className="text-danger">{r.error}</span>
            : !r.replayable ? <>Not replayable: {r.why}.</>
            : r.stage ? (
              <>
                {r.reproduced ? <span className="font-medium text-success">Reproduced</span> : <span className="font-medium text-danger">Different result</span>}: {name(r.winner)} wins
                {r.winner !== r.logged_winner && <> (logged: {name(r.logged_winner)})</>}
                {" · "}Stage {r.stage}
                {r.lane_applied
                  ? <> · exploration lane: draw {r.draw?.toFixed(4) ?? "—"} against a {pct(r.share, 0)} share{r.logged_draw != null && r.draw != null && Math.abs(r.logged_draw - r.draw) > 1e-9 && <> (logged {r.logged_draw.toFixed(4)})</>}</>
                  : <> · no exploration lane: the top score was chosen</>}
                {r.order && r.order.length > 1 && <> · order {r.order.map(name).join(" › ")}</>}
                {r.selection_probability != null && r.selection_probability < 1 && <> · chosen with probability {pct(r.selection_probability, 0)}</>}.
                {!r.reproduced && r.stage === "C" && <span className="block text-subtle">A Stage C decision mixed with a challenger model is a draw between two orderings, so it may not reproduce.</span>}
              </>
            )
            : r.reproduced !== undefined
              ? <>{r.reproduced ? <span className="text-success">Reproduced</span> : <span className="text-danger">Different result</span>}: {name(r.winner)} won {pct(r.selection_probability ?? null, 0)} of {r.draws} draws
                  (logged {name(r.logged_winner)}, {pct(r.logged_probability ?? null, 0)}). Legacy decision: seeded draws, before Addendum 3.</>
              : <>Legacy decision: holdout draw {r.holdout_draw?.toFixed(4)} ({r.holdout ? "in the holdout" : "AI-steered"}), exploration draw {r.exploration_draw?.toFixed(4)}: {r.mode}.</>}
        </p>
      )}
    </div>
  );
}
