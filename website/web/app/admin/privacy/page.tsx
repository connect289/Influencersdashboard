import { Suspense } from "react";
import { AdminShell, Card } from "@/components/admin/AdminShell";
import { CloseForm, FulfilForm, SystemForm } from "@/components/admin/PrivacyActions";
import {
  KIND_LABEL,
  STATE_LABEL,
  SYSTEM_LABEL,
  checklist,
  countsSummary,
  leadLine,
  privacyError,
  websiteDone,
  type PrivacyRequest,
} from "@/lib/admin/privacy";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { errorFields, log } from "@/lib/server/log";

export const metadata = { title: "Privacy requests" };

const DONE_LINE: Record<string, string> = {
  erased: "Website data erased. Now erase the lead in each CRM listed on the request and tick it.",
  sent: "Recorded: the copy was sent.",
  ticked: "Ticked. The request stays open until every system is done.",
  completed: "Request completed.",
  already: "That step was already done; nothing changed.",
  done: "Marked done.",
  rejected: "Request rejected.",
};

const day = (t: string) => new Date(t).toLocaleDateString("en-IN", { timeZone: "Asia/Kolkata" });

/** One open delete / copy request: what it covers, the explicit step, then the checklist of systems. */
function Fulfilment({ r }: { r: PrivacyRequest }) {
  const erase = r.kind === "delete";
  if (!websiteDone(r)) {
    const p = r.preview;
    const problem = p?.requester_problem ?? null;
    const blocked = erase && (p?.other_open.length ?? 0) > 0;
    const downloaded = r.systems?.website?.downloaded_at;
    return (
      <div className="mt-2 grid gap-2">
        {problem ? (
          <p role="alert" className="text-danger">
            {privacyError(problem)}
          </p>
        ) : (
          <>
            <p className="text-muted">
              The website holds for this account: {countsSummary(p?.counts)}.{" "}
              {(p?.leads.length ?? 0) > 0
                ? "Shared leads its enquiries reached:"
                : "Its enquiries reached no shared lead."}
            </p>
            {(p?.leads.length ?? 0) > 0 ? (
              <ul className="text-muted list-disc pl-5">
                {p?.leads.map((l) => (
                  <li key={l.lead_id}>{leadLine(l)}</li>
                ))}
              </ul>
            ) : null}
            {blocked ? (
              <p className="text-amber-text">{privacyError("other_requests_open")}</p>
            ) : (
              <>
                {erase ? null : (
                  <p>
                    {/* a plain link (no prefetch): each download is written to the audit log */}
                    <a href={`/admin/privacy/${r.id}/export`} className="text-accent font-medium underline">
                      Download the copy (JSON)
                    </a>{" "}
                    <span className="text-muted">
                      {downloaded ? `Downloaded ${day(downloaded)}. ` : ""}Send it to {r.email_norm} from the company
                      mailbox, then record it as sent.
                    </span>
                  </p>
                )}
                <FulfilForm
                  id={r.id}
                  kind={erase ? "delete" : "export"}
                  email={r.email_norm}
                  holds={countsSummary(p?.counts)}
                  leads={p?.leads.length ?? 0}
                />
              </>
            )}
          </>
        )}
        <CloseForm id={r.id} canMarkDone={false} />
      </div>
    );
  }
  return (
    <div className="mt-2 grid gap-2">
      {(r.leads?.length ?? 0) > 0 ? (
        <ul className="text-muted list-disc pl-5">
          {r.leads?.map((l) => (
            <li key={l.lead_id}>{leadLine(l)}</li>
          ))}
        </ul>
      ) : null}
      <ul className="grid gap-2">
        {checklist(r).map(({ key, entry }) => (
          <li key={key}>
            <span aria-hidden className={entry.state === "pending" ? "text-amber-text" : "text-success"}>
              {entry.state === "pending" ? "○" : "✓"}
            </span>{" "}
            <strong>{SYSTEM_LABEL[key]}</strong>: {STATE_LABEL[entry.state ?? "pending"]}
            {key === "website"
              ? (erase ? " (erased" : " (copy sent") + (entry.at ? ` ${day(entry.at)}` : "") + ")"
              : ""}
            {entry.by ? <span className="text-muted"> by {entry.by}</span> : null}
            {entry.note ? <span className="text-muted"> · {entry.note}</span> : null}
            {key !== "website" && entry.state === "pending" ? (
              <SystemForm id={r.id} system={key} label={SYSTEM_LABEL[key]} erase={erase} />
            ) : null}
          </li>
        ))}
      </ul>
      {erase ? null : (
        <p>
          <a href={`/admin/privacy/${r.id}/export`} className="text-accent underline">
            Download the copy again (JSON)
          </a>
        </p>
      )}
    </div>
  );
}

async function View({ searchParams }: { searchParams: Promise<{ ok?: string; request?: string }> }) {
  // Student emails: super admins only (they process the requests).
  const [s, sp] = await Promise.all([requireAdmin("super_admin"), searchParams]);
  let rows: PrivacyRequest[] | null = null;
  try {
    rows = await rpc<PrivacyRequest[]>("web_admin_privacy_requests");
  } catch (err) {
    log("error", "admin.privacy_list_failed", errorFields(err));
  }
  const line = sp.ok && Object.hasOwn(DONE_LINE, sp.ok) ? DONE_LINE[sp.ok] : undefined;
  const which = sp.request && /^\d{1,12}$/.test(sp.request) ? `Request #${sp.request}: ` : "";
  return (
    <AdminShell session={s} title="Privacy requests">
      <p className="text-muted max-w-3xl text-sm">
        Deletion, copy-of-data and opt-out requests from signed-in student accounts (DPDP). Complete them within 30
        days. A deletion or copy request is fulfilled here for the website&apos;s own data; the lead in Spark and in the
        B2B CRM is erased or copied in that CRM by its admin and then ticked here, and the request is done only when
        every system is.
      </p>
      {line ? (
        <p role="status" className="text-success text-sm">
          {which}
          {line}
        </p>
      ) : null}
      <Card>
        {rows === null ? (
          <p role="alert" className="text-danger text-sm">
            The requests could not be loaded. Nothing was changed; reload the page to try again.
          </p>
        ) : (
          <ul className="grid gap-3 text-sm">
            {rows.map((r) => (
              <li key={r.id} className="border-border border-b pb-3 last:border-0">
                <p>
                  <strong>{KIND_LABEL[r.kind] ?? r.kind}</strong> · #{r.id} · {r.email_norm} · {day(r.requested_at)} ·{" "}
                  <span className={r.status === "open" ? "text-amber-text font-medium" : "text-muted"}>{r.status}</span>
                  {r.processed_by ? <span className="text-muted"> by {r.processed_by}</span> : null}
                </p>
                {r.note ? <p className="text-muted mt-1">{r.note}</p> : null}
                {r.kind === "opt_out" ? (
                  r.status === "open" ? (
                    <CloseForm id={r.id} canMarkDone />
                  ) : null
                ) : r.status === "open" || (r.status === "done" && websiteDone(r)) ? (
                  <Fulfilment r={r} />
                ) : null}
              </li>
            ))}
            {rows.length === 0 ? <li className="text-muted">No requests.</li> : null}
          </ul>
        )}
      </Card>
    </AdminShell>
  );
}

export default function PrivacyPage({ searchParams }: { searchParams: Promise<{ ok?: string; request?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-40" />}>
      <View searchParams={searchParams} />
    </Suspense>
  );
}
