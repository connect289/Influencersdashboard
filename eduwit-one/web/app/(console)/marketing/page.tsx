import { type Metadata } from "next";
import { JsonView } from "@/components/embeds/json-view.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { ui } from "@/lib/ui/api.ts";
import { marketingSchema, settingsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Marketing" };

function Section({ title, about, value, error }: { title: string; about: string; value: unknown; error: unknown }) {
  return (
    <Card>
      <CardHeader title={title} description={about} />
      <CardBody className="max-h-[32rem] overflow-auto">
        {typeof error === "string" ? (
          <p className="text-sm text-fg-muted">{error}</p>
        ) : (
          <JsonView value={value ?? []} />
        )}
      </CardBody>
    </Card>
  );
}

export default async function MarketingPage({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const days = [7, 30, 90].includes(Number((await searchParams).days)) ? Number((await searchParams).days) : 30;
  let data;
  let settings;
  try {
    [data, settings] = await Promise.all([
      ui("ui_marketing", marketingSchema, { p_days: days }),
      ui("ui_settings", settingsSchema),
    ]);
  } catch (e) {
    return <PageError error={e} />;
  }
  const spark = (settings.hosts?.value as { spark?: string } | undefined)?.spark;
  return (
    <>
      <PageHeader
        title="Marketing"
        description="Across the apps: where leads come from, what the ads cost, how far nurture reaches, and the WhatsApp numbers' state. Spend and leads are shown side by side, never on one scale."
        actions={
          spark ? (
            <a href={`${spark}/w`} target="_blank" rel="noreferrer" className="text-sm underline">
              Spark marketing
            </a>
          ) : null
        }
      />
      <Filters reset="/marketing">
        <FilterSelect
          name="days"
          label="Period"
          value={String(days)}
          options={[
            ["7", "7 days"],
            ["30", "30 days"],
            ["90", "90 days"],
          ]}
        />
      </Filters>
      <div className="grid gap-4 xl:grid-cols-2">
        <Section
          title="Leads by platform and campaign"
          about="From the B2B CRM's lead campaigns, per day (IST)."
          value={data.leads}
          error={data.leads_error}
        />
        <Section
          title="Ad spend"
          about="Per day, the B2B CRM's and Spark's imported spend in rupees."
          value={data.spend}
          error={data.spend_error}
        />
        <Section
          title="Touchpoints"
          about="Lead events from every app (public.touchpoints), per day and source."
          value={data.touchpoints}
          error={data.touchpoints_error}
        />
        <Section
          title="Nurture"
          about="Spark's nurture overview; it runs as you and needs your Spark marketing role."
          value={data.nurture}
          error={data.nurture_error}
        />
        <Section
          title="WhatsApp numbers"
          about="Status and quality rating from the WhatsApp probe (Setup item whatsapp)."
          value={data.whatsapp}
          error={undefined}
        />
      </div>
    </>
  );
}
