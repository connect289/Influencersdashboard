import { redirect } from "next/navigation";
import { landingPath } from "@/lib/auth/landing";

export default async function Home() {
  redirect(await landingPath());
}
