# Slate — engineering guide

Read this before touching anything in this repo. It governs how you work here
on every turn, not just the first one.

## What this is

An infinite-canvas handwriting app for iPad in which an AI tutor watches the
user work problems by hand and places hints on the canvas — never the answer.
v1 is iPadOS, native Swift, SwiftUI + PencilKit, bring-your-own API key, no
backend. It must port to iPhone, Mac, Android, and Windows afterward, and it
must be able to grow a cloud backend later without a rewrite. v1.5 extends the
same loop to reading, writing, and document analysis.

Full context, read before anything architectural:

- `docs/brief/founding-brief.txt` — v1 scope, the four-level hint ladder, the
  tutor loop's trigger events, `TutorConfig`, milestones M0–M8, and section
  10 (the six forward-compatibility changes v1.5 requires, C1–C6).
- `docs/brief/v15-addendum.txt` — v1.5 text-work scope (reading, planning,
  drafting surfaces), the writing and reading hint ladders, R6 (the prose
  rule), text-domain triggers, milestones M9–M14.
- `docs/brief/origin-context.txt` — the prototype origin story and the
  problem statement this whole product answers.
- `docs/decisions/log.md` — architectural decisions, dated, with the options
  considered and the reason. Append to it; do not rewrite history.
- `docs/status/current.md` — **read this first.** Where the build actually
  stands right now: which milestone, what's built, what's unverified, what's
  next. Keep it current as you finish work.

These same documents also live in a claude.ai Project ("AI Live tutoring")
that Andrew uses for planning conversations outside the terminal. The two
copies are kept in sync by hand — if you add a decision or change status here,
say so, and Andrew (or a future session) should mirror it there. Don't let
them silently diverge.

## Who you're working with

A solo builder: mechanical engineering student, runs a real business, does
freelance web development. Technically fluent, reads code comfortably, is not
a career iOS developer. Do not explain what a variable is. Do explain Swift
concurrency, PencilKit internals, CloudKit behavior, and App Store mechanics
when they come up.

He prefers step-by-step instructions as downloadable .docx or .txt files
rather than long inline text or markdown artifacts. When you produce a guide,
a runbook, a setup procedure, or a checklist he will follow away from the
screen, write it to a file.

## The five standing invariants

These are not preferences. Violating one is a bug, even if the code runs.
Every piece of code you write is subject to all five, permanently.

**INVARIANT 1 — LAYER PURITY.** The codebase has exactly three layers with
enforced boundaries:

- Layer 1, Domain core. Pure Swift. Imports Foundation and nothing else.
  Contains the document model, stroke geometry, problem model, tutor state
  machine, AI provider adapters, prompt construction, response parsing,
  error classification, and session history.
- Layer 2, Platform services. Thin adapters implementing protocols declared
  in Layer 1: ink capture, rendering, persistence, sync, PDF, camera,
  Keychain, networking.
- Layer 3, UI. SwiftUI/UIKit views. Zero business logic.

Layer 1 lives in its own Swift package (`Packages/SlateCore`) and MUST
compile and pass its tests on Linux. If a change would put SwiftUI, UIKit,
PencilKit, CloudKit, CoreGraphics, or any Apple-only type into Layer 1, the
change is wrong — restructure it. Run `./Tools/check-layer-purity.sh` before
delivering anything. This single rule is what makes the Android and Windows
ports tractable. Do not erode it for convenience, and tell Andrew if he asks
you to.

**INVARIANT 2 — NO PROPRIETARY FORMAT AS SOURCE OF TRUTH.** Ink is stored in a
normalized, platform-independent representation: ordered points with
pressure, tilt, azimuth, and timestamp. PencilKit's `PKDrawing` may be cached
alongside it as a rendering optimization, never as the canonical record. The
same applies to any Apple-specific serialization anywhere in the document
model. If the only copy of user data is in an Apple format, the app is
un-portable regardless of how clean the layering looks.

**INVARIANT 3 — EVERY EXTERNAL DEPENDENCY SITS BEHIND A PROTOCOL.** AI
providers, storage, sync, auth, file import, telemetry, payments. Each is a
protocol declared in Layer 1 with concrete implementations in Layer 2. Adding
Gemini, swapping CloudKit for a custom backend, or supporting a local model
must mean writing one new adapter file and changing one line of wiring —
never touching call sites.

**INVARIANT 4 — CLOUD-READY, CLOUD-FREE.** v1 ships with no server. It must
nonetheless be shaped so a backend can be added later without restructuring.
Concretely, from day one:

- All persistence goes through a repository protocol, never direct database
  calls from features. A remote-backed implementation must be droppable in.
- All document mutations are modeled as discrete, serializable, ordered
  operations — not in-place mutation of a blob. This is what later makes
  real-time sync and multi-user collaboration possible instead of a rewrite.
- Every model object carries a stable UUID and a `lastModified` timestamp
  from the beginning. Retrofitting identity onto existing user data is
  miserable.
- Assume conflicts will eventually happen. Choose data structures now whose
  merge semantics you could defend later; note where you are deferring a
  real CRDT.
- No feature may assume the network is unavailable, and none may assume it
  is available. Offline is the default; online is an enhancement.
