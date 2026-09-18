# Design system integration — Stage A audit

Scope: the ten items (INK-1, INK-2, INK-3, INK-4, INK-6, INK-7, INK-8, UI-1,
UI-2, UI-3) plus the token layer (Palette/Motion/Haptics), against the repo
at `docs/DS-CONFLICTS.md`'s own branch, `design-system`, branched from `main`
at commit `7fc7522`.

Labeled `DS` throughout, not `M4`/`M5` — this repo's founding brief already
defines M0–M8 as a sequential product-feature roadmap (M4 = provider seam,
M5 = tutor loop, M6 = the ladder, M7 = problems in, M8 = session
summary/TestFlight/exam mode). Design-system integration is a cross-cutting
concern, not one of those features, so it doesn't borrow a number from that
sequence. See conversation for the two corrections that led here — the first
proposed label ("M4") collided with the real M4 in `docs/status/current.md`;
the second ("M5") collided with the real M5 in the founding brief and in
`CanvasController.swift`'s own comment ("That is M5's job").

**Working-tree note:** `main` currently carries uncommitted WIP (per your
instruction, left untouched) that is the real M4's in-progress on-device
test: `CanvasController.swift`, `AppEnvironment.swift`, `CanvasScreen.swift`,
`TutorConfig.swift`, `AIProvider.swift`, `CoreGraphicsStrokeRasterizer.swift`,
plus two new untracked files, `APIKeySettingsView.swift` and
`DebugEvaluationResultView.swift`. All of it is carried onto this branch
unmodified. Everything below reflects the tree as it currently stands,
WIP included.

**Architecture baseline, relevant to every finding below:** the canvas today
is 100% native PencilKit — `PKCanvasView` + `PKToolPicker` + `PKInkingTool`.
There is no custom on-screen rendering layer, and a repo-wide grep for
`Animation`/`.spring`/`withAnimation`/`UIImpactFeedbackGenerator`/
`UINotificationFeedbackGenerator` in `App/Slate` and
`Packages/SlatePlatform/Sources` returns **zero matches**. Nothing here is a
retrofit; most of the ten items are net-new interaction code, not token
swaps. That materially changes the risk profile of several items — flagged
individually below.

Layer purity holds today: `grep -rl "import SwiftUI\|import UIKit"
Packages/SlateCore/Sources` returns nothing. None of the ten items require
touching `SlateCore`.

---

## A1. Hardcoded values inventory

### Animation / duration literals

**None exist.** Every animated behavior the ten items ask for (INK-3's
settle, INK-7's velocity-carried zoom, INK-8's reverse-draw, UI-3's chrome
fade) is new code, not a value to swap. Noted here rather than left silent,
per the instruction not to skip a category because it's empty.

### Color literals

**MECHANICAL** — maps cleanly to a token, safe swap:

| File:line | Current | Maps to |
|---|---|---|
| `CanvasScreen.swift:126` | `.foregroundStyle(.secondary)` (status line text) | `Palette.inkSoft` |
| `CanvasScreen.swift:147` | `.foregroundStyle(.secondary)` (saved-state label) | `Palette.inkSoft` |
| `DebugEvaluationResultView.swift:62,72,91` | `.foregroundStyle(.secondary)` | `Palette.inkSoft` — *see C-8, this file may be out of scope entirely* |

**JUDGMENT** — current value differs meaningfully from the spec, or has no
clean token:

