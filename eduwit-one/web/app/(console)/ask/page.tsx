import { type Metadata } from "next";
import { AskForm, PinButton } from "@/components/brief/brief-forms.tsx";
import { StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, json } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { asksSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Ask" };

type Query = { tool?: string; args?: Record<string, unknown>; rows?: number; ok?: boolean; error?: string };
type Answer = { answer?: string; queries?: Query[] };

export default async function AskPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  // A question an Operate page suggests (?q=…), offered in the form and never sent by itself.
  const q = (await searchParams).q;
  const defaultQuestion = typeof q === "string" ? q.slice(0, 2000) : undefined;
  let asks;
  try {
    asks = await ui("ui_asks", asksSchema, { p_limit: 50 });
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Ask"
        description="A question to the AI worker, answered with fixed read-only tools it lists for you (it never writes SQL). The AI reads masked data only."
      />
      <Card>
        <CardBody>
          <AskForm defaultQuestion={defaultQuestion} />
        </CardBody>
      </Card>
      {asks.length === 0 ? (
        <Card>
          <Empty title="No questions yet" />
        </Card>
      ) : (
        <div className="grid gap-3">
          {asks.map((a) => {
            const r = (a.result ?? {}) as Answer;
            return (
              <Card key={a.id}>
                <CardHeader
                  title={a.question ?? "(no question)"}
                  description={`${a.asked_by ?? "?"} · ${ago(a.created_at)}`}
                  actions={<StatusBadge status={a.status} />}
                />
                <CardBody className="grid gap-2 text-sm">
                  {a.status === "done" && r.answer ? <p className="whitespace-pre-line">{r.answer}</p> : null}
                  {a.status === "pending" || a.status === "claimed" ? (
                    <p className="text-fg-muted">The AI worker is on it; an answer usually takes a minute or two.</p>
                  ) : null}
                  {a.status === "deferred" ? (
                    <p className="text-fg-muted">Waiting: {a.error ?? "deferred"}</p>
                  ) : a.error && a.status !== "done" ? (
                    <p className="text-p1">{a.error}</p>
                  ) : null}
                  {r.queries?.length ? (
                    <details>
                      <summary className="cursor-pointer">The tools it used ({r.queries.length})</summary>
                      <ul className="mt-2 grid gap-1 text-xs">
                        {r.queries.map((q, n) => (
                          <li key={n}>
                            <code>{q.tool ?? "?"}</code> <code className="text-fg-muted">{json(q.args ?? {})}</code>{" "}
                            {q.ok ? `${q.rows ?? 0} rows` : (q.error ?? "failed")}
                          </li>
                        ))}
                      </ul>
                    </details>
                  ) : null}
                  {a.status === "done" && !a.pinned ? <PinButton id={a.id} /> : null}
                  {a.pinned ? <p className="text-xs text-fg-muted">Pinned to a brief.</p> : null}
                </CardBody>
              </Card>
            );
          })}
        </div>
      )}
    </>
  );
}
