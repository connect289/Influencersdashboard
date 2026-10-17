import Link from "next/link";
import type { Settings } from "@/lib/settings";

/** Admin-managed announcement bar (spec 11). Hidden when the setting is null. */
export function AnnouncementBar({ announcement }: { announcement: Settings["announcement"] }) {
  if (!announcement?.text) return null;
  const tone = announcement.tone === "amber" ? "bg-amber-soft text-text" : "bg-accent-soft text-text";
  const body = <span className="line-clamp-2">{announcement.text}</span>;
  return (
    <div className={`${tone} border-border border-b text-center text-sm`}>
      <div className="container-site py-2">
        {announcement.href ? (
          <Link href={announcement.href} className="underline-offset-4 hover:underline">
            {body}
          </Link>
        ) : (
          body
        )}
      </div>
    </div>
  );
}
