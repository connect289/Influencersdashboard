"use client";
import { useState, useTransition } from "react";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { riskTone } from "@/components/ui/labels.ts";
import { decideChatAction, type ChatActionResult } from "@/lib/actions/chat.ts";
import { json } from "@/lib/format.ts";

export type ActionCardData = {
  id: number;
  tool: string;
  args: Record<string, unknown>;
  summary: string;
  risk: "low" | "medium" | "high";
  status: "proposed" | "confirmed" | "done" | "failed" | "declined" | "expired";
  error?: string | null;
};

/**
 * An action the assistant proposed: what it would do, with Confirm and Decline. Confirming runs the one page function
 * it names, as you, and the card shows the outcome. Nothing runs until the button is pressed.
 */
export function ActionCard({ action, onDecided }: { action: ActionCardData; onDecided?: (a: ActionCardData) => void }) {
  const [state, setState] = useState<ActionCardData>(action);
  const [result, setResult] = useState<ChatActionResult | null>(null);
  const [pending, start] = useTransition();
  const waiting = state.status === "proposed";

  function decide(decision: "confirm" | "decline") {
    start(async () => {
      const form = new FormData();
      form.set("id", String(state.id));
      form.set("decision", decision);
      let r: ChatActionResult;
      try {
        r = await decideChatAction(undefined, form);
      } catch {
        r = { ok: false, error: "That did not work. Try again." };
      }
      setResult(r);
      const status = (r.status ??
        (r.ok ? (decision === "decline" ? "declined" : "done") : "failed")) as ActionCardData["status"];
      const next = { ...state, status, error: r.ok ? null : r.error };
      setState(next);
      onDecided?.(next);
    });
  }

  return (
    <div
      className="grid gap-2 rounded-md border border-border bg-surface p-3 text-sm"
      role="group"
      aria-label={`Action: ${state.summary}`}
    >
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={riskTone[state.risk] ?? "neutral"}>{state.risk} risk</Badge>
        <StatusBadge status={state.status === "proposed" ? "waiting for you" : state.status} />
        <code className="text-xs text-fg-muted">{state.tool}</code>
      </div>
      <p className="font-medium">{state.summary}</p>
      {Object.keys(state.args).length ? (
        <details>
          <summary className="cursor-pointer text-xs text-fg-muted">The exact arguments</summary>
          <pre className="mt-1 max-h-48 overflow-auto rounded bg-surface-2 p-2 font-mono text-xs whitespace-pre-wrap">
            {json(state.args)}
          </pre>
        </details>
      ) : null}
      {waiting ? (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => decide("confirm")} disabled={pending}>
            Confirm and run
          </Button>
          <Button size="sm" variant="secondary" onClick={() => decide("decline")} disabled={pending}>
            Decline
          </Button>
          <span className="self-center text-xs text-fg-muted">Runs as you, with your role; it is in Audit.</span>
        </div>
      ) : null}
      {result ? (
        result.ok ? (
          <p role="status" className="text-ok">
            {result.message}
          </p>
        ) : (
          <p role="alert" className="text-p1">
            {result.error}
          </p>
        )
      ) : state.error ? (
        <p className="text-p1">{state.error}</p>
      ) : null}
    </div>
  );
}
