import Link from "next/link";
import { Card, CardBody, CardHeader, Stat } from "@/components/ui/card.tsx";
import { Empty } from "@/components/ui/state.tsx";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table.tsx";
import { ago, num } from "@/lib/format.ts";
import type { AppErrors } from "@/lib/ui/schemas.ts";

/** The app's own server-error check (B2B-ERR, ONE-ERR, …), as the Checks list has it. */
export type ErrorCheck = { id: string; app: string; enabled: boolean; disabled_reason: string | null };

/**
 * "Server errors, last 24 h" on an app's page (0041, D-141): the counts the app itself reported through
 * one.app_error_report, read with one.ui_app_errors. Routes are templates and messages are masked in the database;
 * nothing here names a person. `errors` is null when the read failed; `failure` then says why.
 */
export function AppErrorsCard({
  errors,
  failure,
  check,
}: {
  errors: AppErrors | null;
  failure: string | null;
  check: ErrorCheck | null;
}) {
  const over = errors ? errors.last_15m > errors.limit_15m : false;
  return (
    <Card>
      <CardHeader
        title={`Server errors, last ${errors?.hours ?? 24} h`}
        description={
          <>
            Counted by the app itself, per page route and error name, and reported at most once a minute.
            {check ? (
              <>
                {" "}
                <Link href={`/settings/checks?app=${check.app}#${check.id}`} className="underline">
                  {check.id}
                </Link>{" "}
                {check.enabled
                  ? `fails above ${errors ? num(errors.limit_15m) : "the limit of"} errors in 15 minutes.`
                  : "is switched off, so nobody is alerted."}
              </>
            ) : null}
          </>
        }
      />
      {!errors ? (
        <CardBody>
          <p role="alert" className="text-sm text-p1">
            {failure ?? "The error counts could not be loaded."}
          </p>
        </CardBody>
      ) : errors.total === 0 ? (
        <Empty title="None reported">
          {check && !check.enabled
            ? "This app does not report its errors yet."
            : "An app reports only when it throws, and only from its deployment. The host's logs hold each error's line."}
        </Empty>
      ) : (
        <>
          <CardBody className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Stat label={`Errors in ${errors.hours} h`} value={num(errors.total)} />
            <Stat
              label="Last 15 minutes"
              value={<span className={over ? "text-p1" : undefined}>{num(errors.last_15m)}</span>}
              hint={`limit ${num(errors.limit_15m)}`}
            />
            <Stat label="Route and error pairs" value={num(errors.pairs)} />
            <Stat label="Last error" value={<span className="text-base">{ago(errors.last_seen)}</span>} />
          </CardBody>
          <Table>
            <THead>
              <TR>
                <TH>Route</TH>
                <TH>Error</TH>
                <TH className="text-right">Count</TH>
                <TH className="text-right">Last</TH>
              </TR>
            </THead>
            <TBody>
              {errors.top.map((e) => (
                <TR key={`${e.route}\n${e.error}`}>
                  <TD className="max-w-[18rem] text-xs break-all">{e.route}</TD>
                  <TD className="min-w-[12rem]">
                    <span className="font-medium">{e.error}</span>
                    {e.kind ? <span className="text-xs text-fg-muted"> · {e.kind}</span> : null}
                    {e.message ? <p className="text-xs break-words text-fg-muted">{e.message}</p> : null}
                    {e.digest ? <p className="text-xs text-fg-muted">digest {e.digest}</p> : null}
                  </TD>
                  <TD className="text-right tabular-nums">{num(e.n)}</TD>
                  <TD className="text-right text-xs whitespace-nowrap text-fg-muted">{ago(e.last_seen)}</TD>
                </TR>
              ))}
            </TBody>
          </Table>
          {errors.pairs > errors.top.length ? (
            <p className="border-t border-border px-4 py-2 text-xs text-fg-muted">
              The {errors.top.length} busiest of {num(errors.pairs)} pairs. &quot;(overflow)&quot; counts errors whose
              route was not kept apart.
            </p>
          ) : null}
        </>
      )}
    </Card>
  );
}
