"use client";

import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import { useState } from "react";

const OfferingPanel = dynamic(() => import("./OfferingPanel").then((m) => m.OfferingPanel), { ssr: false });
const GroupPanel = dynamic(() => import("./GroupPanel").then((m) => m.GroupPanel), { ssr: false });

/** Loads panel code only once a panel is opened (deep link or click). */
export function PanelHost(props: { qual?: string; advisorEnabled: boolean; whatsapp: string; goals: { value: string; label: string }[] }) {
  const sp = useSearchParams();
  const [used, setUsed] = useState({ offering: false, group: false });
  if ((!used.offering && sp.get("offering")) || (!used.group && sp.get("group"))) {
    setUsed({ offering: used.offering || !!sp.get("offering"), group: used.group || !!sp.get("group") });
  }
  return (
    <>
      {used.offering ? <OfferingPanel {...props} /> : null}
      {used.group ? <GroupPanel whatsapp={props.whatsapp} goals={props.goals} /> : null}
    </>
  );
}

