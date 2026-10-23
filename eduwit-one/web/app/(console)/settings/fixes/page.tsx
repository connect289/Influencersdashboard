import { type Metadata } from "next";
import Link from "next/link";
import { SettingEditor } from "@/components/settings/setting-editor.tsx";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { ago } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { actionsSchema, settingsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Fixes" };

export default async function FixesPage() {
  const me = await requireUser("/settings/fixes");
  let settings;
  let actions;
  try {
    [settings, actions] = await Promise.all([
      ui("ui_settings", settingsSchema),
      ui("ui_actions", actionsSchema, { p_limit: 500 }),
    ]);
  } catch (e) {
    return <PageError error={e} />;
  }
  const fixes = (settings.fixes?.value ?? {}) as Record<string, { enabled?: boolean } | unknown>;
  const ids = Object.keys(fixes).filter((k) => k.startsWith("FIX-"));
  return (
    <>
      <PageHeader
        title="Fixes"
        description="Each auto-fix ships switched off and runs as a dry run for the observation window (two weeks). Switching one on is the owner's decision, and nothing that touches allocation, money, live switches, partner mappings, prompts or versioned settings is ever a fix."
      />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {ids.map((id) => {
          const on = Boolean((fixes[id] as { enabled?: boolean })?.enabled);
          const runs = actions.rows.filter((a) => a.fix_id === id);
          return (
            <Card key={id}>
              <CardHeader title={id} actions={on ? <Badge tone="ok">on</Badge> : <Badge tone="off">off</Badge>} />
              <CardBody className="grid gap-1 text-sm">
                <p className="text-fg-muted">
                  {runs.length} run{runs.length === 1 ? "" : "s"} recorded ({runs.filter((r) => r.dry_run).length} dry)
                  {runs[0] ? `, last ${ago(runs[0].ran_at)}` : ""}
                </p>
                {runs.slice(0, 3).map((r) => (
                  <p key={r.id} className="flex items-center gap-2 text-xs">
                    <StatusBadge status={r.status} /> {r.dry_run ? "dry run" : "real"} · {ago(r.ran_at)}
                  </p>
                ))}
                <Link href={`/actions?fix=${id}`} className="text-xs underline">
                  Full history
                </Link>
              </CardBody>
            </Card>
          );
        })}
      </div>
      <Card>
        <CardHeader
          title="Switches and limits"
          description="enabled, per_tick and cooldown_min per fix; observation_started_at and observation_days for the window."
        />
        <CardBody>
          <SettingEditor name="fixes" value={JSON.stringify(fixes, null, 2)} readOnly={me.role !== "owner"} />
        </CardBody>
      </Card>
    </>
  );
}