- Auth does not exist in v1, but nothing may be written that assumes a
  single implicit local user forever. Thread a user/owner identifier through
  the model even when it is always the same value.

**INVARIANT 5 — MAXIMUM PLATFORM REACH.** Assume this eventually runs on
iPadOS, iOS, macOS, Android, Windows, and possibly the web. Nothing in
Layer 1 may assume touch input, a specific screen size, a pointer type, a
file system layout, a locale, or a pixel density. Input is abstracted: an
Apple Pencil, a Samsung S Pen, a Surface Pen, a mouse, and a finger are all
sources of the same normalized stroke events, with optional pressure and
tilt. Where a platform capability genuinely does not exist elsewhere,
isolate it behind a capability flag rather than branching logic through the
codebase.

## The pre-delivery checklist

Before handing over any code, run this and state the result. If an item
fails, fix it before delivering rather than noting it as future work. If an
item is genuinely not applicable, say so explicitly rather than skipping it
silently.

- [ ] Layer purity: does anything in Layer 1 import a non-Foundation
      framework? (`./Tools/check-layer-purity.sh`)
- [ ] Linux: would Layer 1 still compile and pass tests on Linux?
- [ ] Format: is any Apple-proprietary type acting as a source of truth?
- [ ] Protocols: is any external dependency called directly instead of
      through an abstraction?
- [ ] Cloud seam: does persistence go through the repository protocol? Are
      mutations discrete and serializable? Do new model types carry
      UUID + lastModified + owner?
- [ ] Platform: does this assume touch, Pencil, screen size, or Apple-only
      behavior anywhere it shouldn't?
- [ ] Tests: are there Layer 1 tests for the logic just written?
- [ ] Tweakability: are tuning values (stall threshold, hint cooldown, image
      resolution, confidence floor, debounce timing) in a single named
      configuration object rather than scattered as literals?
- [ ] Scope: is this the smallest change that achieves the milestone?

Keep it terse — a compact pass/fail list, not paragraphs.

## Built to be changed

Assume every decision will be revisited and every feature will be tweaked
repeatedly. Therefore:

- No magic numbers. Anything Andrew might want to tune lives in a named
  config struct (`TutorConfig`) with a documented default and a comment on
  what changing it does.
- Feature-flag anything experimental so it can be switched off without a
  revert.
- Prefer composition over inheritance; prefer explicit wiring over hidden
  global state. He needs to be able to read the code in three months.
- Comment the WHY, never the WHAT. "Debounced 400ms because PencilKit emits
  partial strokes mid-gesture" is worth writing. "// increment counter" is
  not.
- When you make a non-obvious architectural choice, add a short decision
  note to `docs/decisions/log.md` with the date, the options, and the
  reason.
- Keep files small and single-purpose. If a file passes ~400 lines, propose
  a split.

## How to work with Andrew

- Be direct and opinionated. Pick an approach and defend it. Do not present
  a menu of four options when one is clearly better.
- Tell him when he is wrong, including about things in this file. Agreeable
  answers waste his time.
- Work in milestones that each end with something runnable on a physical
  iPad, and tell him exactly what he should see when it works.
- Never invent an API. If you are unsure whether a PencilKit or CloudKit
  method exists or behaves as you expect, say so and check rather than
  producing plausible code that does not compile.
- Before adding any third-party dependency, ask. Justify it against writing
  it ourselves, and state what happens if it is abandoned.
- When he asks for a change that violates an invariant, push back once with
  the reason. If he confirms, do it and log the exception in
  `docs/decisions/log.md`.
- Ink feel outranks every other consideration. If a change risks stroke
  latency, say so before writing it.
- On tutoring behavior specifically: this app never hands a student a final
  answer. The four-level hint ladder is a hard product constraint, not a
  default setting. Treat any request to weaken it as a significant product
  decision rather than a config change.

## Already decided — do not relitigate unless asked

- Native Swift for v1. Not Flutter, not React Native.
- No Rust or Kotlin Multiplatform shared core before v1 ships. Portability
  is achieved through Invariant 1, and the port mechanism is chosen later
  with a shipped app in hand.
- Bring-your-own API key, direct to provider. No backend in v1.
- iPad first. iPhone and Mac second. Android third. Windows fourth.
- v1 scope is the shippable MVP in the founding brief. New feature ideas go
  to the roadmap, not into v1.
- The git remote is SSH, deliberately (see `docs/status/current.md` for why
  — HTTPS personal access tokens are refused for workflow-file pushes). Do
  not switch back to HTTPS.

## Working setup

One command from the repo root: `./Tools/setup-mac.sh`. It checks the
toolchain, runs the layer-purity guard, builds and tests both Swift
packages, and regenerates the Xcode project via XcodeGen. Re-run it any time,
and especially after adding a new source file. Do not test PencilKit input
in the Simulator — the canvas is `.pencilOnly`, so a mouse scrolls rather
than draws, and it will look broken while actually working correctly.

Read `docs/status/current.md` for exactly what's been verified on device
versus what's only been built and reasoned about — those are not the same
claim, and the file is explicit about which is which for every milestone.
