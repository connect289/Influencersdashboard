import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { fetchMe } from "@/lib/auth";
import { safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";
import { MfaForm } from "./MfaForm";

export const metadata: Metadata = { title: "Two-step verification" };

export default async function MfaPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const next = safeNext((await searchParams).next);
  const supabase = await createClient();
  const result = await fetchMe(supabase);
  if ("setupError" in result || !result.me.user_id) redirect("/login");
  if (!result.me.allowlisted) redirect("/auth/refuse");
  if (result.me.aal === "aal2") redirect(next);

  const { data } = await supabase.auth.mfa.listFactors();
  const hasFactor = Boolean(data?.totp.some((f) => f.status === "verified"));
  return <MfaForm mode={hasFactor ? "verify" : "enroll"} next={next} email={result.me.email ?? ""} />;
}
