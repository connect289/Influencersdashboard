// Every move of a deliverable: who (side), what, when, and the note.
import { useTranslations } from "next-intl";
import type { DeliverableDetail } from "@/lib/content/data";
import { formatDateTime } from "@/lib/format";
import { ACTIONS, DELIVERABLE_STATUSES, type Action, type DeliverableStatus } from "@/lib/content/workflow";

const isAction = (a: string): a is Action => (ACTIONS as readonly string[]).includes(a);
const isStatus = (s: string): s is DeliverableStatus => (DELIVERABLE_STATUSES as readonly string[]).includes(s);

export function HistoryList({ transitions }: { transitions: DeliverableDetail["transitions"] }) {
  const t = useTranslations();
  if (!transitions.length) return <p className="text-sm text-muted">{t("content.history.empty")}</p>;
  return (
    <ol className="flex flex-col gap-3 border-l-2 border-line pl-4">
      {[...transitions].reverse().map((x, i) => (
        <li key={i} className="text-sm">
          <p>
            <span className="font-medium">{isAction(x.action) ? t(`content.actions.${x.action}`) : x.action}</span>
            {isStatus(x.to) ? <span className="text-muted"> → {t(`content.statuses.${x.to}`)}</span> : null}
          </p>
          <p className="text-xs text-muted">
            {t(
              `content.history.sides.${x.side === "creator" || x.side === "agency" || x.side === "eduwit" ? x.side : "system"}`,
            )}{" "}
            · {formatDateTime(x.at)}
          </p>
          {x.note ? <p className="mt-0.5 text-muted">{x.note}</p> : null}
        </li>
      ))}
    </ol>
  );
}
