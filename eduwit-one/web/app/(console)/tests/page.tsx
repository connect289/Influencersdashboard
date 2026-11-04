import { type Metadata } from "next";
import Link from "next/link";
import { TestControls } from "@/components/tests/test-controls.tsx";
import { appName } from "@/components/ui/labels.ts";
import { Badge, SeverityBadge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ago, ist, ms } from "@/lib/format.ts";
import { cn } from "@/lib/cn.ts";
import { ui } from "@/lib/ui/api.ts";
import { testsSchema, type TestRow } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Tests" };

/** The first failing step of a run, as "title: detail". */
function failure(steps: TestRow["runs"][number]["steps"]): string | null {
  const bad = steps.find((x) => x.ok === false);
  return bad ? `${bad.title ?? bad.key}: ${bad.detail ?? "failed"}` : null;
}

function median(xs: number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  const hi = s[m] ?? 0;
  return s.length % 2 ? hi : ((s[m - 1] ?? hi) + hi) / 2;
}

/**
 * Step timings (spec §10: "a slow step is seen before it fails"): for each step, the last run's time and the median of
 * its passes over the last 30 runs, as a bar against the step's timeout. One hue; a failed step is named in text.
 */
function StepTimings({ t }: { t: TestRow }) {
  if (t.step_defs.length === 0) return null;
  const last = t.runs[0];
  return (
    <div className="grid gap-1.5">
      <p className="text-xs font-medium text-fg-muted">
        Step timings: last run, and the median of passes (last 30 runs)
      </p>
      <ol className="grid gap-1.5">
        {t.step_defs.map((d) => {
          const lastStep = last?.steps.find((x) => x.key === d.key);
          const passes = t.runs.flatMap((r) =>
            r.steps.flatMap((x) => (x.key === d.key && x.ok && typeof x.ms === "number" ? [x.ms] : [])),
          );
          const med = median(passes);
          const shown = lastStep?.ms ?? med;
          const width = shown == null ? 0 : Math.min(100, Math.max(1, (shown / (d.timeout_s * 1000)) * 100));
          return (
            <li key={d.key} className="grid gap-0.5 text-xs sm:grid-cols-[14rem_1fr] sm:items-center sm:gap-3">
              <span className={cn("truncate", lastStep?.ok === false && "font-medium text-p1")}>
                {lastStep?.ok === false ? "✗ " : ""}
                {d.title}
              </span>
              <span className="flex min-w-0 items-center gap-2">
                <span className="h-2 w-24 shrink-0 rounded bg-surface-2 sm:w-40" aria-hidden="true">
                  <span className="block h-2 rounded bg-primary" style={{ width: `${width}%` }} />
                </span>
                <span className="truncate text-fg-muted tabular-nums">
                  {lastStep?.ms != null ? ms(lastStep.ms) : "—"} · median {med != null ? ms(med) : "—"} · limit{" "}
                  {d.timeout_s} s
                </span>
              </span>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

function Runs({ t }: { t: TestRow }) {
  if (t.runs.length === 0) return <p className="text-sm text-fg-muted">No runs yet.</p>;
  return (
    <ol className="flex flex-wrap gap-1" aria-label="Last 30 runs, newest first">
      {t.runs.map((r) => (
        <li
          key={r.id}
          title={`${ist(r.started_at)}: ${r.ok === null ? "running" : r.ok ? "passed" : "failed"} in ${ms(r.duration_ms)}`}
          className={cn(
            "inline-flex size-5 items-center justify-center rounded text-[10px] font-bold",
            r.ok === null ? "bg-off-bg text-off" : r.ok ? "bg-ok-bg text-ok" : "bg-p1-bg text-p1",
          )}
        >
          {r.ok === null ? "…" : r.ok ? "✓" : "✗"}
          <span className="sr-only">{r.ok === null ? "running" : r.ok ? "passed" : "failed"}</span>
        </li>
      ))}
    </ol>
  );
}

export default async function TestsPage() {
  let tests;
  try {
    tests = await ui("ui_tests", testsSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Tests"
        description="Synthetic journeys through the apps on the test identities only (is_test). A test whose identity is not set up yet shows as not configured, never as failing."
      />
      {tests.length === 0 ? (
        <Card>
          <Empty title="No tests in the catalogue">The catalogue is seeded by migration 0015.</Empty>
        </Card>
      ) : (
        <div className="grid gap-3">
          {tests.map((t) => {
            const last = t.runs[0];
            const why = last && last.ok === false ? (failure(last.steps) ?? last.error ?? null) : null;
            const missing = t.needs.filter((n) => !n.validated);
            return (
              <Card key={t.id} id={t.id}>
                <CardHeader
                  title={t.title}
                  description={`${t.id} · ${appName(t.app)} · ${t.seam ? `${t.seam} · ` : ""}${t.steps} steps · schedule ${t.schedule} (UTC) · timeout ${t.timeout_s} s`}
                  actions={
                    <>
                      <SeverityBadge severity={t.severity} />
                      {t.enabled ? (
                        <StatusBadge
                          status={last ? (last.ok === null ? "pending" : last.ok ? "passed" : "failed") : "pending"}
                        />
                      ) : (
                        <Badge tone="off">{t.disabled_reason?.startsWith("setup:") ? "not configured" : "off"}</Badge>
                      )}
                    </>
                  }
                />
                <CardBody className="grid gap-3">
                  {t.description ? <p className="text-sm text-fg-muted">{t.description}</p> : null}
                  <Runs t={t} />
                  <StepTimings t={t} />
                  {why ? <p className="text-sm text-p1">Last failure: {why}</p> : null}
                  {last ? (
                    <p className="text-xs text-fg-muted">
                      Last run {ago(last.started_at)} in {ms(last.duration_ms)}
                    </p>
                  ) : null}
                  {t.run_requested_at ? (
                    <p className="text-xs text-fg-muted">Run requested {ago(t.run_requested_at)}</p>
                  ) : null}
                  {!t.enabled && t.disabled_reason ? (
                    <p className="text-xs text-fg-muted">
                      Off: {t.disabled_reason}
                      {missing.length ? (
                        <>
                          {" "}
                          · waiting for{" "}
                          {missing.map((n, i) => (
                            <span key={n.item}>
                              {i ? ", " : ""}
                              <Link href={`/settings/setup#${n.item}`} className="underline">
                                {n.item}
                              </Link>
                            </span>
                          ))}
                        </>
                      ) : null}
                    </p>
                  ) : null}
                  <TestControls id={t.id} enabled={t.enabled} schedule={t.schedule} />
                </CardBody>
              </Card>
            );
          })}
        </div>
      )}
    </>
  );
}
