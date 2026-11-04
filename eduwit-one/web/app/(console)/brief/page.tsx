import { type Metadata } from "next";
import Link from "next/link";
import { RegenerateForm } from "@/components/brief/brief-forms.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { istDate, usd } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { briefsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Brief" };

export default async function BriefsPage() {
  let briefs;
  try {
    briefs = await ui("ui_briefs", briefsSchema, { p_limit: 60 });
  } catch (e) {
    return <PageError error={e} />;
  }
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date());
  return (
    <>
      <PageHeader
        title="Brief"
        description="The nightly brief (built at 02:30 IST, mailed in the morning), with the numbers it was built from."
      />
      <Card>
        <CardHeader
          title="Re-generate a brief"
          description="Queues it for the AI worker on the tier you choose; the cost shows in Audit → AI calls."
        />
        <CardBody>
          <RegenerateForm date={today} />
        </CardBody>
      </Card>
      <Card>
        {briefs.length === 0 ? (
          <Empty title="No briefs yet">
            The AI worker writes one each night at 02:30 IST once its key and model prices are set (Setup item ai_key).
          </Empty>
        ) : (
          <ul className="divide-y divide-border">
            {briefs.map((b) => (
              <li key={b.id}>
                <Link href={`/brief/${b.id}`} className="grid gap-1 px-4 py-3 hover:bg-surface-2">
                  <span className="font-medium">{istDate(b.for_date)}</span>
                  <span className="line-clamp-2 text-sm text-fg-muted">{b.excerpt}</span>
                  <span className="text-xs text-fg-muted">
                    {b.tier ?? "regular"} · {b.model ?? "model ?"} · {usd(b.cost_usd)}
                    {b.sent_at ? " · mailed" : ""}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
