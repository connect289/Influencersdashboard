import { connection } from "next/server";

// The account area renders per request so Next can stamp the CSP nonce on every script (D-025); never cached.
export const instant = false;

export default async function AccountLayout({ children }: { children: React.ReactNode }) {
  await connection();
  return children;
}
