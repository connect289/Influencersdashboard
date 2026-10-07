"use client";
import { useState, useTransition } from "react";
import { LoaderCircle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { DecisionReplay } from "@/lib/routing-data";
import { pct } from "@/lib/segments";
import { replayDecision } from "../../actions";

/** Re-runs the decision from its logged seed and candidates and says whether it reproduces. */
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
            : r.reproduced !== undefined
              ? <>{r.reproduced ? <span className="text-success">Reproduced</span> : <span className="text-danger">Different result</span>}: {name(r.winner)} won {pct(r.selection_probability ?? null, 0)} of {r.draws} draws
                  (logged {name(r.logged_winner)}, {pct(r.logged_probability ?? null, 0)}).</>
              : <>Holdout draw {r.holdout_draw?.toFixed(4)} ({r.holdout ? "in the holdout" : "AI-steered"}), exploration draw {r.exploration_draw?.toFixed(4)}: {r.mode}.</>}
        </p>
      )}
    </div>
  );
}
