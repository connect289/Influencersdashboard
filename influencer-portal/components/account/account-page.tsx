import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import type { ServerSupabase } from "@/lib/supabase/server";
import { DeviceList, SessionList, type DeviceRow, type SessionRow } from "./session-list";

/** The Account page body for both portals: who you are, your sessions, and (staff) trusted devices. */
export async function AccountPage({
  supabase,
  name,
  email,
  extra,
  showDevices,
}: {
  supabase: ServerSupabase;
  name: string;
  email: string;
  extra?: React.ReactNode;
  showDevices: boolean;
}) {
  const t = await getTranslations();
  const [sessions, devices] = await Promise.all([
    supabase.rpc("my_sessions"),
    showDevices ? supabase.rpc("my_devices") : Promise.resolve({ data: [], error: null }),
  ]);
  return (
    <>
      <PageHeader title={t("account.title")} description={t("account.subtitle")} />
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader title={t("account.profile")} />
          <dl className="grid gap-2 text-sm">
            <div>
              <dt className="text-muted">{t("account.name")}</dt>
              <dd className="font-medium">{name}</dd>
            </div>
            <div>
              <dt className="text-muted">{t("account.email")}</dt>
              <dd className="font-medium break-all">{email}</dd>
            </div>
            {extra}
          </dl>
        </Card>
        <Card>
          <CardHeader title={t("account.sessions.title")} description={t("account.sessions.subtitle")} />
          {sessions.error ? (
            <ErrorState title={t("errors.loadFailed")} />
          ) : (
            <SessionList sessions={sessions.data as SessionRow[]} />
          )}
        </Card>
        {showDevices ? (
          <Card>
            <CardHeader title={t("account.devices.title")} description={t("account.devices.subtitle")} />
            {devices.error ? (
              <ErrorState title={t("errors.loadFailed")} />
            ) : (
              <DeviceList devices={devices.data as DeviceRow[]} />
            )}
          </Card>
        ) : null}
      </div>
    </>
  );
}
