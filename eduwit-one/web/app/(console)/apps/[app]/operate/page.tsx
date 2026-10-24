import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DryRunForm } from "@/components/fixes/fix-forms.tsx";
import { IconExternal } from "@/components/icons.tsx";
import { appName, fixModes, fixProof } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader, Stat } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Banner, Empty, PageHeader } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ago } from "@/lib/format.ts";
import { embeds } from "@/lib/embeds/index.ts";
import { appJobs, OPERATE, readiness } from "@/lib/operate/index.ts";
import { ui, UiError } from "@/lib/ui/api.ts";
import {
  checksSchema,
  embedSchema,
  fixesSchema,
  fixStatesSchema,
  heartbeatsSchema,
  incidentRowSchema,
  pageOf,
  settingsSchema,
  setupSchema,
  testsSchema,
} from "@/lib/ui/schemas.ts";
import { z } from "zod";

export const metadata: Metadata = { title: "Operate" };

const cronRows = z.array(
  z.looseObject({
    job: z.string(),
    schedule: z.string(),
    active: z.boolean(),
    last: z.string().nullable(),
    at: z.string().nullable(),
    error: z.string().nullable().optional(),
  }),
);

// Each read fails on its own: the page still renders what it could read, and says what it could not.
async function part<T>(p: Promise<T>): Promise<{ data: T | null; error: string | null }> {
  try {
    return { data: await p, error: null };
  } catch (e) {
    return { data: null, error: e instanceof UiError ? e.message : "could not be read" };
  }
}

