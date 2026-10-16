import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getMe } from "@/lib/auth";
import { NewPasswordForm } from "./NewPasswordForm";

export const metadata: Metadata = { title: "New password" };

/** Reached only through the emailed link (/auth/confirm signs the person in for this step). */
export default async function NewPasswordPage() {
  const result = await getMe();
  if ("setupError" in result) redirect("/login?error=setup");
  if (!result.me.user_id) redirect("/password?error=expired");
  return <NewPasswordForm email={result.me.email ?? ""} />;
}
