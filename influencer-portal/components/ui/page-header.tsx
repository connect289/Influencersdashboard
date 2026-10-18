import type { ReactNode } from "react";
import { HelpLink } from "@/components/help/help-link";

export function PageHeader({
  title,
  description,
  actions,
  help,
}: {
  title: string;
  description?: ReactNode;
  actions?: ReactNode;
  /** Link to the guide section that explains this screen. */
  help?: string;
}) {
  return (
    <header className="mb-4 flex flex-col gap-3 md:mb-6 md:flex-row md:items-end md:justify-between">
      <div className="min-w-0">
        <h1 className="text-xl font-semibold md:text-2xl">{title}</h1>
        {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
        {help ? (
          <div className="mt-1">
            <HelpLink href={help} />
          </div>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </header>
  );
}
