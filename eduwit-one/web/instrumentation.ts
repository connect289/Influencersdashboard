import type { Instrumentation } from "next";
import { logRequestError } from "./lib/request-error.ts";

// Next calls this for every error a page, route, server action or the middleware throws on the server (D-137): one
// structured, contact-free line in the platform's logs (lib/request-error.ts). No external service.
export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  logRequestError(error, request, context);
};
