import { type Metadata } from "next";
import { MuteForm, UnmuteButton } from "@/components/settings/admin-forms.tsx";
import { appNames } from "@/components/ui/labels.ts";
import { StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ist } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { mutesSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Mutes and maintenance" };

export default async function MaintenancePage() {
  let mutes;
  try {
    mutes = await ui("ui_mutes", mutesSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Mutes and maintenance"
        description="While muted, a check's or an app's incidents still record but nothing is sent. When the window ends, whatever is still failing alerts again."
      />
      <Card>
        <CardHeader title="Start a mute or a maintenance window" />
        <CardBody>
          <MuteForm apps={Object.entries(appNames)} />
        </CardBody>
      </Card>
      <Card>
        <CardHeader title="Mutes" description="Active first, then the last hundred." />
        {mutes.length === 0 ? (
          <Empty title="No mutes" />
        ) : (
          <ul className="divide-y divide-border text-sm">
            {mutes.map((m) => (
              <li key={m.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2">
                <span className="grid gap-0.5">
                  <span className="flex items-center gap-2">
                    <StatusBadge status={m.active ? "muted" : "expired"} /> {m.target_type}{" "}
                    <span className="font-medium">{m.target}</span>
                  </span>
                  <span className="text-xs text-fg-muted">
                    {ist(m.starts_at)} → {ist(m.ends_at)} · {m.reason} · {m.created_by}
                  </span>
                </span>
                {m.active ? <UnmuteButton id={m.id} /> : null}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
