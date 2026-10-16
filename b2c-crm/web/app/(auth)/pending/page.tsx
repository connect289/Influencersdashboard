import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getMe, homeFor } from "@/lib/auth";

export const metadata: Metadata = { title: "Waiting for access" };

/** Signed in with an @eduwit.in account the Admin has not added (or has deactivated). */
export default async function PendingPage() {
  const result = await getMe();
  if ("setupError" in result) redirect("/login?error=setup");
  const { me } = result;
  if (!me.user_id) redirect("/login");
  if (me.known && me.active) redirect(homeFor(me));
  return (
    <div className="stack">
      <h1>{me.known ? "Your access is switched off" : "Waiting for access"}</h1>
      <p className="muted">
        {me.known
          ? "The Admin has deactivated your account. Ask them if this is a mistake."
          : `You are signed in as ${me.email}, but the Admin has not added you yet. Ask them to add you under Teams; then sign in again.`}
      </p>
      <form action="/auth/signout" method="post">
        <button className="btn ghost block" type="submit">Sign out</button>
      </form>
    </div>
  );
}
