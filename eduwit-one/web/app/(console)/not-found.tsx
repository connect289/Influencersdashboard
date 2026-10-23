import { ButtonLink } from "@/components/ui/button.tsx";
import { Empty } from "@/components/ui/state.tsx";

export default function NotFound() {
  return (
    <Empty title="Nothing here">
      <ButtonLink href="/">Back to the overview</ButtonLink>
    </Empty>
  );
}
