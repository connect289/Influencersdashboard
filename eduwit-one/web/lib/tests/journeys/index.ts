import type { TestDef } from "../types.ts";
import { tAlert } from "./alert.ts";
import type { JourneyIo } from "./io.ts";

// The journeys the runner knows. A test in the catalogue without a journey here never starts (it is not enabled
// until its Setup items are validated, and the runner skips a test it has no journey for). journeys.test.ts keeps
// each journey's steps and needs equal to config/tests.json.
export const journeys: ReadonlyArray<TestDef<JourneyIo>> = [tAlert];
