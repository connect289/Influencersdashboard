import { parseUnsubscribeLink } from "@/lib/unsubscribe";
import { UnsubscribeForm } from "./UnsubscribeForm";

/**
 * /u/{lead}/{token} (M34j): the Unsubscribe link in a student's email. Public, no sign-in (proxy.ts lets /u/ through
 * without reading a session). Opening it only shows the confirm button: nothing is read from or written to the database
 * until the button is pressed, so a mail scanner that follows the link unsubscribes nobody and learns nothing.
 * The page waits for nothing, so it has no loading.tsx (a streamed shell would need JavaScript to show its content); the
 * waiting state is the button's (UnsubscribeForm), and the form also works without JavaScript.
 */
type Props = { params: Promise<{ lead: string; token: string }> };

/**
 * A link of the wrong shape, usually cut short when it was copied: say so, rather than a false "done". Names nobody.
 * Rendered here, not through notFound(): that answer reaches the browser as a script, and this page must read without one.
 */
function IncompleteLink() {
  return (
    <div>
      <h1 className="text-xl font-semibold tracking-tight text-fg">This link is incomplete</h1>
      <p className="mt-2 text-[15px] leading-6 text-muted">
        Open the Unsubscribe link in your latest email from Eduwit again, or reply to that email and ask us to stop.
      </p>
    </div>
  );
}

export default async function UnsubscribePage({ params }: Props) {
  const link = parseUnsubscribeLink(await params);
  return link ? <UnsubscribeForm lead={link.lead} token={link.token} /> : <IncompleteLink />;
}
