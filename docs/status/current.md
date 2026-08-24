# Slate — build status

Last updated 2026-08-14.

## Where the code lives

- Repo: `~/Claude Code/slate` on Andrew's MacBook Pro.
- Remote: https://github.com/andrewcrockefeller-bit/slate — **pushed over SSH**,
  not HTTPS. See the auth note below; this matters.
- Archive: iCloud Drive → `slate/v1/slate-v1-m1-2026-08-13.zip` (M1-era; stale,
  predates M2 onward).
- Standing project context now lives in two places that must be kept in sync
  by hand: this claude.ai Project (`brief/`, `decisions/`, `status/`), and
  `CLAUDE.md` + `docs/` in the repo itself, for Claude Code. See the decisions
  log entry "Development moved from Cowork to Claude Code CLI for
  implementation," 2026-08-14.

## Milestones

**M0 — skeleton. Complete.**

**M1 — ink capture. PASSED on device.** Normalized stroke model, PencilKit
adapter with verified round-trip, canvas with pan/zoom, undo/redo/clear, tool
picker, palm rejection. Confirmed on a physical iPad: capture works end to end,
ink feel acceptable against Freeform, palm rejection works, pressure and tilt
detected.

**Linux CI — GREEN.** Runs on every push. `SlateCore` compiles and passes its
tests in a `swift:6.0` container with no Apple frameworks present.

**M2 — persistence. BUILDS; not yet accepted on device.** Document model with
mutations as discrete ordered operations, `DocumentRepository` protocol,
in-memory reference implementation, file-backed adapter (snapshot + JSON Lines
log with compaction), autosave and restore wired into the canvas.

Acceptance test still outstanding: draw, force-quit from the app switcher,
relaunch, and the work should be exactly there. **Do this first in Claude
Code** — everything built since M2 sits on top of unverified persistence.

**M3 — problem model. Domain layer DONE; UI creation gesture NOT built.**
This was done as part of the "Checkpoint 2026-08-13 19:50" commit alongside
finishing M2's file-backed repository, rather than under its own milestone
commit — easy to undersell if you only read commit messages. What actually
exists: `WorkRegion` (kind, state, ordinal), the centre-of-bounds claiming
rule (a stroke belongs to whichever region contains the centre of its path
bounds — chosen over any-overlap or full-containment so spilled ink still
counts, see `docs/decisions.md`), `captureBounds` (grows to cover everything
claimed, then pads, so a model crop never clips the bottom of a fraction),
observed vs. declared region state (`untouched`/`inProgress` follow from
whether there's ink in the region; `complete`/`setAside` are judgements that
survive an erase without silently un-finishing the problem), and a full test
suite (`WorkRegionTests.swift`). `WorkRegionID` — added speculatively at M0 —
was deleted; regions are addressed by `ElementID` like every other canvas
element.

