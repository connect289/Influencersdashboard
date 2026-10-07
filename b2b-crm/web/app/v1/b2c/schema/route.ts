import { callB2c, requireKey } from "@/lib/b2c-api";

/** GET /v1/b2c/schema: every lead field the B2C CRM sees, which it may write, the stage list and the activity kinds. */
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  return callB2c("api_b2c_schema", { p_key: key });
}
