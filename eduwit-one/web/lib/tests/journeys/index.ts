import type { TestDef } from "../types.ts";
import { tAlert } from "./alert.ts";
import { tB2bIntake, tB2bPush } from "./b2b.ts";
import type { JourneyIo } from "./io.ts";
import { tB2cNurture, tHandoff } from "./spark.ts";
import { tWittyQualify, tWittyTurn } from "./witty.ts";

// The journeys the runner knows. A test in the catalogue without a journey here never starts (it is not enabled
// until its Setup items are validated, and the runner skips a test it has no journey for): today the blocked website
// and influencer tests (D-071). journeys.test.ts keeps each journey's steps and needs equal to config/tests.json.
export const journeys: ReadonlyArray<TestDef<JourneyIo>> = [
  tWittyTurn,
  tWittyQualify,
  tB2bIntake,
  tB2bPush,
  tHandoff,
  tB2cNurture,
  tAlert,
];
