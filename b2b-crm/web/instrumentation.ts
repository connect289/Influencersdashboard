import type { Instrumentation } from "next";
import { requestErrorLine } from "@/lib/request-error";

/** M34i: one JSON line per failed server request, with no personal data (lib/request-error.ts says what is left out). */
export const onRequestError: Instrumentation.onRequestError = (error, request, context) => {
  console.error(JSON.stringify(requestErrorLine(error, request, context)));
};
