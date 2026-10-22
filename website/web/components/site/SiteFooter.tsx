import Link from "next/link";
import { Mail } from "lucide-react";
import { Logo } from "@/components/brand/Logo";
import { COMPANY, FEE_DISCLAIMER, LEGAL_PAGES } from "@/content/site";

/**
 * Footer (spec 8.12): contact, GST, address, legal links, social links, and sitemap hubs (top programmes and
 * universities — passed in from the catalogue so the links always exist).
 */
export function SiteFooter({
  programmes = [],
  universities = [],
  hasResources = true,
}: {
  programmes?: { href: string; label: string }[];
  universities?: { href: string; label: string }[];
  hasResources?: boolean;
}) {
  return (
    <footer className="border-border border-t pb-20 md:pb-0">
      <div className="container-site grid gap-10 py-14 md:grid-cols-2 lg:grid-cols-[1.4fr_1fr_1fr_1fr]">
        <div className="grid content-start gap-4">
          <Logo height={32} />
          <address className="text-muted grid gap-2 text-sm not-italic">
            <span className="text-text font-semibold">{COMPANY.name}</span>
            <a href={`mailto:${COMPANY.email}`} className="hover:text-text flex gap-2">
              <Mail className="size-4" aria-hidden />
              {COMPANY.email}
            </a>
            <Link href="/contact" className="hover:text-text">All contact details</Link>
          </address>
          {COMPANY.social.length ? (
            <ul className="flex gap-3 text-sm">
              {COMPANY.social.map((s) => (
                <li key={s.href}>
                  <a href={s.href} rel="noopener me" className="text-muted hover:text-text">
                    {s.label}
                  </a>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
        <FooterList title="Programmes" links={[{ href: "/programmes", label: "All programmes" }, ...programmes]} />
        <FooterList
          title="Universities"
          links={[{ href: "/universities", label: "All universities" }, ...universities]}
        />
        <FooterList
          title="Eduwit"
          links={[
            { href: "/about", label: "About" },
            { href: "/how-it-works", label: "How it works" },
            ...(hasResources ? [{ href: "/resources", label: "Guides" }] : []),
            { href: "/contact", label: "Contact" },
            ...LEGAL_PAGES.map((l) => ({ href: `/legal/${l.slug}`, label: l.title })),
          ]}
        />
      </div>
      <div className="border-border border-t">
        <p className="container-site text-subtle py-5 text-xs">
          © {COMPANY.name}. {FEE_DISCLAIMER}
        </p>
      </div>
    </footer>
  );
}

function FooterList({ title, links }: { title: string; links: { href: string; label: string }[] }) {
  return (
    <nav aria-label={title} className="grid content-start gap-3">
      <p className="eyebrow">{title}</p>
      <ul className="grid gap-2 text-sm">
        {links.map((l) => (
          <li key={l.href}>
            <Link href={l.href} className="text-muted hover:text-text">
              {l.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
