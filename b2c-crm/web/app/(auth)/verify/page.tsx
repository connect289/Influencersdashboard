import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getMe, homeFor, trustDevice } from "@/lib/auth";
import { safeNext } from "@/lib/security";
import { VerifyForm } from "./VerifyForm";

export const metadata: Metadata = { title: "Check your email" };

export default async function VerifyPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const result = await getMe();
  if ("setupError" in result) redirect("/login?error=setup");
  const { me } = result;
  if (!me.user_id) redirect("/login");
  if (!me.known || !me.active) redirect("/pending");
  const next = safeNext(sp.next, homeFor(me));
  if (me.checked || (await trustDevice())) redirect(next);
  return <VerifyForm next={next} email={me.email ?? "your company inbox"} />;
}
