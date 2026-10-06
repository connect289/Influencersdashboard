import { DatabaseZap } from "lucide-react";
import { Card } from "@/components/ui/Card";

/** Shown instead of the app when the database is reachable but the b2b schema is not exposed to the Data API. */
export function SetupNotice() {
  return (
    <main className="grid min-h-dvh place-items-center p-6">
      <Card className="max-w-lg p-6">
        <DatabaseZap className="size-6 text-warning" />
        <h1 className="mt-3 text-lg font-semibold text-fg">One Supabase setting is missing</h1>
        <p className="mt-2 text-sm leading-6 text-muted">
          The app talks to the database through the <code className="tabular text-fg">b2b</code> schema, which is not exposed yet.
          In Supabase, open <span className="font-medium text-fg">Project Settings → Data API → Exposed schemas</span>, add
          <code className="tabular text-fg"> b2b</code>, save, and reload this page.
        </p>
      </Card>
    </main>
  );
}
