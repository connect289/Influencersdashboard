import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { DashboardView } from "../DashboardView";

export const metadata: Metadata = { title: "Dashboard" };
type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function DashboardPage({ params, searchParams }: Props) {
  await requireAdmin();
  const raw = (await params).id;
  if (!/^\d{1,15}$/.test(raw)) notFound();
  return <DashboardView id={Number(raw)} sp={await searchParams} />;
}
