import { type Metadata } from "next";
import { notFound } from "next/navigation";
import { SettingView } from "@/components/settings/setting-view.tsx";

export const metadata: Metadata = { title: "Setting" };

export default async function SettingPage({
  params,
  searchParams,
}: {
  params: Promise<{ key: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const key = (await params).key;
  const from = Number((await searchParams).from);
  if (!/^[a-z_]{2,40}$/.test(key)) notFound();
  return <SettingView name={key} from={from} base={`/settings/${key}`} />;
}
