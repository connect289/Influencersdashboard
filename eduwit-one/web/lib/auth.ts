import "server-only";
import { bootEnv } from "./env.ts";
import { INTERNAL_TOKEN_HEADER, internalRequestAuthorized } from "./security.ts";

/**
 * The internal routes' caller check (spec §13, security review m6): the database's job calls carry a short-lived
 * x-one-token signed with one_internal_key from Vault; a person's curl carries the same value as a bearer. The app
 * holds that value as ONE_INTERNAL_KEY. Constant-time compares; no key configured means every call is refused.
 */
export function internalAuthorized(request: Request): Promise<boolean> {
  return internalRequestAuthorized({
    key: bootEnv().ONE_INTERNAL_KEY,
    authorization: request.headers.get("authorization"),
    token: request.headers.get(INTERNAL_TOKEN_HEADER),
    pathname: new URL(request.url).pathname,
    nowSeconds: Math.floor(Date.now() / 1000),
  });
}
