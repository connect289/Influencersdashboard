import { type Metadata } from "next";
import Link from "next/link";
import { SecretForm, ValidateButton } from "@/components/settings/setup-forms.tsx";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { credentialAvailable, missingCredentials } from "@/lib/clients/credentials.ts";
import { ago, ist } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { setupSchema, type SetupItem } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Setup" };

// A value the app reads that is in neither Vault nor this deployment's environment means what the item unblocks cannot
// run here, whatever an earlier validation (the build's preflight, with its own credentials) recorded (D-108).
function status(i: SetupItem, missing: string[]): string {
  if (missing.length) return "value_missing";
  if (i.state.validated) return "validated";
  return i.state.status ?? "unfilled";
}

export default async function SetupPage() {
  const me = await requireUser("/settings/setup");
  let items;
  try {
    items = await ui("ui_setup", setupSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  const missing = new Map(items.map((i) => [i.id, missingCredentials(i.secrets)]));
  const lacking = (i: SetupItem) => missing.get(i.id) ?? [];
  const open = items.filter((i) => !i.state.validated || lacking(i).length > 0).length;
  return (
    <>
      <PageHeader
        title="Setup"
        description={`Everything Eduwit One can use but does not have yet. A check, test or fix that waits for an item shows as not configured, never as failing; validating the item switches it on. ${open} of ${items.length} still open.`}
      />
      <div className="grid gap-3">
        {items.map((i) => (
          <Card key={i.id} id={i.id}>
            <CardHeader
              title={i.title}
              description={`${i.id} · filled by the ${i.who}`}
              actions={
                <>
                  <StatusBadge status={status(i, lacking(i))} />
                  {i.validate ? <ValidateButton id={i.id} /> : null}
                  {!i.state.validated || lacking(i).length ? (
                    <Link
                      href={`/ask?q=${encodeURIComponent(`How do I fill Setup item ${i.id}, step by step, and what does it unblock?`)}`}
                      className="text-sm underline"
                    >
                      Ask the AI how
                    </Link>
                  ) : null}
                </>
              }
            />
            <CardBody className="grid gap-2 text-sm">
              {lacking(i).length ? (
                <p className="text-p2">
                  {lacking(i).join(", ")} {lacking(i).length === 1 ? "is" : "are"} in neither Vault nor this
                  deployment&apos;s environment, so what this item unblocks cannot run here
                  {i.state.validated ? ", although it was validated earlier" : ""}.{" "}
                  {me.role === "owner" ? "Paste the value below, then press Validate." : "The owner pastes the value."}
                </p>
              ) : null}
              {i.how ? <p>{i.how}</p> : null}
              {i.unblocks.length ? (
                <p>
                  <span className="text-fg-muted">Unblocks: </span>
                  {i.unblocks.join(", ")}
                </p>
              ) : null}
              {i.waiting.length ? (
                <p>
                  <span className="text-fg-muted">Checks waiting for it: </span>
                  {i.waiting.map((c, n) => (
                    <span key={c}>
                      {n ? ", " : ""}
                      <Link href={`/settings/checks#${c}`} className="underline">
                        {c}
                      </Link>
                    </span>
                  ))}
                </p>
              ) : null}
              {i.state.detail ? <p className="text-fg-muted">{i.state.detail}</p> : null}
              {i.state.fix && !i.state.validated ? <p className="text-fg-muted">To fix: {i.state.fix}</p> : null}
              {i.state.validated_at ? (
                <p className="text-xs text-fg-muted" title={ist(i.state.validated_at)}>
                  Last validated {ago(i.state.validated_at)}
                  {i.state.ran ? ` · ${i.state.ran}` : ""}
                </p>
              ) : null}
              {i.secrets.length ? (
                <div className="grid gap-2 border-t border-border pt-2">
                  {i.secrets.map((s) => (
                    <div key={s.name} className="grid gap-1">
                      <p className="flex items-center gap-2">
                        Vault <code className="text-xs">{s.name}</code>{" "}
                        {s.present ? (
                          <Badge tone="ok">present</Badge>
                        ) : credentialAvailable(s.name, false) ? (
                          <Badge tone="ok">set in the environment</Badge>
                        ) : (
                          <Badge tone="off">missing</Badge>
                        )}
                      </p>
                      {me.role === "owner" ? <SecretForm name={s.name} /> : null}
                    </div>
                  ))}
                </div>
              ) : null}
            </CardBody>
          </Card>
        ))}
      </div>
    </>
  );
}
