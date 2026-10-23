import type { EmailClient } from "../../clients/email.ts";
import type { TestSeams } from "../db.ts";

// What a journey can use: the seams in schema one (facts and actions on test identities), and the vendor clients a
// seam outside the database needs. A client is null when its credential is not configured; a test that needs it is
// not enabled until its Setup item is validated, and its guard refuses to start without it.
export type JourneyIo = {
  seams: TestSeams;
  email: EmailClient | null;
};
