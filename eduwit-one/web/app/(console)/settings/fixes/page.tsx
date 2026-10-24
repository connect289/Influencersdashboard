import { type Metadata } from "next";
import Link from "next/link";
import { ActionRows } from "@/components/fixes/action-rows.tsx";
import { DryRunForm, FixSwitchForm } from "@/components/fixes/fix-forms.tsx";
import { Badge, SeverityBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader, Stat } from "@/components/ui/card.tsx";
import { appName, fixModes } from "@/components/ui/labels.ts";
import { PageError } from "@/components/ui/page-error.tsx";
import { Banner, Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, ist } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { fixesSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Fixes" };

export default async function FixesPage() {
  const me = await requireUser("/settings/fixes");
  let data;
  try {
    data = await ui("ui_fixes", fixesSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  const { window: w, fixes } = data;
  return (
    <>
      <PageHeader
        title="Fixes"
        description="The auto-fixes of spec §8. Each ships switched off and, for the observation window, runs as a dry run on every matching incident, recording what it would have done. Switch one on when its dry runs show it would have done the right thing. Nothing that touches allocation, money, live switches, partner mappings, prompts or versioned settings is ever a fix."
      />
      {w.running ? (
        <Banner tone="p3">
          {w.started_at
            ? `Observation window: dry runs only until ${ist(w.until ?? w.started_at)} (${w.days} days from ${ist(w.started_at)}).`
            : `The ${w.days}-day observation window starts with the first tick that runs the fixes.`}{" "}
          No fix can be switched on before it ends.
        </Banner>
      ) : (
        <Banner tone="p3">
          The observation window ended {w.until ? ist(w.until) : ""}. A fix with a dry run of its own can now be
          switched on by the owner.
        </Banner>
      )}
      <div className="grid gap-4">
        {fixes.map((f) => {
          const mode = fixModes[f.mode];
          return (
            <Card key={f.id} id={f.id}>
              <CardHeader
                title={
                  <span className="flex flex-wrap items-center gap-2">
                    {f.id}
                    {f.settings.enabled ? <Badge tone="ok">on</Badge> : <Badge tone="off">off</Badge>}
                    {mode ? <Badge tone={mode.tone}>{mode.label}</Badge> : null}
                  </span>
                }
                description={`${f.title} · ${appName(f.app)} · tried on ${f.checks.join(", ")}`}
              />
              <CardBody className="grid gap-4">
                <div className="grid gap-3 md:grid-cols-2">
                  <div className="grid gap-2 text-sm">
                    <p>
                      <span className="font-medium">When:</span> {f.trigger}.
                    </p>
                    <p>
                      <span className="font-medium">What:</span> {f.what}
                    </p>
                    {mode ? <p className="text-xs text-fg-muted">{mode.hint}</p> : null}
                    <p>
                      <span className="font-medium">Rights:</span> {f.grants}.{" "}
                      {f.grants_state.ok ? (
                        f.app_functions.length > 0 ? (
                          <Badge tone="ok">granted</Badge>
                        ) : null
                      ) : (
                        <Badge tone="p2">missing {f.grants_state.missing.join(", ")}</Badge>
                      )}
                    </p>
                    <p>
                      <span className="font-medium">Rollback:</span> {f.rollback}.
                    </p>
                  </div>
                  <div className="grid content-start gap-3">
                    <div className="grid grid-cols-3 gap-3">
                      <Stat label="Dry runs" value={f.counts.dry_runs} />
                      <Stat
                        label="Real runs"
                        value={f.counts.runs}
                        hint={f.counts.failed ? `${f.counts.failed} failed` : undefined}
                      />
                      <Stat
                        label="Held / escalated"
                        value={`${f.counts.held} / ${f.counts.escalated}`}
                        hint={f.counts.last_at ? `last ${ago(f.counts.last_at)}` : "never ran"}
                      />
                    </div>
                    {f.open_incidents.length > 0 ? (
                      <div className="grid gap-2">
                        <p className="text-xs font-medium">Open incidents it is tried on</p>
                        {f.open_incidents.map((i) => (
                          <div key={i.id} className="flex flex-wrap items-center gap-2 text-sm">
                            <SeverityBadge severity={i.severity} />
                            <Link href={`/incidents/${i.id}`} className="underline">
                              #{i.id} {i.check_id}
                            </Link>
                            <DryRunForm fix={f.id} incident={i.id} label="Dry run now" />
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="text-xs text-fg-muted">No open incident of {f.checks.join(" or ")} right now.</p>
                    )}
                  </div>
                </div>
                {f.recent.length > 0 ? (
                  <div className="grid gap-1">
                    <p className="text-xs font-medium">
                      Latest rows ·{" "}
                      <Link href={`/actions?fix=${f.id}`} className="underline">
                        full history
                      </Link>
                    </p>
                    <ActionRows rows={f.recent} />
                  </div>
                ) : (
                  <Empty title="No dry run yet">
                    It records one the first time {f.checks.join(" or ")} has an open incident it applies to.
                  </Empty>
                )}
                {me.role === "owner" ? (
                  <details>
                    <summary className="cursor-pointer text-sm font-medium">
                      Switch and limits ({f.settings.enabled ? "on" : "off"}, {f.settings.per_tick} a run, cooldown{" "}
                      {f.settings.cooldown_min} min)
                    </summary>
                    <div className="mt-2">
                      <FixSwitchForm
                        fix={f.id}
                        enabled={f.settings.enabled}
                        perTick={f.settings.per_tick}
                        cooldownMin={f.settings.cooldown_min}
                        canEnable={f.can_enable}
                      />
                    </div>
                  </details>
                ) : (
                  <p className="text-xs text-fg-muted">
                    Switch {f.settings.enabled ? "on" : "off"}, {f.settings.per_tick} a run, cooldown{" "}
                    {f.settings.cooldown_min} min. Only the owner changes these.
                  </p>
                )}
              </CardBody>
            </Card>
          );
        })}
      </div>
    </>
  );
}
