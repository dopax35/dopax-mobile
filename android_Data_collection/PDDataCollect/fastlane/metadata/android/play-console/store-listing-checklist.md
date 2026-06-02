# Play Console — Store Listing checklist

Required asset specifications and notes. Anything below that needs to
be produced (icon, feature graphic, screenshots) is not generated here
because it requires graphic-design tooling — these are the specs to
hand to whoever produces them.

## Text fields

| Field             | Source                                                 | Limit       |
| ----------------- | ------------------------------------------------------ | ----------- |
| App name          | `fastlane/.../title.txt`                                | 30 chars    |
| Short description | `fastlane/.../short_description.txt`                    | 80 chars    |
| Full description  | `fastlane/.../full_description.txt`                     | 4000 chars  |
| What's new        | `fastlane/.../changelogs/39.txt`                        | 500 chars   |
| Email             | The PI's email — paste in Console                       | required    |
| Privacy Policy URL| Public HTTPS URL hosting `privacy_policy.html`          | required    |

## Categorization

* App or game: **App**
* Category: **Medical**
* Tags (up to 5): "Health & Fitness", "Medical", "Research"

## Target audience

* Target age groups: **18 and older.** This is a research-only app for
  enrolled adult participants. Do NOT target a minor age group; that
  triggers the Designed-for-Families program with extra requirements
  the app does not meet.
* The Play Console question "Is your app appealing to children?":
  **No.**

## Distribution

* Countries: select only the countries where the study has IRB /
  ethics-board approval. For a friends-and-family pilot,
  **Internal testing track** is the right release channel — it does
  not require store-listing review and reaches up to 100 testers
  invited by email.
* Internal testing has no Play Store listing requirement; the app
  stays unlisted. Testers install via a one-tap link emailed by Play
  Console.

## Graphic asset specs

These must be produced by a designer — only specs here.

| Asset             | Required | Spec                                                                         |
| ----------------- | -------- | ---------------------------------------------------------------------------- |
| App icon          | Yes      | 512 × 512 px, 32-bit PNG with alpha. The mipmap `ic_launcher` you ship is rendered separately on devices; this is the *store* icon. |
| Feature graphic   | Yes      | 1024 × 500 px, JPG or 24-bit PNG (no alpha). Shown atop the listing.         |
| Phone screenshots | 2–8      | 16:9 or 9:16, min 320 px, max 3840 px on the long edge, JPG or 24-bit PNG.   |
| 7" tablet         | optional | as above, 1024–7680 px long edge.                                            |
| 10" tablet        | optional | as above.                                                                    |

For the feature graphic, recommend keeping app text out (Google
overlays the app name on it).

## Suggested screenshots (in this order)

1. The Consent screen (showing the participant they understand what's
   collected before installing).
2. The daily home screen with "Start test battery" prominent.
3. Mid-test: spiral being traced (motion blur OK — communicates
   "drawing").
4. Mid-test: finger tapping with the moving target.
5. Settings → "Body side" card showing the dominance + affected-side
   choice (the new metadata feature).
6. Settings → the prominent "Withdraw from study" outlined button
   (signals user-control).

If you have only time for two, ship #2 and #5: they answer the two
questions reviewers ask first ("what does it do?" and "can I quit?").

## Pre-launch report concerns to expect

When you upload the AAB Google runs an automated pre-launch test on
real devices. Likely flags for this app:

* "Accessibility Service usage" — Google's policy team will review.
  Have the Data Safety justification (see `data-safety.md`) handy;
  responses must be submitted within 7 days or the app is removed.
* "Foreground service `specialUse`" — must include the `<property>`
  element with `android:value` describing what the special use is.
  The current manifest already has this; if Console flags it, paste
  the `subtype` text from the manifest's `<service>` blocks.
* "Background location" — none expected. App has no location
  permissions; if you see this flag, it is wrong, contest it.
