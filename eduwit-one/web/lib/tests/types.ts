// The synthetic tests (spec §10): each is a journey through one seam, a list of steps that each act once and then
// wait, within their own timeout, for the app to show the result. A run is a state machine kept in one.test_runs, so a
// step that waits for minutes spans several minute ticks.

/** What a run created in the apps, kept for the purge (lead ids, test phones, message ids...). Never a contact. */
export type Artefacts = Record<string, unknown>;

export type StepResult = {
  key: string;
  title: string;
  ok: boolean;
  /** From the step's start to the moment its result was seen (step timings on the Tests page). */
  ms: number;
  detail: string | null;
  at: string;
};

export type RunState = { step: number; stepStartedAt: string; acted: boolean };

export type Run = {
  id: number;
  testId: string;
  startedAt: string;
  steps: StepResult[];
  artefacts: Artefacts;
  state: RunState;
};

export type Poll = { done: boolean; detail?: string; artefacts?: Artefacts };

export type TestContext<Io> = {
  run: Run;
  /** The run's artefacts so far; steps read the ids earlier steps recorded. */
  artefacts: Artefacts;
  identities: Identities;
  io: Io;
  now: () => number;
};

export type Step<Io> = {
  key: string;
  title: string;
  timeoutS: number;
  /** Done once per run (the state records that it ran, so a later tick never repeats it). */
  act?: (ctx: TestContext<Io>) => Promise<Artefacts | undefined>;
  /** Polled until it is done or the step times out. A step without it passes when its act returns. */
  until?: (ctx: TestContext<Io>) => Promise<Poll>;
};

export type TestDef<Io> = {
  id: string;
  /** Setup items the test needs (the catalogue in config/tests.json is the source; a unit test keeps them equal). */
  needs: readonly string[];
  /**
   * The safety check before anything is sent (spec §10): every identity the run will use is a test identity. Returns
   * why the run must not start, or null.
   */
  guard: (ctx: TestContext<Io>) => Promise<string | null>;
  steps: Array<Step<Io>>;
};

/** settings.test_identities: the only identities a test may use (spec §17.9). */
export type Identities = {
  phone_prefix: string;
  whatsapp_number: string | null;
  mailbox: string | null;
  website_preview_url: string | null;
  spark_test_user_email: string | null;
  partner_slug: string | null;
  creator_referral_code: string | null;
};

/** Thrown by a step for a refusal that must stop the run (a non-test identity, an unsafe target). */
export class Unsafe extends Error {}