| File:line | Current | Issue |
|---|---|---|
| `InkCanvasView.swift:45` | `canvas.backgroundColor = .systemBackground` | Conceptually → `Palette.paper`, but this is a flat `UIColor` with no grain/ruling. Swapping the color alone satisfies nothing in INK-1/INK-2 — see C-4. |
| `InkCanvasView.swift:55` | `PKInkingTool(.pen, color: .label, width: 3)` | The entire current "tool" implementation: one hardcoded pen, `.label`, width 3, with no ink/marker choice at all. Real work is INK-4, not a token swap — see C-2. |
| `CanvasScreen.swift:103, 129` | `.background(.thinMaterial, in: Capsule())` (×2) | Legacy `Material`, not the Liquid Glass API (`.glassEffect`), and used **twice** — see C-1. |
| `CanvasScreen.swift:118` | `Color.secondary.opacity(0.15)` ("M2" build badge) | This is a hardcoded milestone-debug label ("M2"), not a token gap — see C-6. Product question, not a style one. |
| `CanvasScreen.swift:153` | `.foregroundStyle(.red)` (SAVE FAILED) | No error/warning token exists anywhere in the section-3a Palette. Section 3a defines `paper/surface/graphite/inkSoft/inkFaint/hairline/pen/tutor/tutorWash/inks/markers` — nothing for alerts. Gap, not a mapping — see C-7. |
| `APIKeySettingsView.swift:42` | `.foregroundStyle(.red)` (Keychain error) | Same gap as above. |
| `DebugEvaluationResultView.swift:51` | `.foregroundStyle(.orange)` (tutor refusal) | Same gap; also tutor-adjacent — see C-7, C-8. |
| `DebugEvaluationResultView.swift:58` | `Color.accentColor.opacity(0.15)` (hint-rung chip) | System accent (undefined in this app, defaults to blue), on a view that renders `TutorResponse` directly. If retokenized at all this arguably wants `Palette.tutorWash`, but the file itself may be off-limits — see C-8. |
| `DebugEvaluationResultView.swift:83` | `.foregroundStyle(.red)` (failed evaluation) | Same gap as `CanvasScreen.swift:153`; also tutor-adjacent. |

**Excluded from this inventory, not mechanical or judgment — out of scope
by nature:**

- `CoreGraphicsStrokeRasterizer.swift:82,120,145` — the opaque-white
  background and per-stroke `CGColor`s here render the image sent to the AI
  provider for evaluation, not on-screen UI. The code comment is explicit
  that this is deliberate: "Opaque white, always... black ink on a black
  background is a blank image that costs a request to discover." This is
  Layer 2 code in service of the tutor pipeline — see C-9.
- `PencilKitInkConverter.swift:193,232,253,272,280,282,291` — `UIColor`/
  `NSColor` construction here is round-tripping the domain's normalized
  `InkColor` to/from PencilKit's native color type. It's format conversion
  of *user-chosen* ink values, not a hardcoded design-system color.

---

## A2. Conflicts

### C-1 — Two translucent surfaces, neither is real Liquid Glass
Files:            `App/Slate/CanvasScreen.swift:103,129`
Spec says:        UI-1 — exactly one Liquid Glass surface (the floating
                   canvas toolbar, Regular variant); everything else opaque;
                   never stack translucency.
Code does:        `.thinMaterial` (a legacy SwiftUI `Material`, not the
                   `.glassEffect()` Liquid Glass API) on **both** the
                   top-leading status line and the top-trailing editing
                   controls.
Type:             structural
Risk if changed:  Status line currently reads clearly over any canvas
                   content because of the material blur; making it opaque
                   changes its contrast behavior — low risk, easy to check
                   in both themes.
Recommendation:   adopt spec
Why:              Neither surface is actually Liquid Glass today, so there's
                   no working behavior to preserve. Recommend `editingControls`
                   (undo/redo/clear/API key/Ask tutor) as the one Regular-glass
                   surface — it's the closer match to "the floating canvas
                   toolbar" — and make `statusLine` opaque (`Palette.surface`).

### C-2 — No custom tool set exists; canvas is bare native PencilKit
Files:            `App/Slate/InkCanvasView.swift:28-60`
Spec says:        INK-4 — exactly four tools (fountain pen, pencil,
                   highlighter, eraser), six inks, three markers, no color
                   wheel/eyedropper/hex field.
Code does:        `canvas.tool` is hardcoded to one `PKInkingTool(.pen,
                   color: .label, width: 3)` at view creation, and the
                   system `PKToolPicker` is attached and made visible — the
                   student currently gets Apple's own tool/color UI,
                   including its full color wheel and eyedropper.
