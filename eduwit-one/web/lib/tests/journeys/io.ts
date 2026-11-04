import type { EmailClient } from "../../clients/email.ts";
import type { TestApps } from "../apps.ts";
import type { TestSeams } from "../db.ts";
import type { Identities } from "../types.ts";

// What a journey can use: the seams in schema one (facts and actions on test identities), the alert email client, and
// the apps' own doors (lib/tests/apps.ts), built for the run's test identities. A door is null when what it needs is
// not configured; a test that needs it is not enabled until its Setup item is validated, and its guard refuses to start
// without it.
export type JourneyIo = {
  seams: TestSeams;
  email: EmailClient | null;
  apps: (identities: Identities) => TestApps;
};
