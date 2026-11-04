"use client";
import { ActionForm } from "@/components/forms/action-form.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input, Select, Textarea } from "@/components/ui/field.tsx";
import { acknowledge, mute, rerunDeep, resolve } from "@/lib/actions/incidents.ts";
import { create as createProposal } from "@/lib/actions/proposals.ts";

type Props = { id: number; checkId: string; app: string; open: boolean; acknowledged: boolean };

/** What a person can do with an incident (spec §12): acknowledge, resolve with a note, mute, re-run triage, propose. */
export function IncidentActions({ id, checkId, app, open, acknowledged }: Props) {
  return (
    <div className="grid gap-4">
      {open && !acknowledged ? (
        <ActionForm action={acknowledge}>
          <input type="hidden" name="id" value={id} />
          <Button type="submit" variant="accent" className="w-full">
            Acknowledge
          </Button>
        </ActionForm>
      ) : null}
      {open ? (
        <details className="rounded-md border border-border p-3">
          <summary className="cursor-pointer text-sm font-medium">Resolve with a note</summary>
          <ActionForm action={resolve} className="mt-3">
            <input type="hidden" name="id" value={id} />
            <Field label="Resolution">
              <Select name="resolution" defaultValue="fixed">
                <option value="fixed">Fixed</option>
                <option value="false_positive">False positive</option>
                <option value="accepted">Accepted as is</option>
                <option value="manual">Other (say in the note)</option>
              </Select>
            </Field>
            <Field label="Note">
              <Textarea name="note" required minLength={3} placeholder="What was done, or why it is fine" />
            </Field>
            <Button type="submit">Resolve</Button>
          </ActionForm>
        </details>
      ) : null}
      <details className="rounded-md border border-border p-3">
        <summary className="cursor-pointer text-sm font-medium">Mute</summary>
        <ActionForm action={mute} className="mt-3">
          <Field label="What">
            <Select name="target_type" defaultValue="check">
              <option value="check">This check ({checkId})</option>
              <option value="app">The whole app ({app}): maintenance window</option>
            </Select>
          </Field>
          <input type="hidden" name="target" value={checkId} />
          <input type="hidden" name="app" value={app} />
          <Field label="For how many minutes">
            <Input name="minutes" type="number" min={1} max={10080} defaultValue={60} required />
          </Field>
          <Field label="Reason">
            <Input name="reason" required minLength={3} placeholder="Deploy in progress" />
          </Field>
          <p className="text-xs text-fg-muted">
            Incidents still record while muted; nothing is sent. When the mute ends, anything still failing alerts
            again.
          </p>
          <Button type="submit" variant="secondary">
            Mute
          </Button>
        </ActionForm>
      </details>
      <ActionForm action={rerunDeep}>
        <input type="hidden" name="id" value={id} />
        <Button type="submit" variant="secondary" className="w-full">
          Re-run triage on the deep model
        </Button>
      </ActionForm>
      <details className="rounded-md border border-border p-3">
        <summary className="cursor-pointer text-sm font-medium">Create a proposal</summary>
        <ActionForm action={createProposal} className="mt-3">
          <input type="hidden" name="incident_id" value={id} />
          <input type="hidden" name="app" value={app} />
          <Field label="Kind">
            <Select name="kind" defaultValue="fix">
              <option value="fix">Fix</option>
              <option value="config">Config</option>
              <option value="feature">Feature</option>
              <option value="cleanup">Cleanup</option>
            </Select>
          </Field>
          <Field label="Title">
            <Input name="title" required minLength={5} />
          </Field>
          <Field label="Why">
            <Textarea name="rationale" required minLength={10} />
          </Field>
          <Field
            label="The change, as JSON"
            hint='For example {"rpc": "b2b.retry_push", "args": {}, "touches": []}. "touches" names money, allocation, live_switches, partner_mappings, prompts or versioned_settings when it does; without it, a fix or config needs the owner.'
          >
            <Textarea name="change" className="font-mono text-xs" placeholder="{}" />
          </Field>
          <Field label="Risk">
            <Select name="risk" defaultValue="low">
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </Select>
          </Field>
          <Button type="submit" variant="secondary">
            Create proposal
          </Button>
        </ActionForm>
      </details>
    </div>
  );
}