Type:             structural
Risk if changed:  M1's ink-feel acceptance ("PASSED on device... pressure
                   and tilt detected") was verified against this exact
                   native-PencilKit setup. Ripping out `PKCanvasView`/
                   `PKInkingTool` and replacing Apple's rendering engine
                   would re-open that acceptance test and is far larger
                   than a design-system item. **That is not what INK-4
                   requires**, though: you can keep `PKCanvasView` +
                   `PKInkingTool` (so pressure/tilt/rendering stay exactly
                   what M1 verified) and only replace the *picker chrome* —
                   hide `PKToolPicker` (`setVisible(false...)`) and drive
                   `canvas.tool` from a new custom SwiftUI tray offering
                   just the four tools / six inks / three markers. Low risk
                   to ink feel if scoped that way.
Recommendation:   adopt spec, scoped to the picker only
Why:              Satisfies INK-4's letter without touching the rendering
                   engine M1 already proved. Flagged as the largest single
                   item in this batch — see A3.

### C-3 — No on-screen guarantee that highlighter renders behind ink
Files:            `App/Slate/InkCanvasView.swift`, `App/Slate/CanvasController.swift`
Spec says:        INK-4 — "The highlighter always composites BEHIND ink,
                   never over it."
Code does:        No highlighter tool exists on-screen at all yet (see
                   C-2). The only place a behind/over-compositing rule
                   exists today is `CoreGraphicsStrokeRasterizer.swift:130`
                   (`.multiply` blend), and that's for the tutor's snapshot
                   image, not what the student sees drawing.
Type:             structural
Risk if changed:  `PKDrawing` renders its `strokes` array in array order —
                   there's no native "layer" concept to put highlighters
                   behind ink regardless of draw order. The tractable fix is
                   to maintain the invariant that `canvas.drawing.strokes`
                   is kept sorted (all highlighter strokes first, then ink)
                   after every ingest, and re-set `canvas.drawing` — native
                   PencilKit compatible, no custom rendering needed, but is
                   new logic in `CanvasController`/the `Coordinator`, not a
                   flag flip.
Recommendation:   adopt spec
Why:              Achievable without abandoning PencilKit's renderer, but
                   it's real logic, not a style change — flagged so Stage B
                   doesn't treat it as free.

### C-4 — No paper grain or paper-style rendering exists in any form
Files:            `App/Slate/InkCanvasView.swift:45`
Spec says:        INK-1 (3% grain texture) and INK-2 (three papers: plain,
                   faint grid, dot grid).
Code does:        `canvas.backgroundColor = .systemBackground` — a flat
                   system color, no texture, no ruling, no per-paper switch,
                   and no UI anywhere to switch papers.
Type:             structural
Risk if changed:  Low risk to ink capture itself — a background layer
                   behind or within `PKCanvasView` doesn't touch stroke
                   input. Real work is generating/caching the grain texture
                   once and drawing the three rulings efficiently at canvas
                   scale (20,000×20,000pt content per `canvasExtent`).
Recommendation:   adopt spec
Why:              Additive; doesn't risk M1's verified ink feel. Needs a
                   place to put the paper-switch control — likely the same
                   tool tray being built for INK-4/C-2.

### C-5 — Ink settle has no addressable target to animate
Files:            `App/Slate/InkCanvasView.swift`
Spec says:        INK-3 — ease a completed stroke's opacity up 4% over
                   `Motion.inkSettle` once it's drawn.
Code does:        Strokes are rendered entirely inside `PKCanvasView`'s
                   internal (Metal-backed) view. There's no SwiftUI/UIKit
                   layer per stroke to attach an opacity animation to — the
                   delegate only learns a stroke completed
                   (`canvasViewDidEndUsingTool`), not a drawable handle for
                   that specific stroke.
Type:             structural
Risk if changed:  Unknown until prototyped. Two possible approaches: (a) a
                   transient custom overlay that redraws just the new
                   stroke and cross-fades it in as PencilKit's own render
                   settles underneath, or (b) determine it isn't achievable
                   against native `PKCanvasView` rendering and it needs to
                   be deferred pending the day the app moves to fully custom
                   ink rendering.
Recommendation:   needs a decision
Why:              This is the one item in the batch where I can't tell you
                   today whether the acceptance criterion is achievable at
                   all without a spike. Recommend prototyping it early (see
                   A4) rather than assuming it'll fall out of the token work.

