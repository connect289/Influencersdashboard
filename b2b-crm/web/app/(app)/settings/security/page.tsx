import type { Metadata } from "next";
import { History, Laptop, ShieldCheck } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { mySessions, signInHistory } from "@/lib/data";
import { describeDevice, formatDateTime, relativeTime } from "@/lib/format";
import { SignOutOthers } from "./SignOutOthers";

export const metadata: Metadata = { title: "Security" };

const OUTCOME_TONE: Record<string, "success" | "danger" | "warning" | "neutral"> = {
  success: "success",
  failed_password: "danger",
  failed_totp: "danger",
  refused_not_allowlisted: "warning",
  locked: "danger",
  signed_out: "neutral",
  session_expired: "neutral",
};

const OUTCOME_LABEL: Record<string, string> = {
  success: "Signed in",
  failed_password: "Wrong password",
  failed_totp: "Wrong code",
  refused_not_allowlisted: "Refused: not allowed",
  locked: "Locked out",
  signed_out: "Signed out",
  session_expired: "Session expired",
};

const METHOD_LABEL: Record<string, string> = {
  google: "Google",
  password: "Password",
  totp: "Authenticator code",
  password_reset: "Password reset",
  sign_out: "Sign out",
  session: "Session check",
};

export default async function SecurityPage() {
  const result = await requireAdmin();
  const email = "me" in result ? result.me.email : "";
  const [sessions, history] = await Promise.all([mySessions(), signInHistory()]);

  return (
    <>
      <PageHeader title="Security" description="Two-step verification, the devices signed in as you, and every sign-in attempt." />

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]">
        <div className="space-y-6">
          <Card>
            <CardHeader title="Account" />
            <dl className="divide-y divide-border text-[13px]">
              <div className="flex items-center justify-between gap-4 px-5 py-3"><dt className="text-muted">Email</dt><dd className="truncate font-medium text-fg">{email}</dd></div>
              <div className="flex items-center justify-between gap-4 px-5 py-3"><dt className="text-muted">Role</dt><dd><Badge tone="brand">Admin</Badge></dd></div>
              <div className="flex items-center justify-between gap-4 px-5 py-3">
                <dt className="text-muted">Two-step verification</dt>
                <dd><Badge tone="success"><ShieldCheck className="size-3" /> On · authenticator app</Badge></dd>
              </div>
              <div className="flex items-center justify-between gap-4 px-5 py-3"><dt className="text-muted">Idle sign-out</dt><dd className="text-fg">After 12 hours</dd></div>
            </dl>
          </Card>

          <Card>
            <CardHeader title="Active sessions" description="Devices currently signed in as you." action={<SignOutOthers disabled={sessions.length < 2} />} />
            {sessions.length === 0 ? (
              <EmptyState icon={Laptop} title="No sessions found" />
            ) : (
              <ul className="divide-y divide-border">
                {sessions.map((s) => (
                  <li key={s.id} className="flex items-center gap-3 px-5 py-3">
                    <Laptop className="size-4 shrink-0 text-subtle" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-medium text-fg">{describeDevice(s.user_agent)}</p>
                      <p className="text-[12px] text-subtle">{s.ip ?? "IP unknown"} · active {relativeTime(s.refreshed_at ?? s.updated_at ?? s.created_at)}</p>
                    </div>
                    {s.current && <Badge tone="info">This device</Badge>}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        <Card>
          <CardHeader title="Sign-in history" description="Last 25 attempts, including refused accounts." />
          {history.length === 0 ? (
            <EmptyState icon={History} title="No attempts recorded yet" />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-[13px]">
                <thead className="text-[11px] uppercase tracking-wider text-subtle">
                  <tr className="border-b border-border">
                    <th scope="col" className="px-5 py-2.5 font-medium">When</th>
                    <th scope="col" className="px-3 py-2.5 font-medium">Result</th>
                    <th scope="col" className="px-3 py-2.5 font-medium">Method</th>
                    <th scope="col" className="px-5 py-2.5 font-medium">Device</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {history.map((h) => (
                    <tr key={h.id}>
                      <td className="tabular whitespace-nowrap px-5 py-2.5 text-[12.5px] text-muted">{formatDateTime(h.at)}</td>
                      <td className="px-3 py-2.5"><Badge tone={OUTCOME_TONE[h.outcome] ?? "neutral"}>{OUTCOME_LABEL[h.outcome] ?? h.outcome}</Badge></td>
                      <td className="whitespace-nowrap px-3 py-2.5 text-muted">{METHOD_LABEL[h.method] ?? h.method}</td>
                      <td className="px-5 py-2.5 text-muted">
                        <span className="block truncate">{describeDevice(h.user_agent)}</span>
                        {h.outcome === "refused_not_allowlisted" && h.email && <span className="block truncate text-[11.5px] text-subtle">{h.email}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
