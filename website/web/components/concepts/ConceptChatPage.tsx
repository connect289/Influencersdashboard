import { ConceptFrame, type ConceptId } from "./ConceptFrame";
import { WITTY_GREETING } from "./Heroes";
import { Atmosphere } from "@/components/fx/Atmosphere";
import { ChatDemo } from "@/components/witty/ChatDemo";
import { seedOfferings } from "@/lib/seed/concept";

export function ConceptChatPage({ c }: { c: ConceptId }) {
  return (
    <ConceptFrame concept={c} active="chat">
      <main id="main" className="relative isolate overflow-hidden">
        {c === "a" ? <Atmosphere variant="aurora" className="opacity-60" /> : null}
        <div className="container-site relative grid max-w-3xl gap-4 py-8">
          <h1 className="sr-only">Chat with Witty</h1>
          <ChatDemo offerings={seedOfferings} variant={c} greeting={WITTY_GREETING} />
        </div>
      </main>
    </ConceptFrame>
  );
}
