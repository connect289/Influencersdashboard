"use client";
// One change request: suggested clause wording (shown as a word diff against the current text) or a compensation
// counter-offer (each number from → to). Eduwit accepts, counters or rejects it; the requester can withdraw it.
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Textarea } from "@/components/ui/input";
import { useAction } from "@/components/ui/use-action";
import { decideClauseRequest, decideCompRequest, withdrawContractChange } from "@/lib/actions/contracts";
import type { CounterItem, CounterLine } from "@/lib/contracts/counter";
import { diffWords } from "@/lib/contracts/diff";
import { plainText, type Block, type RichDoc } from "@/lib/contracts/doc";
import { formatDateTime } from "@/lib/format";
import { changesFrom, CounterFields, formatCounterValue } from "./counter-form";
import { DocView } from "./doc-view";
import { RichEditor } from "./rich-editor";

export interface RequestView {
  id: string;
  kind: "clause" | "compensation";
  clause_key: string | null;
  proposed_body: RichDoc | null;
  note: string | null;
  from_side: "creator" | "agency";
  status: "pending" | "accepted" | "rejected" | "countered" | "withdrawn";
  created_at: string;
  decision_note: string | null;
}

export function WordDiff({ before, after }: { before: string; after: string }) {
  return (
    <p className="text-sm leading-relaxed whitespace-pre-wrap">
      {diffWords(before, after).map((op, i) =>
        op.op === "eq" ? (
          <span key={i}>{op.text}</span>
        ) : op.op === "ins" ? (
          <ins key={i} className="bg-success-soft text-success no-underline">
            {op.text}
          </ins>
        ) : (
          <del key={i} className="bg-danger-soft text-danger">
            {op.text}
          </del>
        ),
      )}
    </p>
  );
}

