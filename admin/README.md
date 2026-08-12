# DopaX Admin Console

Staff-facing web console for monitoring participant activity in the DopaX / PDCollect study.

It is a reader. Nothing here writes participant data, changes a credential, or touches Google
Drive. The two things it can write are both human decisions that the backend refuses to guess:
resolving a contested participant code, and resolving an unattributable Drive object.

Read [`../backend/docs/MIGRATION_PLAN.md`](../backend/docs/MIGRATION_PLAN.md) for why the study is
mid-migration, and [`../backend/README.md`](../backend/README.md#the-admin-console-api) for the API
this app consumes.

## Quick start

The backend must be running first, with `ADMIN_API_ENABLED=true`.

```bash
cd ../backend
npm run stack:up
npm run dev                              # API on :8080
npm run staff:add -- --email you@example.com --role admin --name "Your Name"

cd ../admin
cp .env.example .env.local
npm install
npm run dev                              # console on :3100
```

Then open <http://localhost:3100> and sign in with the email you just added.

With `ADMIN_DEV_LOGIN=true` in the backend, the login page accepts a bare email and no password.
That bypass only exists in development — the backend refuses to boot with it enabled in production,
so it cannot be left switched on by accident.

## Why the token never reaches the browser

Every backend call is made by the Next server, not by the page. The staff JWT lives in an httpOnly,
SameSite=Strict cookie that client JavaScript cannot read, and the browser only ever receives
already-rendered HTML.

The practical consequence: an XSS bug in this console cannot exfiltrate a token that would let an
attacker read the whole study. It would have to keep asking this server, which is authenticated,
audited, and role-limited per request.

This is also why almost every component is a server component. If you find yourself needing
`useEffect` to fetch study data, the data should be fetched in the page instead.

## What the pages are for

| Page | Question it answers |
|---|---|
| Overview | Is the study healthy, and is the migration safe to complete? |
| Participants | Who is enrolled, and who has gone quiet? |
| Participant detail | What has this person actually done, and where are the gaps? |
| Uploads | Is data still arriving, and from which platforms? |
| Operations | What needs a human decision, and what did the first-run migration do? |
| Audit | Who looked at which participant, and when? (`admin` only) |

## Reading an empty panel correctly

An empty panel during a migration is ambiguous: it can mean "nothing happened" or "the thing that
fills this has not run". Confusing the two is how a study loses a month, so the console labels the
difference explicitly rather than rendering a blank card.

Concretely, uploads are catalogued from the Drive corpus but not yet stream-parsed, so events, test
sessions and daily summaries are genuinely empty and say so. Adherence is therefore computed from
upload history alone, which is why participant detail talks about collection days rather than
sessions.

## Roles

The backend redacts before it responds — a `researcher` response does not contain an email address
to leak, rather than containing one that the UI declines to draw. `identityVisible` on list
responses tells the UI which columns exist at all.

Participant codes and historical legacy codes stay visible to every role. Those are the study's own
pseudonyms and correlating them to old Drive filenames is the job.

## Environment

| Variable | Meaning |
|---|---|
| `ADMIN_API_URL` | Backend base URL, server-side only. Never exposed to the browser. |
| `SESSION_COOKIE_SECURE` | Set `false` for plain-HTTP localhost, `true` everywhere else. |
| `NEXT_PUBLIC_FIREBASE_*` | Only needed for Google sign-in. Omit entirely when using the dev login. |

## Checks

```bash
npx tsc --noEmit
npm run lint
npm run build
```
