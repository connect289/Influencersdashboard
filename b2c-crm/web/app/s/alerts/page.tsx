import type { Metadata } from "next";
import { Page } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { Notifications } from "../Notifications";

export const metadata: Metadata = { title: "Alerts" };

/** Every alert, newest first: new leads, re-engaged leads, SLA, reminders, replies, enrolment checks, number changes. */
export default async function AlertsPage() {
  await requireUser("sales", "/s/alerts");
  return (
    <Page title="Alerts" sub="Newest first. Each one opens the lead or screen it is about.">
      <Notifications limit={100} all />
    </Page>
  );
}
