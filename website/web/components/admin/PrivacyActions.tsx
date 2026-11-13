"use client";

import { useActionState } from "react";
import {
  fulfilPrivacyAction,
  privacyDoneAction,
  privacySystemAction,
  type AdminFormState,
} from "@/app/admin/content-actions";

/**
 * The forms of Admin → Privacy requests (web17, D-096). Each shows its own pending state and refusal; a success reloads
 * the page with a status line. Client components only for that: every rule is checked again on the server and in the
 * database.
 */
const input = "border-border bg-surface h-9 rounded-[var(--radius-md)] border px-2 text-sm";
const quiet = "border-border h-9 rounded-full border px-3 text-sm disabled:opacity-50";

function Refusal({ state }: { state: AdminFormState }) {
  return state?.error ? (
    <p role="alert" className="text-danger text-xs">
      {state.error}
    </p>
  ) : null;
}

/**
 * The irreversible step, behind a disclosure that names what goes and a confirmation that must be ticked.
 * `kind` delete: erase the website's data. `kind` export: record that the downloaded copy was sent.
 */
export function FulfilForm({
  id,
  kind,
  email,
  holds,
  leads,
}: {
  id: number;
  kind: "delete" | "export";
  email: string;
  /** "2 verified forms, 1 Witty chat, …" */
  holds: string;
  leads: number;
}) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(fulfilPrivacyAction, null);
  const erase = kind === "delete";
  const box = `confirm-${id}`;
  return (
    <details className="border-border rounded-[var(--radius-md)] border p-3">
      <summary className={`cursor-pointer text-sm font-medium ${erase ? "text-danger" : ""}`}>
        {erase ? "Erase this account's website data…" : "Record the copy as sent…"}
      </summary>
      <form action={action} className="mt-3 grid gap-3 text-sm">
        <input type="hidden" name="id" value={id} />
        <input type="hidden" name="kind" value={kind} />
        {erase ? (
          <>
            <p>
              This permanently erases what the website holds for <strong>{email}</strong>: the account (name, email,
              phone number), {holds}, and any queued emails to this address. The person is signed out everywhere.
            </p>
            <p className="text-muted">
              Kept without their identity: the consent record (marked withdrawn), this request and its audit trail, and
              bare counts for the funnels.{" "}
              {leads > 0
                ? "The CRMs are not touched: after this step, erase the lead in Spark and in the B2B CRM and tick each one here. The request is done only then."
                : "No CRM lead is linked to this account, so the request is done with this step and a confirmation email is sent."}
            </p>
          </>
        ) : (
          <p>
            Confirm that you downloaded the copy and sent it to <strong>{email}</strong> from the company mailbox.{" "}
            {leads > 0
              ? "The CRM part of the copy is separate: send it from Spark and the B2B CRM and tick each one here."
              : "No CRM lead is linked to this account, so the request is done with this step."}
          </p>
        )}
        <label htmlFor={box} className="flex items-start gap-2">
          <input id={box} name="confirm" type="checkbox" required className="mt-0.5 size-4" />
          <span>
            {erase
              ? "I checked that this request came from this signed-in account. Erase it; this cannot be undone."
              : "I sent the downloaded copy to this address."}
          </span>
        </label>
        <div>
          <button
            type="submit"
            disabled={pending}
            className={
              erase
                ? "border-danger text-danger h-9 rounded-full border px-4 text-sm font-medium disabled:opacity-50"
                : "bg-primary text-on-primary h-9 rounded-full px-4 text-sm font-medium disabled:opacity-50"
            }
          >
            {pending ? (erase ? "Erasing…" : "Saving…") : erase ? "Erase website data now" : "Copy sent"}
          </button>
        </div>
        <Refusal state={state} />
      </form>
    </details>
  );
}

/** Tick one CRM after the work was done there (or say why it does not apply), with a note. */
export function SystemForm({
  id,
  system,
  label,
  erase,
}: {
  id: number;
  system: "spark" | "b2b";
  label: string;
  erase: boolean;
}) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(privacySystemAction, null);
  const note = `note-${system}-${id}`;
  return (
    <form action={action} className="mt-1 grid gap-2">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="system" value={system} />
      <div className="flex flex-wrap items-center gap-2">
        <label className="sr-only" htmlFor={note}>
          Note for {label}
        </label>
        <input
          id={note}
          name="note"
          required
          minLength={3}
          maxLength={300}
          placeholder="What was done there, and its reference"
          className={`${input} w-72 max-w-full`}
        />
        <button name="state" value="done" disabled={pending} className={quiet}>
          {pending ? "Saving…" : erase ? "Erased there" : "Copy sent from there"}
        </button>
        <button name="state" value="not_applicable" disabled={pending} className={quiet}>
          Not applicable
        </button>
      </div>
      <Refusal state={state} />
    </form>
  );
}

/** Reject a request, or mark an opt-out request done. A delete / copy request is never marked done here. */
export function CloseForm({ id, canMarkDone }: { id: number; canMarkDone: boolean }) {
  const [state, action, pending] = useActionState<AdminFormState, FormData>(privacyDoneAction, null);
  const note = `note-${id}`;
  return (
    <form action={action} className="mt-2 grid gap-2">
      <input type="hidden" name="id" value={id} />
      <div className="flex flex-wrap items-center gap-2">
        <label className="sr-only" htmlFor={note}>
          Note
        </label>
        <input
          id={note}
          name="note"
          maxLength={500}
          placeholder={canMarkDone ? "Note (what was done)" : "Why it is rejected"}
          className={input}
        />
        {canMarkDone ? (
          <button
            name="status"
            value="done"
            disabled={pending}
            className="bg-primary text-on-primary h-9 rounded-full px-3 disabled:opacity-50"
          >
            Mark done
          </button>
        ) : null}
        <button name="status" value="rejected" disabled={pending} className={quiet}>
          Reject
        </button>
      </div>
      <Refusal state={state} />
    </form>
  );
}
