'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const LINKS = [
  { href: '/progress', label: 'Progress Review' },
  { href: '/participants', label: 'All Participants' },
  { href: '/uploads', label: 'File Uploads' },
];

export function Nav({ role: _role }: { role: 'viewer' | 'researcher' | 'admin' }) {
  const pathname = usePathname();

  return (
    <nav className="space-y-0.5">
      {LINKS.map((link) => {
        const active = pathname === link.href || (link.href === '/progress' && pathname === '/');

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
