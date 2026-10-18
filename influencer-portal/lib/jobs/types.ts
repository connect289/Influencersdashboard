export interface Job {
  id: number;
  kind: string;
  payload: Record<string, unknown>;
  attempts: number;
  max_attempts: number;
}

/** A job handler. Throw to fail (retried with backoff); return to succeed. Must be idempotent. */
export type JobHandler = (job: Job) => Promise<void>;

export class PermanentJobError extends Error {}