### C-6 — The status line's "M2" badge is a milestone-debug label, not chrome
Files:            `App/Slate/CanvasScreen.swift:113-119`
Spec says:        Nothing directly — this isn't one of the ten items — but
                   section 2's rules ("no exclamation marks," restraint) and
                   the fact that the badge hardcodes a stale milestone
                   number make it worth flagging rather than silently
                   retokenizing.
Code does:        A capsule literally reading "M2," left over from the M1/M2
                   build-verification status line, now stale (the app is
                   past M4).
Type:             value-only, but the underlying question is a product one
Risk if changed:  None either way; it's debug-only chrome.
Recommendation:   needs a decision
Why:              Retokenizing its background color (mechanical, see A1) is
                   fine regardless, but whether the badge itself should keep
                   existing, get updated to say something current, or get
                   removed for a "premium... restraint" v1 is Andrew's call,
                   not something to fix quietly while passing through for
                   colors.

### C-7 — No error/warning token exists in the spec's own Palette
Files:            `CanvasScreen.swift:153`, `APIKeySettingsView.swift:42`,
                   `DebugEvaluationResultView.swift:51,83`
Spec says:        Section 3a's `Palette` enum defines ground, ink, the pen
                   accent, the reserved tutor color, six inks, three
                   markers — no error or warning color.
Code does:        Four call sites use system `.red`/`.orange` for save
                   failures, Keychain errors, and tutor refusals/failures.
Type:             value-only (but the gap is structural — the token doesn't
                   exist to map to)
Risk if changed:  "SAVE FAILED" is explicitly commented as "loud on purpose"
                   — CanvasController.swift's neighboring code calls a
                   silent failure "how a student loses an hour of work
                   without noticing." Whatever replaces `.red` here must stay
                   loud.
Recommendation:   needs a decision
Why:              Per section 8's precedence, I won't invent a token — is
                   system semantic red/orange deliberately exempt (an
                   OS-level alert outside the brand palette, on purpose,
                   because it must never be mistaken for a themed color), or
                   should Palette gain an explicit `alert`/`warning` token?

### C-8 — Two tutor-adjacent presentation files are new, untracked, and mid-test
Files:            `App/Slate/APIKeySettingsView.swift`,
                   `App/Slate/DebugEvaluationResultView.swift`
Spec says:        "Do not modify tutor code... The one exception is defining
                   the tutor color token itself, which is inert until
                   something uses it."