export default async function OperatePage({ params }: { params: Promise<{ app: string }> }) {
  const key = (await params).app;
  const app = OPERATE[key];
  if (!app) notFound();
  const reads = await Promise.all([
    part(ui("ui_setup", setupSchema)),
    part(ui("ui_fixes", fixesSchema)),
    part(ui("ui_heartbeats", heartbeatsSchema)),
    part(ui("ui_checks", checksSchema, { p_app: key })),
    part(ui("ui_tests", testsSchema)),
    part(ui("ui_embed", embedSchema, { p_panel: "platform.cron" })),
    part(ui("ui_settings", settingsSchema)),
    part(ui("ui_incidents", pageOf(incidentRowSchema), { p_status: "open", p_app: key, p_limit: 20 })),
    part(ui("ui_fix_states", fixStatesSchema)),
  ]);
  const [setup, fixes, heartbeats, checks, tests, cron, settings, incidents, fixStates] = reads;
  if (setup.error && fixes.error && checks.error) return <PageError error={new UiError("unavailable", setup.error)} />;
  const items = setup.data ?? [];
  const ready = readiness(app, items);
  const byId = new Map(items.map((i) => [i.id, i]));
  const appFixes = (fixes.data?.fixes ?? []).filter((f) => app.fixes.includes(f.id));
  const fixStateOf = new Map((fixStates.data ?? []).map((s) => [s.fix_id, s]));
  const window = fixes.data?.window ?? null;
  const beats = (heartbeats.data ?? []).filter((h) => h.app === key);
  const appTests = (tests.data ?? []).filter((t) => app.tests.includes(t.id));
  const jobs = cron.data?.ok ? appJobs(app, cronRows.catch([]).parse(cron.data.data)) : [];
  const hosts = (settings.data?.hosts?.value ?? {}) as Record<string, string | undefined>;
  const links = (
    embeds[key]?.links({
      hosts,
      chatwootAccount: (settings.data?.chatwoot?.value as { account_id?: string } | undefined)?.account_id,
      wittyWorkflow: (settings.data?.n8n?.value as { witty_workflow_id?: string } | undefined)?.witty_workflow_id,
    }) ?? []
  ).filter((l): l is { label: string; href: string } => Boolean(l.href));
  const checkById = new Map((checks.data ?? []).map((c) => [c.id, c]));
  const failing = (checks.data ?? []).filter((c) => c.enabled && c.last_status && c.last_status !== "ok");
  const secrets = new Map(items.flatMap((i) => i.secrets).map((s) => [s.name, s.present]));
  const name = appName(key);
  const asks = [
    `What does ${name} still need before Eduwit One watches it fully, and in what order?`,
    `Which ${name} checks failed in the last 7 days, and what did each one see?`,
    `What would each fix for ${name} have done this week, from its dry runs?`,
  ];
  const errors = reads.map((p) => p.error).filter(Boolean);
  return (
    <>
      <PageHeader
        title={`${name}: set up and run`}
        description={`What ${name} needs, what Eduwit One sees of it right now, what it can do for it, and what stays in the app. Reads only: every change is made in the app itself or on Settings → Setup.`}
        actions={
          <>
            <Link
              href={`/apps/${key}`}
              className="inline-flex min-h-9 items-center gap-1 rounded-md border border-border bg-surface px-3 text-sm hover:bg-surface-2"
            >
              Its panels
            </Link>
            {links.map((l) => (
              <a
                key={l.label}
                href={l.href}
                target="_blank"
                rel="noreferrer"
                className="inline-flex min-h-9 items-center gap-1 rounded-md border border-border bg-surface px-3 text-sm hover:bg-surface-2"
              >
                {l.label} <IconExternal size={14} />
              </a>
            ))}
          </>
        }
      />
      {errors.length ? (
        <Banner tone="p2">
          Some of this page could not be read ({errors.length} of {reads.length} reads); what loaded is shown.
        </Banner>
      ) : null}
      {window?.running && appFixes.length ? (
        <Banner tone="p3">
          The fixes&apos; observation window runs until {window.until ? ago(window.until).replace("in ", "") : "?"}:
          every fix below records a dry run only.
        </Banner>
      ) : null}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader
            title="What it needs"
            description={`Setup items this app needs: ${ready.done} of ${ready.total} validated. A check, test or fix waiting for one shows as not configured, never as failing.`}
            actions={
              <Badge tone={ready.missing.length ? "p2" : "ok"}>
                {ready.done}/{ready.total}
              </Badge>
            }
          />
          <ul className="divide-y divide-border">
            {app.needs.map((id) => {
              const i = byId.get(id);
              const status = i ? (i.state.validated ? "validated" : (i.state.status ?? "unfilled")) : "unknown";
              return (
                <li key={id} className="flex flex-wrap items-center gap-2 px-4 py-2 text-sm">
                  <StatusBadge status={status} />
                  <Link href={`/settings/setup#${id}`} className="min-w-0 flex-1 truncate underline">
                    {i?.title ?? id}
                  </Link>
                  <span className="text-xs text-fg-muted">{i?.who ?? ""}</span>
                </li>
              );
            })}
          </ul>
        </Card>
        <Card>
          <CardHeader title="Right now" />
          <CardBody className="grid grid-cols-2 gap-3">
            <Link href={`/incidents?app=${key}`} className="rounded-md hover:bg-surface-2">
              <Stat label="Open incidents" value={incidents.data?.rows.length ?? "—"} />
            </Link>
            <Stat
              label="Heartbeats"
              value={beats.length ? `${beats.filter((b) => b.ok).length}/${beats.length}` : "—"}
              hint={
                beats.filter((b) => !b.enabled).length
                  ? `${beats.filter((b) => !b.enabled).length} wait for Setup`
                  : undefined
              }
            />
            <Link href={`/settings/checks?app=${key}`} className="rounded-md hover:bg-surface-2">
              <Stat
                label="Checks on"
                value={checks.data ? checks.data.filter((c) => c.enabled).length : "—"}
                hint={failing.length ? `${failing.length} failing` : undefined}
              />
            </Link>
            <Stat
              label="Cron jobs"
              value={app.cronPrefixes.length ? jobs.length : "none here"}
              hint={
                jobs.filter((j) => j.last === "failed").length
                  ? `${jobs.filter((j) => j.last === "failed").length} failed last`
                  : undefined
              }
            />
          </CardBody>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="First time, in order"
          description="What has to exist once for the app to run and for Eduwit One to watch it."
        />
        <ol className="divide-y divide-border">
          {app.firstTime.map((s, n) => {
            const i = s.setup ? byId.get(s.setup) : undefined;
            return (
              <li key={s.title} className="grid gap-1 px-4 py-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">
                    {n + 1}. {s.title}
                  </span>
                  {i ? <StatusBadge status={i.state.validated ? "validated" : (i.state.status ?? "unfilled")} /> : null}
                  {s.setup ? (
                    <Link href={`/settings/setup#${s.setup}`} className="text-xs underline">
                      Setup → {s.setup}
                    </Link>
                  ) : null}
                </div>
                <p className="text-fg-muted">{s.detail}</p>
                {i && !i.state.validated && i.state.fix ? (
                  <p className="text-xs text-fg-muted">To fix: {i.state.fix}</p>
                ) : null}
              </li>
            );
          })}
        </ol>
      </Card>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader
            title="Heartbeats"
            description="Components that stopped reporting open a P1 or P2 (HB-* checks)."
          />
          {beats.length === 0 ? (
            <Empty title="No heartbeat is read for this app" />
          ) : (
            <ul className="divide-y divide-border">
              {beats.map((b) => (
                <li key={b.component} className="flex flex-wrap items-center gap-2 px-4 py-2 text-sm">
                  <StatusBadge
                    status={!b.enabled ? "not_configured" : b.ok ? "ok" : b.never_seen ? "pending" : "fail"}
                  />
                  <Link href={`/settings/checks#${b.check_id}`} className="min-w-0 flex-1 truncate underline">
                    {b.component}
                  </Link>
                  <span className="text-xs text-fg-muted">
                    {b.last_ok_at
                      ? `ok ${ago(b.last_ok_at)}`
                      : b.disabled_reason
                        ? `waits for ${b.disabled_reason.replace("setup:", "Setup ")}`
                        : "never seen"}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardHeader
            title="Its own timers"
            description={
              app.cronPrefixes.length
                ? "The app's pg_cron jobs and their last finished run (PLAT-01, PLAT-02 watch them)."
                : "This app has no pg_cron job in the shared database."
            }
          />
          {app.cronPrefixes.length === 0 ? (
            <Empty title={key === "witty" ? "Witty runs in n8n" : "Nothing scheduled here"}>
              {key === "witty"
                ? "Its timer is the n8n workflow&apos;s; see the n8n heartbeats above."
                : "Its jobs run in its own hosting."}
            </Empty>
          ) : cron.error || !cron.data?.ok ? (
            <Empty title="The cron list could not be read">{cron.error ?? cron.data?.error ?? ""}</Empty>
          ) : jobs.length === 0 ? (
            <Empty title="No job with this app's prefix" />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>Job</TH>
                  <TH>Schedule</TH>
                  <TH>Last run</TH>
                </TR>
              </THead>
              <TBody>
                {jobs.map((j) => (
                  <TR key={j.job}>
                    <TD className="text-xs">
                      {j.job}
                      {!j.active ? <Badge tone="off">inactive</Badge> : null}
                    </TD>
                    <TD className="text-xs text-fg-muted">{j.schedule}</TD>
                    <TD className="text-xs">
                      <StatusBadge status={j.last ?? "never"} /> {j.at ? ago(j.at) : ""}
                      {j.error ? <div className="text-p1">{j.error}</div> : null}
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          )}
        </Card>
      </div>

      <Card>
        <CardHeader
          title="What Eduwit One can do for it"
          description="The fixes of spec §8 that act on this app. Off until the owner switches one on after the observation window; a dry run records what it would do."
          actions={
            <Link href="/settings/fixes" className="text-sm underline">
              Settings → Fixes
            </Link>
          }
        />
        {appFixes.length === 0 ? (
          <Empty title="No fix acts on this app">
            {app.key === "influencer" || app.key === "one" ? "Everything is done in the app or by a person." : ""}
          </Empty>
        ) : (
          <ul className="divide-y divide-border">
            {appFixes.map((f) => {
              const mode = fixModes[f.mode];
              const st = fixStateOf.get(f.id);
              const trial = Boolean(st && !st.paused && f.settings.enabled && !st.proven);
              return (
                <li key={f.id} className="grid gap-1 px-4 py-3 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <Link href={`/settings/fixes#${f.id}`} className="font-medium underline">
                      {f.id}
                    </Link>
                    <Badge tone={f.settings.enabled ? "ok" : "off"}>{f.settings.enabled ? "on" : "off"}</Badge>
                    {mode ? <Badge tone={mode.tone}>{mode.label}</Badge> : null}
                    {st?.paused ? <Badge tone={fixProof.paused.tone}>{fixProof.paused.label}</Badge> : null}
                    {trial ? <Badge tone={fixProof.trial.tone}>{fixProof.trial.label}</Badge> : null}
                    {!f.grants_state.ok ? <Badge tone="p2">rights missing</Badge> : null}
                    <span className="text-xs text-fg-muted">
                      {f.counts.dry_runs} dry runs · {f.counts.runs} runs · {f.counts.held} held · {f.counts.escalated}{" "}
                      did not hold
                    </span>
                  </div>
                  <p className="text-fg-muted">{f.what}</p>
                  {f.open_incidents.length ? (
                    <div className="flex flex-wrap items-center gap-2">
                      {f.open_incidents.map((i) => (
                        <span key={i.id} className="flex items-center gap-2">
                          <Link href={`/incidents/${i.id}`} className="underline">
                            #{i.id} {i.check_id}
                          </Link>
                          {i.stopped ? <Badge tone="p2">stopped</Badge> : null}
                          <DryRunForm fix={f.id} incident={i.id} label="Dry run now" />
                        </span>
                      ))}
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader title="When a check fires: the first place to look" />
          <ul className="divide-y divide-border">
            {app.whenFires.map((w) => {
              const c = checkById.get(w.check);
              return (
                <li key={w.check} className="grid gap-1 px-4 py-2 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <Link href={`/settings/checks#${w.check}`} className="font-medium underline">
                      {w.check}
                    </Link>
                    {c ? <SeverityBadge severity={c.severity} /> : null}
                    {c ? <StatusBadge status={c.enabled ? (c.last_status ?? "pending") : "not_configured"} /> : null}
                    {c?.open_incident ? (
                      <Link href={`/incidents/${c.open_incident}`} className="text-xs underline">
                        open incident #{c.open_incident}
                      </Link>
                    ) : null}
                  </div>
                  <p className="text-fg-muted">{w.look}</p>
                </li>
              );
            })}
          </ul>
        </Card>
        <Card>
          <CardHeader
            title="Synthetic tests"
            description="Each switches on by itself when the Setup items it needs are validated."
          />
          {appTests.length === 0 ? (
            <Empty title="No test for this app" />
          ) : (
            <ul className="divide-y divide-border">
              {appTests.map((t) => (
                <li key={t.id} className="flex flex-wrap items-center gap-2 px-4 py-2 text-sm">
                  <StatusBadge
                    status={
                      t.enabled
                        ? t.runs[0]?.ok === false
                          ? "failed"
                          : t.runs[0]
                            ? "passed"
                            : "pending"
                        : "not_configured"
                    }
                  />
                  <Link href="/tests" className="min-w-0 flex-1 truncate underline">
                    {t.id}: {t.title}
                  </Link>
                  {!t.enabled && t.needs.length ? (
                    <span className="text-xs text-fg-muted">
                      waits for{" "}
                      {t.needs
                        .filter((n) => !n.validated)
                        .map((n) => n.item)
                        .join(", ")}
                    </span>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Card>
          <CardHeader title="Every day" />
          <ol className="grid gap-2 px-4 py-3 text-sm">
            {app.daily.map((d, n) => (
              <li key={d}>
                {n + 1}. {d}
              </li>
            ))}
          </ol>
        </Card>
        <Card>
          <CardHeader
            title="Its secrets"
            description="Rotate on Settings → Setup (paste, validate); RUNBOOK.md says where each is issued."
          />
          {app.secrets.length === 0 ? (
            <Empty title="Eduwit One holds no secret for this app" />
          ) : (
            <ul className="divide-y divide-border">
              {app.secrets.map((s) => (
                <li key={s} className="flex items-center gap-2 px-4 py-2 text-sm">
                  <StatusBadge status={secrets.get(s) ? "validated" : secrets.has(s) ? "unfilled" : "unknown"} />
                  <code className="text-xs">{s}</code>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardHeader title="Stays in the app" description="Eduwit One links to these and never does them." />
          <ul className="grid gap-2 px-4 py-3 text-sm text-fg-muted">
            {[...app.inTheApp, ...(embeds[key]?.gaps ?? [])].map((g) => (
              <li key={g}>{g}</li>
            ))}
          </ul>
        </Card>
      </div>

      <Card>
        <CardHeader
          title="Ask the AI"
          description="Each opens Ask with the question filled in; nothing is sent until you press Ask. The AI reads masked data through fixed tools and never changes anything."
        />
        <ul className="grid gap-2 px-4 py-3 text-sm sm:grid-cols-3">
          {asks.map((q) => (
            <li key={q}>
              <Link
                href={`/ask?q=${encodeURIComponent(q)}`}
                className="block rounded-md border border-border px-3 py-2 hover:bg-surface-2"
              >
                {q}
              </Link>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
