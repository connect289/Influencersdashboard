import "server-only";
import { rpc } from "../db";
import { log } from "../log";

/**
 * Witty's prompts by reference (docs/AGENT_ARCHITECTURE.md §3.2): read through web_agent_core_prompts(), cached in memory
 * for 5 minutes, recorded per session as name:version:md5. The web overlay (versioned, web_settings until A-AGENT-4) is
 * appended to the counselor prompt only.
 */
interface PromptRow {
  version: number;
  md5: string;
  text: string;
}
export interface CorePrompts {
  extractor: string;
  counselor: string;
  version: string;
}

let cache: { at: number; value: CorePrompts } | null = null;

export async function corePrompts(engineVersion: string): Promise<CorePrompts | null> {
  if (cache && Date.now() - cache.at < 5 * 60_000) return cache.value;
  const r = await rpc<{ extractor: PromptRow | null; counselor: PromptRow | null; overlay: { version: number; body: string } | null }>("web_agent_core_prompts");
  if (!r.extractor?.text || !r.counselor?.text) {
    log("error", "web_advisor.prompts_missing");
    return null;
  }
  const overlay = r.overlay?.body ? `\n\n${r.overlay.body}` : "";
  const value: CorePrompts = {
    extractor: r.extractor.text,
    counselor: r.counselor.text + overlay,
    version: `extractor:${r.extractor.version}:${r.extractor.md5}|counselor:${r.counselor.version}:${r.counselor.md5}|overlay:${r.overlay?.version ?? 0}|engine:${engineVersion}`,
  };
  cache = { at: Date.now(), value };
  return value;
}
