import { AppShell } from "@/components/shell/AppShell";
import { SetupNotice } from "@/components/app/SetupNotice";
import { requireAdmin } from "@/lib/auth";
import { liveSwitches } from "@/lib/data";

/** Every screen inside the app passes this gate on the server, on every request. */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const result = await requireAdmin();
  if ("setupError" in result) return <SetupNotice />;
  const switches = await liveSwitches();
  return (
    <AppShell email={result.me.email ?? ""} anyLive={switches.some((s) => s.live)}>
      {children}
    </AppShell>
  );
}
