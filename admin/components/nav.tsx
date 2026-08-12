'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const LINKS = [
  { href: '/', label: 'Overview' },
  { href: '/participants', label: 'Participants' },
  { href: '/uploads', label: 'Uploads' },
  { href: '/operations', label: 'Operations' },
  { href: '/audit', label: 'Audit trail', minRole: 'admin' as const },
];

export function Nav({ role }: { role: 'viewer' | 'researcher' | 'admin' }) {
  const pathname = usePathname();

  return (
    <nav className="space-y-0.5">
      {LINKS.filter((link) => !link.minRole || link.minRole === role).map((link) => {
        const active = link.href === '/' ? pathname === '/' : pathname.startsWith(link.href);

        return (
          <Link
            key={link.href}
            href={link.href}
            className={`block rounded-lg px-3 py-2 text-sm transition ${
              active
                ? 'bg-surface-2 font-medium text-ink'
                : 'text-ink-dim hover:bg-surface/70 hover:text-ink'
            }`}
          >
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