function ClauseCounter({ r, contractId }: { r: RequestView; contractId: string }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const initial = r.proposed_body ?? { type: "doc" as const, content: [] };
  const [doc, setDoc] = useState<RichDoc>(initial);
  const [note, setNote] = useState("");
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary" size="sm">
          {t("contracts.requests.counter")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("contracts.requests.counterTitle")}
        description={t("contracts.requests.counterClauseHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                decideClauseRequest({
                  requestId: r.id,
                  contractId,
                  decision: "countered",
                  body: doc,
                  note,
                }),
              () => setOpen(false),
            );
          }}
        >
          <RichEditor
            id={`ct-${r.id}`}
            label={t("contracts.requests.wording")}
            value={initial}
            onChange={setDoc}
            variables
          />
          <Field id={`ct-note-${r.id}`} label={t("contracts.requests.reply")} required>
            <Textarea
              id={`ct-note-${r.id}`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              minLength={2}
              maxLength={1000}
              required
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending}>
              {t("contracts.requests.sendCounter")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function CompCounter({
  r,
  contractId,
  items,
  lines,
}: {
  r: RequestView;
  contractId: string;
  items: readonly CounterItem[];
  lines: readonly CounterLine[];
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const [open, setOpen] = useState(false);
  const [values, setValues] = useState<Record<string, number>>(() =>
    Object.fromEntries(lines.filter((l) => l.from !== null).map((l) => [l.key, l.to])),
  );
  const [note, setNote] = useState("");
  const changes = changesFrom(items, values);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="secondary" size="sm">
          {t("contracts.requests.counter")}
        </Button>
      </DialogTrigger>
      <DialogContent
        title={t("contracts.requests.counterTitle")}
        description={t("contracts.requests.counterCompHint")}
        closeLabel={t("common.close")}
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run(
              () =>
                decideCompRequest({
                  requestId: r.id,
                  contractId,
                  decision: "countered",
                  terms: { changes },
                  note,
                }),
              () => setOpen(false),
            );
          }}
        >
          <CounterFields
            items={items}
            values={values}
            idPrefix={`cc-${r.id}`}
            onChange={(k, v) => setValues((p) => ({ ...p, [k]: v }))}
          />
          <Field id={`cc-note-${r.id}`} label={t("contracts.requests.reply")} required>
            <Textarea
              id={`cc-note-${r.id}`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              minLength={2}
              maxLength={1000}
              required
            />
          </Field>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || changes.length === 0}>
              {t("contracts.requests.sendCounter")}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function RequestCard({
  r,
  contractId,
  clauseTitle,
  currentBlocks,
  lines,
  items,
  canDecide,
  canWithdraw,
}: {
  r: RequestView;
  contractId: string;
  clauseTitle: string | null;
  currentBlocks: Block[] | null;
  lines: readonly CounterLine[];
  items: readonly CounterItem[];
  canDecide: boolean;
  canWithdraw: boolean;
}) {
  const t = useTranslations();
  const { pending, run } = useAction();
  const open = r.status === "pending";
  return (
    <article className="rounded-xl border border-line p-3">
      <header className="flex flex-wrap items-center gap-2">
        <span className="font-medium">
          {r.kind === "clause"
            ? t("contracts.requests.clauseTitle", { clause: clauseTitle ?? r.clause_key ?? "" })
            : t("contracts.requests.compTitle")}
        </span>
        <StatusBadge status={r.status} label={t(`contracts.requests.statuses.${r.status}`)} />
        <Badge>{t(`contracts.sides.${r.from_side}`)}</Badge>
        <span className="text-xs text-muted">{formatDateTime(r.created_at)}</span>
      </header>
      {r.kind === "clause" && r.proposed_body ? (
        <div className="mt-2 flex flex-col gap-2">
          {currentBlocks && open ? (
            <WordDiff before={plainText(currentBlocks)} after={plainText(r.proposed_body.content)} />
          ) : (
            <DocView blocks={r.proposed_body.content} className="text-sm" />
          )}
        </div>
      ) : null}
      {r.kind === "compensation" ? (
        <ul className="mt-2 flex flex-col gap-1 text-sm">
          {lines.map((l) => (
            <li key={l.key} className="flex flex-wrap justify-between gap-2">
              <span>{l.label}</span>
              <span className="tabular">
                {open ? (
                  <>{l.from === null ? t("contracts.requests.gone") : formatCounterValue(l.kind, l.from)} → </>
                ) : null}
                <strong>{formatCounterValue(l.kind, l.to)}</strong>
              </span>
            </li>
          ))}
        </ul>
      ) : null}
      {r.note ? (
        <p className="mt-2 text-sm text-muted">
          <span className="font-medium text-ink">{t("contracts.requests.noteLabel")}</span> {r.note}
        </p>
      ) : null}
      {r.decision_note ? (
        <p className="mt-1 text-sm text-muted">
          <span className="font-medium text-ink">{t("contracts.requests.decisionLabel")}</span> {r.decision_note}
        </p>
      ) : null}
      {open && (canDecide || canWithdraw) ? (
        <div className="mt-3 flex flex-wrap gap-2">
          {canDecide ? (
            <>
              <ConfirmDialog
                trigger={<Button size="sm">{t("contracts.requests.accept")}</Button>}
                title={t("contracts.requests.accept")}
                description={
                  r.kind === "clause"
                    ? t("contracts.requests.acceptClauseHint")
                    : t("contracts.requests.acceptCompHint")
                }
                actionLabel={t("contracts.requests.accept")}
                danger={false}
                pending={pending}
                onConfirm={(_x, close) =>
                  run(
                    () =>
                      r.kind === "clause"
                        ? decideClauseRequest({ requestId: r.id, contractId, decision: "accepted" })
                        : decideCompRequest({ requestId: r.id, contractId, decision: "accepted" }),
                    close,
                  )
                }
              />
              {r.kind === "clause" ? (
                <ClauseCounter r={r} contractId={contractId} />
              ) : (
                <CompCounter r={r} contractId={contractId} items={items} lines={lines} />
              )}
              <ConfirmDialog
                trigger={
                  <Button size="sm" variant="secondary">
                    {t("contracts.requests.reject")}
                  </Button>
                }
                title={t("contracts.requests.reject")}
                reasonLabel={t("contracts.requests.rejectReason")}
                actionLabel={t("contracts.requests.reject")}
                pending={pending}
                onConfirm={(reason, close) =>
                  run(
                    () =>
                      r.kind === "clause"
                        ? decideClauseRequest({
                            requestId: r.id,
                            contractId,
                            decision: "rejected",
                            note: reason,
                          })
                        : decideCompRequest({
                            requestId: r.id,
                            contractId,
                            decision: "rejected",
                            note: reason,
                          }),
                    close,
                  )
                }
              />
            </>
          ) : null}
          {canWithdraw ? (
            <ConfirmDialog
              trigger={
                <Button size="sm" variant="secondary">
                  {t("contracts.requests.withdraw")}
                </Button>
              }
              title={t("contracts.requests.withdraw")}
              actionLabel={t("contracts.requests.withdraw")}
              pending={pending}
              onConfirm={(_x, close) => run(() => withdrawContractChange(r.id, contractId), close)}
            />
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
