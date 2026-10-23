import { type Metadata } from "next";
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

/** The first failing step's message, from a run's step results. */
function failure(steps: unknown): string | null {
  if (!Array.isArray(steps)) return null;
  const bad = steps.find(
    (s): s is { name?: string; error?: string; ok?: boolean } =>
      typeof s === "object" && s !== null && (s as { ok?: boolean }).ok === false,
  );
  return bad ? `${bad.name ?? "a step"}: ${bad.error ?? "failed"}` : null;
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
          <Empty title="No tests in the catalogue yet">The synthetic journeys arrive with phase 5.</Empty>
        </Card>
      ) : (
        <div className="grid gap-3">
          {tests.map((t) => {
            const last = t.runs[0];
            const why = last && last.ok === false ? failure(last.steps) : null;
            return (
              <Card key={t.id} id={t.id}>
                <CardHeader
                  title={t.title}
                  description={`${t.id} · ${appName(t.app)} · ${t.steps} steps · schedule ${t.schedule} · timeout ${t.timeout_s} s`}
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
                  <Runs t={t} />
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
                    <p className="text-xs text-fg-muted">Off: {t.disabled_reason}</p>
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
