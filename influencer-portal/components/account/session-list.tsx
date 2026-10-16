"use client";
import { Laptop, Smartphone } from "lucide-react";
import { useTranslations } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { revokeDevice, revokeOtherSessions, revokeSession } from "@/lib/actions/account";
import type { ActionResult } from "@/lib/actions/result";
import { formatDateTime, formatRelative } from "@/lib/format";

export interface SessionRow {
  session_id: string;
  created_at: string;
  last_seen_at: string;
  ip: string | null;
  user_agent: string | null;
  verified: boolean;
  revoked_at: string | null;
  is_current: boolean;
}

export interface DeviceRow {
  id: string;
  label: string | null;
  created_at: string;
  last_used_at: string | null;
  expires_at: string;
}

function deviceName(ua: string | null): { name: string; mobile: boolean } {
  if (!ua) return { name: "", mobile: false };
  const mobile = /Mobile|Android|iPhone|iPad/i.test(ua);
  const browser = /Edg\//.test(ua)
    ? "Edge"
    : /Chrome\//.test(ua)
      ? "Chrome"
      : /Firefox\//.test(ua)
        ? "Firefox"
        : /Safari\//.test(ua)
          ? "Safari"
          : "";
  const os = /Android/.test(ua)
    ? "Android"
    : /iPhone|iPad/.test(ua)
      ? "iOS"
      : /Windows/.test(ua)
        ? "Windows"
        : /Mac OS X/.test(ua)
          ? "macOS"
          : /Linux/.test(ua)
            ? "Linux"
            : "";
  return { name: [browser, os].filter(Boolean).join(" on "), mobile };
}

function useRunner() {
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<ActionResult>) =>
    start(async () => {
      const r = await fn();
      if (r.ok) toast.success(r.message ?? "");
      else toast.error(r.error);
    });
  return { pending, run };
}

export function SessionList({ sessions }: { sessions: SessionRow[] }) {
  const t = useTranslations();
  const { pending, run } = useRunner();
  const live = sessions.filter((s) => !s.revoked_at);
  return (
    <div className="flex flex-col gap-3">
      <ul className="divide-y divide-line">
        {live.map((s) => {
          const d = deviceName(s.user_agent);
          const Icon = d.mobile ? Smartphone : Laptop;
          return (
            <li key={s.session_id} className="flex items-center gap-3 py-3">
              <Icon className="size-5 shrink-0 text-muted" aria-hidden />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">
                  {d.name || t("account.sessions.unknownDevice")}{" "}
                  {s.is_current ? <Badge family="success">{t("account.sessions.thisDevice")}</Badge> : null}
                </p>
                <p className="text-xs text-muted">
                  <time dateTime={s.last_seen_at} title={formatDateTime(s.last_seen_at)}>
                    {t("account.sessions.lastActive", { when: formatRelative(s.last_seen_at) })}
                  </time>
                  {s.ip ? ` · ${s.ip}` : ""}
                </p>
              </div>
              {!s.is_current ? (
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={pending}
                  onClick={() => run(() => revokeSession(s.session_id))}
                >
                  {t("account.sessions.signOut")}
                </Button>
              ) : null}
            </li>
          );
        })}
      </ul>
      {live.length > 1 ? (
        <Button variant="secondary" disabled={pending} onClick={() => run(revokeOtherSessions)} className="self-start">
          {t("account.sessions.signOutOthers")}
        </Button>
      ) : null}
    </div>
  );
}

export function DeviceList({ devices }: { devices: DeviceRow[] }) {
  const t = useTranslations();
  const { pending, run } = useRunner();
  if (devices.length === 0) return <p className="text-sm text-muted">{t("account.devices.none")}</p>;
  return (
    <ul className="divide-y divide-line">
      {devices.map((d) => (
        <li key={d.id} className="flex items-center gap-3 py-3">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">
              {deviceName(d.label).name || t("account.sessions.unknownDevice")}
            </p>
            <p className="text-xs text-muted">
              {t("account.devices.trustedUntil", { date: formatDateTime(d.expires_at) })}
            </p>
          </div>
          <Button variant="secondary" size="sm" disabled={pending} onClick={() => run(() => revokeDevice(d.id))}>
            {t("account.devices.forget")}
          </Button>
        </li>
      ))}
    </ul>
  );
}
