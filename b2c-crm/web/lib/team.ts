import "server-only";
import { rpc } from "@/lib/data";

export type TeamMember = {
  user: {
    user_id: string; email: string; full_name: string | null; role: string; is_active: boolean; is_test_user: boolean; takes_leads: boolean; on_call: boolean;
    phone: string | null; languages: string[]; skills: Record<string, string[]>; weight: number; monthly_cap: number; open_cap: number | null;
    daily_cap: number | null; monthly_target: Record<string, number>; away_until: string | null; job_title: string | null; photo_url: string | null;
  };
  load: { month: number; open: number; day: number };
  working_now: boolean;
  patterns: { isodow: number; start: string; end: string }[];
  leave: { id: number; from_day: string; to_day: string; mode: string; reassign_after_hours: number | null; reason: string | null }[];
  enrolled_month: number;
  calls_today: number;
};

/** b2c.team(): everyone with their load, hours and leave (Admin and Marketing). */
export function team(): Promise<TeamMember[]> {
  return rpc<TeamMember[]>("team");
}

/** Active people who can hold leads, for reassign pickers. */
export function assignable(t: TeamMember[]): { user_id: string; name: string }[] {
  return t.filter((m) => m.user.is_active && ["counsellor", "sales_head", "admin"].includes(m.user.role))
    .map((m) => ({ user_id: m.user.user_id, name: m.user.full_name ?? m.user.email }));
}
