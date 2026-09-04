# Design QA

## Comparison target

- Source visual truth: user-provided `clipboard-2026-09-04-104648-327291A4.png` (Dashboard, 2342 × 1592 px) and `clipboard-2026-09-04-125609-5DB316CD.png` (Actions, 1876 × 1156 px). These source files are intentionally not committed because they contain third-party product imagery.
- Implementation screenshots: `docs/screenshots/dashboard.png` and `docs/screenshots/actions.png` (1920 × 1520 px each).
- Viewport: macOS section content rendered at 1280 × 1013 points and captured at 1.5× density. The native system sidebar and title bar are excluded from the implementation snapshots; they are rendered by `NavigationSplitView` in the running app.
- State: dark appearance, one saved/favorite watch, a cached reading, configured gesture actions, and no active Bluetooth session.
- Density normalization: each source and implementation image was proportionally resized into a 960 × 800 px comparison canvas. No geometry was stretched. Because the source aspect ratios differ, empty canvas space was ignored rather than interpreted as a layout defect.

## Full-view comparison evidence

The Dashboard keeps the source's two-column hierarchy: a prominent watch image and identity controls on the left, cached status and concise action rows on the right. The implementation intentionally replaces the Casio product photo and trademark-led copy with a neutral supplied watch image and independent WatchBridge language. It also makes the persisted reading explicit so disconnected use is understandable.

The Actions screen keeps the source's two-column card grid while reserving the same header, description, picker, optional-value, and hint regions in every card. This resolves the visibly uneven card alignment in the source. A full-width physical A/B/C/D guide now precedes the cards.

## Focused-region comparison evidence

The first and second action rows were inspected at their native 1920 px implementation capture. Card edges, titles, test buttons, selectors, optional value fields, and footer hints align on shared horizontal tracks. The details are legible in the native capture, so no additional enlarged crop was needed.

## Required fidelity surfaces

- Fonts and typography: native system typography preserves the source's compact macOS hierarchy. Headings, labels, helper text, code badges, wrapping, and truncation have distinct, consistent weights and line heights.
- Spacing and layout rhythm: 24-point page margins, consistent section gaps, equal-height 318-point action cards, and fixed internal regions remove the source's staggered controls. Content scrolls within a bounded minimum window rather than pushing navigation out of place.
- Colors and visual tokens: dark native materials, restrained borders, semantic blue controls, green cached-battery state, and orange waiting state preserve the intended hierarchy with improved contrast consistency.
- Image quality and asset fidelity: the supplied neutral watch PNG is sharp, centered, and aspect-fit on both Dashboard and button guide. No third-party model image is bundled, and user photos remain optional local assets.
- Copy and content: all product copy is English. Offline/cached state, physical-watch trust, exact-model selection, and independent-project status are stated directly.

## Comparison history

- Earlier P1: action cards had different heights and controls landed on inconsistent rows. Fix: every card now uses the same fixed height and explicit internal layout regions. Post-fix evidence: `docs/screenshots/actions.png`.
- Earlier P1: users could not see which physical button produced each gesture. Fix: added the visual A/B/C/D watch guide above the action grid. Post-fix evidence: `docs/screenshots/actions.png`.
- Earlier P2: the product image was too small and model-specific imagery could imply bundled Casio assets. Fix: enlarged the neutral default image and made local user-supplied photos/model labels first-class controls. Post-fix evidence: `docs/screenshots/dashboard.png` and `docs/screenshots/my-watches.png`.
- Earlier P2: disconnected status displaced useful information. Fix: the Dashboard now prioritizes the last saved reading and labels its timestamp without requiring reconnection. Post-fix evidence: `docs/screenshots/dashboard.png`.

## Findings

No actionable P0, P1, or P2 visual differences remain for the requested macOS redesign. The deliberate differences from the references are the English copy, neutral branding, larger default image, cached-state emphasis, and added button guide.

## Primary interactions checked

- Sidebar selection and bounded scrolling.
- Exact-model and favorite-watch selection.
- Local photo chooser entry point.
- Action selection, optional value entry, and manual Test affordance.
- Empty/disconnected and cached-reading presentation.

## Follow-up polish

- P3: capture equivalent Windows screenshots on a physical Windows 11 machine after the first CI artifact is available, so Mica rendering can be compared independently of the shared layout definition.

final result: passed