What M3 still needs, and hasn't been started: manual region creation by
lasso or tap in the UI, and a state-chip UI reacting to
`regionsNeedingStateUpdate`. Nothing in the founding brief's M3 acceptance
test ("circle an area, it becomes 'Problem 1', its state chip changes as you
write in it") has been run.

**M4 — provider seam. Layer 1 and Layer 2 code complete; NOT YET WIRED TO THE
UI, NOT YET RUN AGAINST THE REAL API.** This is the founding brief's
"go/no-go for the whole product" milestone. What exists:

  - `HintLevel`, `EvaluationContext`, `StrokeTiming`, `TutorResponse`,
    `TutorResponseValidator` (enforces R5 — the ladder, length limits, the
    confidence floor, and a finality-marker heuristic — and reports every
    violation at once, not just the first).
  - `AIProvider`, `StrokeRasterizing`, `APIKeyStore` — the three Layer 1
    protocols Invariant 3 requires for this milestone.
  - `HTTPTransport` / `HTTPRequest` / `HTTPResponse` — a Layer 1 seam so the
    Anthropic adapter's request-building, response-parsing, and error
    classification are pure Swift and testable on Linux; only the actual
    socket call is Layer 2.
  - `TutorPromptBuilder` — turns an `EvaluationContext` into the actual system
    and user prompt text, deterministically, so it can be asserted on in a
    test.
  - `AnthropicProvider` + `AnthropicWireFormat` — a real adapter against the
    Messages API: builds the request, sends it, extracts a JSON object from
    the reply even if wrapped in a code fence or trailing commentary,
    classifies every HTTP failure mode (401/403 → not authorised, 429 → rate
    limited with retry-after, 5xx/529 → transient, etc.), and enforces R5 on
    the way out — a model that ignores the prompt still cannot exceed the
    permitted rung, skip one, or say "the answer is."
  - Layer 2: `URLSessionTransport` (the real network call, ephemeral session,
    `waitsForConnectivity = false` — a queued request that arrives after the
    student has moved on is worse than a fast failure), `KeychainAPIKeyStore`
    (device-only, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — the key
    never leaves the device via iCloud Keychain), `CoreGraphicsStrokeRasterizer`
    (renders from normalized `InkStroke`, never from `PKDrawing`, per
    Invariant 2; long-edge cap preserves aspect ratio; single-point strokes
    are drawn as dots because a zero-length path strokes to nothing).
  - 35 tests across both packages, including ones that assert on actual pixel
    bytes (an inked render must differ from a blank one) rather than just
    "did not throw."

  **What's missing before M4 can actually be evaluated:** nothing calls
  `AnthropicProvider.evaluate` yet. There is no UI for entering an API key, no
  debug button, no wiring from the canvas to the provider. The founding
  brief's M4 acceptance test — "write something messy, tap debug, watch the
  model read it back correctly" — has not been run. That is the first thing
  to build in Claude Code.

## Working setup

- One command: `./Tools/setup-mac.sh` (or double-click
  `Tools/setup-mac.command`). Purity guard, both test suites, project
  regeneration. `Tools/push-ssh.command` pushes — though with Claude Code
  running natively, `git push` directly from its own shell should work now;
  keep the `.command` files as a fallback for when you want to push by hand.
- `M0-xcode-setup.txt` — the original first-time Xcode project setup and
  signing runbook. Steps 1–5 (creating the project by hand) are superseded by
  `setup-mac.sh` + XcodeGen; step 6 (signing, running on the iPad, trusting
  the cert) still applies verbatim.
- `M1-test-plan.txt` — the three-level M1 test procedure: automated tests,
  an on-device run, and the ink-feel checklist that actually decided the
  milestone (not the automated tests — feel is the acceptance criterion).
  Worth reading once as the template for what a milestone's device test
  should look like; M4's acceptance test (below) hasn't gotten this
  treatment yet and probably should before it's declared done.
- Bundle ID `com.andrewrock.slate`; `DEVELOPMENT_TEAM` pinned in `project.yml`
  because regeneration discards anything Xcode's UI sets.
- Device runs need Developer Mode on the iPad, which only appears after Xcode
  has attempted an install once.
- Do not test in the Simulator — `.pencilOnly` means a mouse scrolls, not draws.

## Two checks, neither one stricter

Learned the hard way at M2: **Linux CI green does not imply the app builds on
macOS.** Apple's XCTest and swift-corelibs-xctest declare the assertion macros
differently, so `XCTAssertEqual(try await …)` — an `await` inside an autoclosure
— compiled on Linux and failed on macOS. CI had been green on that exact code.

Treat the two as complementary: CI proves portability, `setup-mac.sh` proves it
builds. Both are load-bearing.

Related gotcha: `XCTUnwrap` is also an autoclosure. A grep for `XCTAssert.*await`
misses it. Use `XCT[A-Za-z]*(.*await`. The M4 test suite was written against
this pattern from the start.

## Git auth — read before changing anything

The remote is SSH, deliberately. Personal access tokens are refused for any push
that creates or updates a file under `.github/workflows/` unless the token
carries the `workflow` scope — and fine-grained tokens have no such checkbox,
only a "Workflows" repository permission that is easy to miss. Several pushes
failed on this. Do not switch back to HTTPS.

The Cowork device bridge also refused to write workflow files and could not
push over SSH at all (its network egress does not permit outbound connections
to `github.com:22`) — this is part of why implementation moved to Claude Code.
Claude Code running in Terminal uses your Mac's own network and should push
directly with no workaround needed.

## Open risks

1. **Pressure normalization is unconfirmed.** Apple does not document the range
   of `PKStrokePoint.force`. Pressure *is* detected on device, but has not been
   calibrated against a measured hard press. Dial: `maximumForce` in
   `PencilKitInkConverter.Calibration`.
2. **No erase event exists.** `PKCanvasViewDelegate` has five callbacks and none
   reports an erase. Erase, undo, and clear therefore rewrite the whole document
   — 400 operations to erase one stroke on a 200-stroke canvas. Off the writing
   path and folded away by compaction. The fix is stable stroke identity via
   `PKStroke.id`, unverified.
3. **Canvas is finite.** 20,000 × 20,000 points. Recentring deferred.
4. **Document title is not an operation.** Rename writes the snapshot directly.
   Fine for one device; becomes a rename operation when sync arrives.
5. **M4 is code-complete but unproven.** The whole seam — prompt, adapter,
   validator, rasterizer — has never been run against the real Anthropic API
   or a real API key. Cost per hint (brief section 9, Q1) and whether the
   model reads *this app's* raster settings reliably (the actual go/no-go
   question) are both still open.

## Next

Immediate: run `./Tools/setup-mac.sh` in Claude Code and confirm both test
suites pass natively (they were only checked for layer purity and reasoned
about, never compiled, while built through the Cowork bridge). Then the M2
device acceptance test, still outstanding since 2026-08-13: draw, force-quit,
relaunch, confirm the work is exactly there.

Then: wire `AnthropicProvider` to a debug button and a Keychain key-entry
screen so the actual M4 acceptance test can run on a physical iPad — this is
the real go/no-go for the product, per the founding brief. Everything after
that (M5's stall-triggered tutor loop) depends on M4 actually working against
a real key.
