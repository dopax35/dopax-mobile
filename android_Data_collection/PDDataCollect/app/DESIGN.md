# Design System Specification: The Empathetic Anchor

## 1. Overview & Creative North Star
**Creative North Star: The Guided Sanctuary**
This design system rejects the clinical coldness of traditional medical software in favor of a "Guided Sanctuary"—an editorial, high-end environment that feels both authoritative and deeply calming. For patients managing Parkinson’s, cognitive load and motor precision are at a premium. We move beyond the generic "dashboard" look by using intentional asymmetry, generous white space (breathing room), and a sophisticated tonal hierarchy. 

The layout should feel like a premium health journal. By utilizing large, high-contrast typography scales and overlapping surface layers, we create a clear path for the eye, ensuring the most critical health data is never lost in a "sea of boxes."

## 2. Colors
Our palette is rooted in a spectrum of trustworthy deep blues and restorative teals, balanced against a pristine, "bright-paper" background.

### Core Palette (Material Design Convention)
*   **Primary:** `#004086` (Authority/Action)
*   **Primary Container:** `#1e58a7` (Deep Softened Action)
*   **Secondary:** `#006874` (Medical Calm/Teal)
*   **Surface:** `#faf9ff` (The Foundation)
*   **Surface Container Lowest:** `#ffffff` (Floating Card/Focus)
*   **Surface Container High:** `#e7e7f0` (Background Depth)
*   **Tertiary:** `#702e00` (Used sparingly for urgent warnings/high-contrast alerts)

### The "No-Line" Rule
Standard 1px borders are strictly prohibited for sectioning. Boundaries must be defined through background color shifts. To separate a main feed from the background, place a `surface-container-low` section on a `surface` background. This creates a sophisticated, "borderless" look that is easier on the eyes and feels more modern.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. 
*   **Level 0:** `background` (#faf9ff).
*   **Level 1:** `surface-container-low` (#f3f3fb) for main content areas.
*   **Level 2:** `surface-container-lowest` (#ffffff) for interactive cards.
This nesting creates natural depth without the visual clutter of heavy lines.

### The "Glass & Gradient" Rule
For floating elements, such as "Add Symptom" buttons or "Medication Reminder" overlays, use Glassmorphism. Apply `surface` colors at 80% opacity with a `20px` backdrop blur. For main CTAs, use a subtle linear gradient from `primary` (#004086) to `primary_container` (#1e58a7) to provide a "jeweled" professional finish.

## 3. Typography
We use **Lexend** across all scales. Lexend was specifically designed to reduce visual stress and improve reading performance, making it the ideal choice for this user base.

*   **Display (lg/md/sm):** Used for primary data points (e.g., "90% Mobility"). Large, bold, and authoritative.
*   **Headline (lg/md):** Used for screen titles. These should be positioned with intentional asymmetry—often left-aligned with a large top-margin to establish an editorial feel.
*   **Title (lg/md/sm):** Used for card headings and section headers.
*   **Body (lg/md):** All functional text. Maintain a minimum of `body-md` (0.875rem) for critical patient information to ensure legibility.
*   **Label (md/sm):** Used for micro-copy, timestamps, and secondary metadata.

## 4. Elevation & Depth
In this design system, depth is a functional tool for accessibility, not just an aesthetic choice.

### Tonal Layering
Instead of traditional shadows, stack surface tiers. Place a `surface-container-lowest` (#ffffff) card on top of a `surface-container-high` (#e7e7f0) background. This "soft lift" provides enough contrast for users with visual impairments without the "muddy" look of low-quality shadows.

### Ambient Shadows
When a component must float (e.g., a bottom navigation bar or a critical modal), use "Ambient Shadows":
*   **Color:** `#191b21` at 6% opacity.
*   **Blur:** `24px` to `40px`.
*   **Spread:** `-4px`.
This mimics natural light and keeps the UI feeling light and airy.

### The "Ghost Border" Fallback
If a container requires a border for accessibility (e.g., high-glare environments), use the **Ghost Border**: `outline-variant` (#c3c6d4) at 15% opacity. Never use 100% opaque borders.

## 5. Components

### Buttons
*   **Primary:** `primary` to `primary_container` gradient. Moderate roundness (`md`: 0.75rem). Label: `title-sm` (white).
*   **Secondary:** No background. `ghost-border` (#c3c6d4 at 20%) with `primary` text.
*   **Tap Targets:** Minimum height of `48px` (3.5 spacing unit) to accommodate tremors.

### Cards & Lists
*   **Card Style:** Use `surface-container-lowest` with a `md` (0.75rem) or `lg` (1rem) corner radius.
*   **No Dividers:** Prohibit the use of divider lines between list items. Instead, use a `1.4rem` (4 spacing unit) vertical gap. Use a subtle background shift (`surface-container-low`) on every other item if a visual break is required.

### Symptom Trackers (Specialty Component)
*   **Interactive Spheres:** Inspired by the app icon, use "beaded" sliders for symptom intensity. Each "bead" should use a `secondary` (#006874) fill when active, with a soft `surface_tint` glow.

### Input Fields
*   **State:** Unfocused fields should use `surface-container-high`.
*   **Focus State:** Shift to `surface-container-lowest` with a `2px` `primary` "Ghost Border." Use `title-md` for input text to ensure maximum clarity.

## 6. Do's and Don'ts

### Do:
*   **Do** use asymmetrical layouts. For example, a large headline on the left with a smaller "Medication Status" chip floating to the right.
*   **Do** use the `16` (5.5rem) spacing unit for top-of-page gutters to give the UI a "premium editorial" feel.
*   **Do** ensure all interactive elements have at least `8px` of spacing between them to prevent accidental taps.

### Don't:
*   **Don't** use 1px solid dividers. They add visual noise and increase cognitive load.
*   **Don't** use pure black (#000000). Use `on-surface` (#191b21) for text to maintain a softer, high-end contrast.
*   **Don't** use "Small" (sm) roundness for primary containers. It feels too rigid. Stick to `md` (0.75rem) or `lg` (1rem) to maintain a modern, stable personality.