import { type Metadata } from "next";
import { AskForm, PinButton } from "@/components/brief/brief-forms.tsx";
import { StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Code, Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, json } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { asksSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Ask" };

type Answer = { answer?: string; queries?: Array<{ sql?: string; rows?: number }> };

export default async function AskPage() {
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
        description="A question to the AI worker, answered from read-only queries it shows you. The AI reads masked data only."
      />
      <Card>
        <CardBody>
          <AskForm />
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
                  {a.status === "pending" ? (
                    <p className="text-fg-muted">Waiting for the AI worker (phase 6).</p>
                  ) : null}
                  {a.error ? <p className="text-p1">{a.error}</p> : null}
                  {r.queries?.length ? (
                    <details>
                      <summary className="cursor-pointer">The queries it ran ({r.queries.length})</summary>
                      <Code className="mt-2">{json(r.queries)}</Code>
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
