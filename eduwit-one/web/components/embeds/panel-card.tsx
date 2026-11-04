import { JsonView } from "@/components/embeds/json-view.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { ms } from "@/lib/format.ts";
import type { Panel } from "@/lib/embeds/index.ts";
import type { Embed } from "@/lib/ui/schemas.ts";

const why: Record<string, string> = {
  needs_access: "Needs your access in the app itself: this panel runs as you.",
  missing: "Not available on this database (the app's function or table is not there).",
  busy: "The app's table was locked for a moment; it refreshes on its own.",
};

/** One app panel: its data, or why it could not be read, and how long the call took (phase 4 criterion). */
export function PanelCard({ panel, embed }: { panel: Panel; embed: Embed | null }) {
  return (
    <Card>
      <CardHeader
        title={panel.title}
        description={panel.about}
        actions={embed ? <Badge tone={embed.ok ? "neutral" : "off"}>{ms(embed.ms)}</Badge> : null}
      />
      <CardBody className="max-h-[32rem] overflow-auto">
        {!embed ? (
          <p className="text-sm text-p1">This panel could not be loaded.</p>
        ) : embed.ok ? (
          <JsonView value={embed.data} />
        ) : (
          <p className="text-sm text-fg-muted">
            {(embed.kind && why[embed.kind]) ?? embed.error ?? "It did not answer."}
          </p>
        )}
      </CardBody>
    </Card>
  );
}
