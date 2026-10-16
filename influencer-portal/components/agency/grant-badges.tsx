import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";

export interface Grants {
  can_view: boolean;
  can_act_deliverables: boolean;
  can_negotiate_sign: boolean;
  can_view_earnings: boolean;
}

/** The permissions a creator granted an agency, as small badges. */
export async function GrantBadges({ grants }: { grants: Grants }) {
  const t = await getTranslations();
  const on = [
    grants.can_view && "view",
    grants.can_act_deliverables && "deliverables",
    grants.can_negotiate_sign && "negotiate",
    grants.can_view_earnings && "earnings",
  ].filter((x): x is "view" | "deliverables" | "negotiate" | "earnings" => Boolean(x));
  return (
    <span className="flex flex-wrap gap-1">
      {on.map((g) => (
        <Badge key={g} family="progress">
          {t(`agencies.grants.${g}`)}
        </Badge>
      ))}
    </span>
  );
}
