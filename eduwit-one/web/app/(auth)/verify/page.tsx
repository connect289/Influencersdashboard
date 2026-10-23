import { type Metadata } from "next";
import { redirect } from "next/navigation";
import { getMe, trustDevice } from "@/lib/session.ts";
import { safeNext } from "@/lib/security.ts";
import { VerifyForm } from "./verify-form.tsx";

export const metadata: Metadata = { title: "Check your email" };

export default async function VerifyPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const next = safeNext((await searchParams).next);
  const result = await getMe();
  if ("setupError" in result) redirect(`/login?error=${result.setupError}`);
  const { me } = result;
  if (!me.user_id || !me.alive) redirect("/login");
  if (!me.known || !me.active) redirect("/pending");
  if (me.checked || (await trustDevice())) redirect(next);
  return (
    <div className="grid gap-4">
      <div>
        <h1 className="text-xl font-semibold">One more step</h1>
        <p className="mt-1 text-sm text-fg-muted">
          We send a 6-digit code to {me.email}. It proves this browser is yours; you can trust the browser so it is not
          asked again for 30 days.
        </p>
      </div>
      <VerifyForm next={next} />
      <form method="post" action="/auth/signout">
        <button type="submit" className="text-sm text-fg-muted underline">
          Use another account
        </button>
      </form>
    </div>
  );
}
