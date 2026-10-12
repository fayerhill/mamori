# Mamori design QA

Date: 2026-10-12

Final result: passed

Scope: the local native macOS preview and the requested compact interface revisions. This result does not certify live network enforcement or distribution readiness.

## Reference and intentional changes

The original locally retained Night Watch reference was compared with the implementation during the earlier visual review. The user's subsequent instruction explicitly supersedes that direction: simplify the app to an Apple-native utility with system sans-serif typography and standard controls. The final reference is this updated instruction, not the original decorative composition. Local design references are not included in the public repository.

Later user instructions intentionally supersede the original composition:

- Reduce the content panel to 280 × 290 pt, comparable to a compact VPN utility.
- Remove the tagline, large hero shield, oversized status heading, and redundant descriptions.
- Replace the decorative icon with a restrained frosted shield.
- Remove the large icon from the home panel; retain the small shield only as the app and menu-bar identity.
- Place Choose apps beneath Auto-quit apps, aligned to its left text edge.
- Use the system accent color for Start guarding and red for Stop guarding. Text labels also identify the action, so color is not the only distinction.
- Use the system sans-serif design for the wordmark, page headings, controls, and diagnostic text. Retain size and weight hierarchy without a second font design.
- Replace the fixed dark palette, decorative capsule buttons, and large page headings with adaptive system background/text colors, native buttons, standard dividers, and compact navigation headers.

## Evidence

The final build succeeded. Screenshots in `Artifacts` were refreshed on 2026-10-12 from the native-style binary, replacing the previous custom palette and serif captures. The installed-app picker capture and raw test log remain local and are excluded from the public repository.

| Check | Result |
| --- | --- |
| Home hierarchy and spacing | Passed; primary controls and footer fit without scrolling. |
| System sans-serif typography | Passed; wordmark, headings, buttons, and detail text use the native system font. |
| Start and Stop distinction | Passed; idle screenshot uses the native blue accent and protected/blocked previews are red. |
| Choose apps alignment | Passed; link and selected count share the Auto-quit apps text edge. |
| English, Simplified Chinese, Japanese | Passed; home labels fit in all three captured locales. |
| Installed app selection | Passed; searchable catalog includes both running and stopped apps, with native icons and a pinned Done action. |
| Custom awake duration | Passed in native UI inspection; editable minutes and distinct 30/60/120 shortcuts remain accessible in a scrollable section. |
| Settings | Passed; language and settings controls fit in a scrollable detail page. |
| Decoration | Passed; no hero icon, custom background treatment, decorative badge, or oversized page heading remains in the panel. |
| Native appearance | Passed in the captured light appearance; colors and controls use the system's adaptive APIs rather than a forced color scheme. |
| Native interaction | Passed; fresh accessibility state and screenshots confirm the revised home. Preview was returned to its inactive English home. |

No unresolved P0, P1, or P2 visual issues were identified within this scope. The original hero layout and custom color palette are deliberately not reproduced because the user requested a smaller, less verbose, native utility.

## Validation boundary

All visual state changes used `com.mamori.preview`, which always selects simulated protection, power, and termination effects. The app catalog is read-only. No VPN connection was disconnected, no packet-filter policy was loaded, no helper was installed, and no user work application was terminated during this review.

The existing local core test log records 34 passing tests. The final color, alignment, and typography changes were checked by rebuilding and inspecting the native UI; the full suite was not repeated for these presentation-only edits. Live network protection still requires a correctly signed helper and separate authorized validation.
