import { redirect } from "next/navigation";
import { getMe, homeFor } from "@/lib/auth";

/** Sends each person to their own interface: counsellors and the sales head to /s, the Admin and Marketing to /w. */
export default async function Home() {
  const result = await getMe();
  if ("setupError" in result) redirect("/login?error=setup");
  const { me } = result;
  if (!me.user_id) redirect("/login");
  if (!me.known || !me.active || !me.role) redirect("/pending");
  redirect(homeFor(me));
}
