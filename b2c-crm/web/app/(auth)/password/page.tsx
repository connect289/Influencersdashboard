import type { Metadata } from "next";
import { PasswordRequestForm } from "./PasswordRequestForm";

export const metadata: Metadata = { title: "Set your password" };

export default async function PasswordPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  return <PasswordRequestForm expired={sp.error === "expired"} />;
}
