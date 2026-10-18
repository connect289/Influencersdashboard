// Shapes of the thread and unread-count payloads, shared by the server loaders and the browser helpers (no server
// code here).
import { z } from "zod";

const ts = z.string();
const side = z.enum(["eduwit", "creator", "agency"]);

export const messageRow = z.object({
  id: z.uuid(),
  author_side: side,
  author_name: z.string().nullable(),
  body: z.string(),
  created_at: ts,
  mine: z
    .boolean()
    .nullable()
    .transform((v) => v === true),
  attachments: z
    .array(z.object({ id: z.uuid(), name: z.string(), path: z.string(), mime: z.string(), size_bytes: z.number() }))
    .catch([]),
});
export type MessageRow = z.infer<typeof messageRow>;

export const threadView = z.object({
  thread_id: z.uuid().nullable(),
  subject: z.string(),
  side: side.nullable(),
  can_post: z.boolean(),
  staff_only: z.boolean(),
  other_read_at: ts.nullable(),
  my_read_at: ts.nullable(),
  messages: z.array(messageRow),
});
export type ThreadView = z.infer<typeof threadView>;

export const unreadCounts = z.object({ notifications: z.number(), messages: z.number() });
export type UnreadCounts = z.infer<typeof unreadCounts>;
