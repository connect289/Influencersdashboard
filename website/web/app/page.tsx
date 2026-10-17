import { redirect } from "next/navigation";

// Phase 1: the homepage is built in Phase 6. Until then the root shows the design concepts.
export default function Home() {
  redirect("/concepts");
}
