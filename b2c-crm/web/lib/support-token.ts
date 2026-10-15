import { readToken, signToken } from "@/lib/tokens";

/** The developer's link in each support email: answer and change the status without signing in (server only). */
export const supportToken = (ticket: number, key?: string) => signToken(`sup|${ticket}`, key);
export function readSupportToken(token: string, key?: string): number | null {
  const p = readToken(token, key);
  const m = p ? /^sup\|(\d+)$/.exec(p) : null;
  return m ? Number(m[1]) : null;
}
