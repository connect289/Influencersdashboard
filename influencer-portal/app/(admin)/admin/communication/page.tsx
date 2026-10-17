import { redirect } from "next/navigation";
import { COMM_SECTIONS } from "@/components/communication/comm-nav";
import { requireStaff } from "@/lib/auth/guards";

/** Opens the first communication section the person may use. */
export default async function CommunicationPage() {
  const { me } = await requireStaff();
  const first = COMM_SECTIONS.find((s) => me.permissions.has(s.perm));
  redirect(first ? `/admin/communication/${first.key}` : "/no-access");
}