Code does:        Both files are untracked, both are part of the real M4's
                   uncommitted on-device test (per `docs/status/current.md`,
                   M4 is "wired to the UI; still not run against the real
                   API" — this is that wiring). `DebugEvaluationResultView`
                   renders `TutorResponse` directly: hint text, hint-ladder
                   rung, confidence, refusal reasons. `APIKeySettingsView` is
                   the Keychain-backed settings sheet for the provider key.
Type:             structural (scope boundary, not a value or behavior
                   disagreement)
Risk if changed:  If "tutor code" is read strictly, touching either file
                   — even just to retokenize a `.red` — is out of bounds for
                   this batch while M4 is mid-test, and any DS work here
                   should wait until that test lands and these files are
                   committed.
Recommendation:   needs a decision
Why:              The spec's own text ("tutor logic... views... layout...
                   colors") reads as covering `DebugEvaluationResultView`
                   pretty clearly. `APIKeySettingsView` is less clearly
                   "tutor" and more "settings for a tutor-adjacent
                   credential" — a Form with no hint-ladder content. I'd
                   treat both as hands-off for this batch by default, but
                   want your call rather than assuming.

### C-9 — The tutor's rasterizer intentionally ignores theme; leave it alone
Files:            `Packages/SlatePlatform/Sources/SlatePlatform/Rendering/CoreGraphicsStrokeRasterizer.swift:82,120,145`
Spec says:        Nothing directly targets this file (not presentation
                   layer in the visual-chrome sense), but the blanket rule
                   "no literal color... may appear anywhere else in the
                   presentation layer" could be misread to include it.
Code does:        Opaque white background, always, independent of app
                   theme, with a code comment explaining exactly why: it's
                   the image handed to the AI model, and "black ink on a
                   black background is a blank image that costs a request
                   to discover."
Type:             structural
Risk if changed:  Real product risk, not style: making this theme-aware
                   would change what the model sees per session, a
                   functional regression to the actual M4 acceptance test,
                   not a look-and-feel one.
Recommendation:   keep current
Why:              This is Layer 2 code in service of the tutor's vision
                   input, not UI chrome, and it's currently part of the real
                   M4's uncommitted WIP besides. Out of scope for this batch
                   on two independent grounds.

### C-10 — Native pan/zoom bounce already satisfies INK-6's acceptance criterion
Files:            `App/Slate/InkCanvasView.swift:40-44`
Spec says:        INK-6 — progressive resistance past canvas/zoom bounds, a
                   spring return, never a hard stop, with a suggested custom
                   resistance formula.
Code does:        `alwaysBounceVertical/Horizontal = true` plus
                   `minimumZoomScale`/`maximumZoomScale` — standard
                   `UIScrollView` elastic overscroll, inherited for free
                   through `PKCanvasView`. This already resists
                   progressively and springs back, with no hard stop, at
                   both pan and zoom extremes.
Type:             value-only (the acceptance criterion, not the mechanism)
Risk if changed:  Replacing working, already-verified-feeling native bounce
                   with the spec's custom resistance formula risks making
                   panning feel worse for no visible gain, and would need
                   its own on-device feel check the way M1's did.
Recommendation:   keep current
Why:              Per section 8's precedence ("working, tested behavior...
                   beats this spec"), and per the audit's own instruction to
                   say so when existing code already solves it. Recommend
                   treating INK-6 as verify-only in Stage B (confirm the
                   acceptance criterion by hand, no code change) unless you
                   specifically want the custom curve for some other reason
                   (e.g., matching a non-linear feel across pan and zoom that
                   native bounce doesn't give you).

---

## A3. Blast radius

| Item | Files touched | Additive / rewrite | Touches tutor code? |
|---|---|---|---|
| Tokens (Palette/Motion/Haptics) | New: `App/Slate/Theme/Palette.swift`, `Motion.swift`, `Haptics.swift`; new `Assets.xcassets` under `App/Slate` (none exists today — only unrelated XcodeGen test fixtures under `Tools/.xcodegen-src`) | additive | no |
| INK-1 (grain) | `InkCanvasView.swift` (+ a small texture-generation helper) | additive | no |
| INK-2 (three papers) | `InkCanvasView.swift`, plus wherever the paper-switch control lives (new tray from INK-4) | additive | no |
| INK-3 (ink settle) | `InkCanvasView.swift`/`Coordinator` — **feasibility unresolved, see C-5** | unclear until spiked | no |
| INK-4 (tool set) | `InkCanvasView.swift`, `Coordinator`, new tool-tray SwiftUI view, `CanvasController.swift` (stroke reordering for highlighter-behind-ink, C-3) | mixed — new tray is additive, hiding `PKToolPicker` and reordering strokes is a real behavior change | no, if C-8 rules `APIKeySettingsView`/`DebugEvaluationResultView` out of scope as expected |
| INK-6 (rubber-band) | none — verify only, see C-10 | n/a | no |
| INK-7 (zoom settle) | `InkCanvasView.swift`, `Coordinator` (pinch velocity + step logic), `CanvasScreen.swift` (scale HUD) | additive on top of native zoom | no |
| INK-8 (undo you can feel) | `InkCanvasView.swift`, `Coordinator` (two/three-finger tap gestures), `CanvasController.swift` (expose which stroke a native undo just removed — PencilKit's delegate gives no erase-specific event, confirmed by the existing code comment on `rebuildOperations`), `CanvasScreen.swift` (toolbar control restyle) | mixed — gestures are additive, the reverse-draw specifically shares INK-3's "animate PencilKit's own rendering" problem (C-5) | no |
| UI-1 (one glass toolbar) | `CanvasScreen.swift` only | rewrite of 2 call sites down to 1 | no |
| UI-2 (tools that show themselves) | New tool-tray view (shared with INK-4), a small standalone stroke-preview renderer — **write new, don't reuse or modify `CoreGraphicsStrokeRasterizer`, which is tutor-pipeline code per C-9** | additive, depends on INK-4 landing first | no |
| UI-3 (chrome yields to pencil) | `InkCanvasView.swift`'s `Coordinator` (implement the currently-unimplemented `canvasViewDidBeginUsingTool(_:)`), `CanvasScreen.swift` (opacity + debounced return) | additive | no |

**Summary: none of the ten items require touching tutor code**, provided
C-8 is resolved as "hands off" for `APIKeySettingsView.swift` and
`DebugEvaluationResultView.swift` as I'd recommend by default.

---

## A4. Proposed order

Differs from section 4's listed order — sequenced here by dependency and by
front-loading the one item whose feasibility is genuinely unknown (C-5), so
a bad answer there surfaces early rather than after other work is built on
an assumption about it.

1. **Tokens** — Palette/Motion/Haptics + Assets.xcassets + CLAUDE.md rules
   block. Prerequisite for everything.
2. **INK-3 spike** — before committing it to the batch, a short prototype to
   determine whether a per-stroke opacity settle is achievable against
   native `PKCanvasView` rendering at all (C-5). If it isn't, that's a
   decision for you, not a silent descope.
3. **UI-1** — smallest, self-contained, immediately visible, resolves C-1.
4. **INK-6** — verify-only against existing native bounce (C-10); cheap to
   close out early.
5. **INK-1, INK-2** — paper grain and the three papers; additive, no
   gesture work, establishes the ground before the tool tray needs a home
   for its paper-switch control.
6. **INK-4** — the tool tray, hidden `PKToolPicker`, highlighter-behind-ink
   reordering (C-2, C-3). Largest single item; everything below depends on
   the tray existing.
7. **UI-2** — tool tray live stroke samples, built on INK-4's tray.
8. **UI-3** — chrome fade on stroke begin/end; independent, but natural to
   land once the tray from INK-4 exists so both toolbars behave alike.
9. **INK-7** — zoom settle-to-step, scale HUD, double-tap-to-100%.
10. **INK-8** — undo/redo gestures land first (straightforward); the
    reverse-draw animation specifically shares INK-3's rendering problem, so
    do it last, informed by whatever INK-3's spike concluded.

Nothing recommended for deferral out of this batch outright — INK-3 is the
one item whose *inclusion* depends on the spike in step 2.

---

## Summary

- **Mechanical color replacements:** 3 (`CanvasScreen.swift:126,147`,
  `DebugEvaluationResultView.swift:62,72,91` — the latter group contingent
  on C-8).
- **Judgment-flagged values:** 9, of which 2 (`CanvasScreen.swift:153`,
  `APIKeySettingsView.swift:42`, `DebugEvaluationResultView.swift:51,83` —
  4 call sites) share one root cause (C-7, no error token in spec).
- **Conflicts by type:** 6 structural (C-1 through C-5, C-9), 2 value-only
  (C-6, C-10 — C-10 recommends keep-current), 1 scope-boundary (C-8), plus
  C-7's token gap.
- **Excluded outright:** `CoreGraphicsStrokeRasterizer.swift` (C-9, tutor
  vision pipeline) and `PencilKitInkConverter.swift`'s color bridging (not a
  design-system literal at all).

**The three decisions I most need from you:**

1. **C-8** — are `APIKeySettingsView.swift` and `DebugEvaluationResultView.swift`
   "tutor code" (hands-off for this whole batch) or fair game chrome to
   retoken? I'd default to hands-off.
2. **C-7** — does `Palette` gain an explicit alert/warning token, or is
   system `.red`/`.orange` deliberately exempt from the brand palette for
   loud, OS-level failure states?
3. **C-5** — should I spend the step-2 spike time now to find out whether
   INK-3 (ink settle) is achievable against native PencilKit rendering at
   all, before the rest of the batch proceeds?

Also flagging, not blocking: **C-6** (the stale "M2" debug badge) and
**C-10** (recommend treating INK-6 as verify-only against already-working
native bounce, per section 8's precedence for working tested behavior).

Stage B does not begin until you say "go" and answer these.

---

## Decisions

**C-8 — hands-off.** `APIKeySettingsView.swift` and
`DebugEvaluationResultView.swift` are tutor code for the purposes of this
batch. Not touched, not retokenized, not even for the mechanical
`.secondary` swaps listed in A1. Their `.red`/`.orange` literals stand.

**C-7 — add an alert token.** `Palette` gains one new token,
`Palette.alert`, for loud failure states — scoped to the one call site this
decision actually reaches: `CanvasScreen.swift:153` ("SAVE FAILED"). The
other three `.red`/`.orange` sites (`APIKeySettingsView.swift:42`,
`DebugEvaluationResultView.swift:51,83`) are now out of reach per C-8 and
keep their literals. `alert` will be a dedicated warm red distinct from
`Palette.inks[2]` (`InkCrimson`) — reusing the ink swatch would make a
system failure state visually indistinguishable from a student's own chosen
ink color, which defeats the point of a dedicated token.

**C-5 — proceed without a feasibility spike.** INK-3 (ink settle) stays in
the batch at its normal place in the build order. If a genuine per-stroke
opacity animation against native `PKCanvasView` rendering turns out not to
be cleanly achievable, land the closest reasonable approximation and note
what was simplified in the commit message, rather than blocking on it. Per
your instruction: a minor visual shortfall here doesn't matter enough to
stop for.

**C-6 — not yet decided, non-blocking.** The stale "M2" debug badge. Default
plan absent further direction: retokenize its background color only
(mechanical swap, `Palette.hairline` or similar), leave the "M2" text and
its presence as-is — i.e., treat it as out of scope for this batch rather
than silently removing debug chrome you may still want. Flag again if you'd
rather it be updated or removed.

**C-10 — confirmed keep-current.** INK-6 is verify-only: confirm the
native `UIScrollView` bounce (inherited through `PKCanvasView`) already
satisfies the acceptance criterion by hand on device; no code change.

**C-5 — resolved: not implemented.** Confirmed infeasible against native
`PKCanvasView` rendering, consistent with the same root cause flagged
during `DS/INK-4` (highlighter z-order) and `DS/INK-8` (undo's reverse-draw
approximation): PencilKit renders `.drawing` internally, with no
per-stroke handle this app can attach an opacity animation to. Unlike
INK-8, no honest partial version exists here — INK-3's effect is specced
as "subliminal at real speed," and a crude stand-in (e.g. a bounds
highlight, the approach used for INK-8) would be *more* visible than the
real effect was ever meant to be, misrepresenting the design rather than
approximating it. Per your instruction that a minor visual shortfall here
doesn't matter enough to block on, this is skipped rather than faked. No
commit — there is no code to land.

**C-3 — accept current behavior, decided during INK-4's implementation.**
The literal always-behind z-order guarantee turned out to conflict with
`CanvasController.ingest`'s append-only stroke diffing (see the
`DS/INK-4` commit message for the full reasoning) — reordering
`PKDrawing.strokes` risked misattributing strokes to the wrong document
operations. Accepted as-is: highlighter uses PencilKit's native `.marker`
ink type in normal chronological draw order, which is already translucent
enough that ink stays legible when highlighted over. `Palette.markerBlend`
remains defined but has no call site — `PKInkingTool` exposes no blend-mode
hook for on-screen rendering. The literal always-behind guarantee (most
likely two coordinated canvas layers) is not planned as follow-up work
unless raised again later.

**Revised build order (A4), with the INK-3 spike step removed per C-5:**

1. Tokens (Palette incl. `alert` / Motion / Haptics + Assets.xcassets + CLAUDE.md rules block)
2. UI-1 (one glass toolbar)
3. INK-6 (verify only, on-device)
4. INK-1, INK-2 (grain, three papers)
5. INK-4 (tool tray, hidden `PKToolPicker`, highlighter-behind-ink)
6. UI-2 (tool tray live samples)
7. UI-3 (chrome yields to pencil)
8. INK-7 (zoom settle)
9. INK-8 (undo you can feel)
10. INK-3 (ink settle — best-effort per C-5)
