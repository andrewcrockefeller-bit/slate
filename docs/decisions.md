# Decisions log

Non-obvious architectural choices, with the date, the options considered, and
the reason. Append; do not rewrite history. If a decision is later reversed, add
a new entry that says so rather than editing the old one.

---

## 2026-08-13 — Three Swift packages, not one package plus Xcode targets

**Options.** (a) One package with three targets. (b) Layer 1 as a package, Layers
2 and 3 as Xcode targets. (c) Layer 1 and Layer 2 as separate local packages, the
app as a thin Xcode target depending on both.

**Chose (c).** Package boundaries are enforced by the compiler; target boundaries
inside one Xcode project are enforced by discipline. Making `SlateCore` a package
with literally zero dependencies means a stray `import PencilKit` is a build
error, not a review comment. Splitting `SlatePlatform` out as well means Layer 3
cannot accidentally become the place adapters live, which is the usual way a
clean three-layer design turns into two layers.

**Cost.** Slightly more ceremony creating a file, and a local package graph to
keep resolved. Worth it.

---

## 2026-08-13 — The domain protocol is `TimeSource`, not `Clock`

**Options.** (a) Call it `Clock`. (b) Call it `TimeSource`. (c) Use the standard
library's `Clock` / `InstantProtocol` directly.

**Chose (b).** (a) shadows the standard library's `Clock` protocol in a module
that will be imported alongside Foundation everywhere, which produces genuinely
confusing diagnostics. (c) is the more idiomatic modern answer and was rejected
because `Date` is what gets persisted in `lastModified` and what a future sync
layer will compare, so the domain's notion of time has to be `Date`-shaped
anyway; adapting `ContinuousClock` instants to `Date` at every boundary buys
nothing here.

**Why it exists at all.** The entire tutor loop is defined in elapsed time —
stall thresholds, cooldowns, quiet periods, dwell. Testing that against the real
clock means sleeping in tests or accepting flakes.

---

## 2026-08-13 — `elapsed(since:)` clamps at zero

**Options.** (a) Return the raw, possibly negative interval. (b) Clamp at zero.
(c) Return an optional and make callers handle it.

**Chose (b).** A timestamp in the future means the clock moved backwards: a
manual adjustment, a timezone change, or eventually a document synced from
another device. Every caller in the tutor loop treats negative elapsed time as
nonsense, so (a) pushes the same `max(0, …)` into a dozen call sites and (c)
adds handling nobody will do meaningfully. Clamping fails closed — a clock change
delays a hint. Failing open would fire every trigger simultaneously.

---

## 2026-08-13 — Distinct identifier types instead of raw `UUID`

**Options.** (a) `UUID` everywhere. (b) A generic `TypedID<Tag>` with phantom
types. (c) Distinct concrete structs behind a `UniqueIdentifier` protocol.

**Chose (c).** (a) makes it possible to pass a document's identifier where an
element's is expected, and that bug is invisible until it corrupts data. (b) is
tidier but the generic parameter interacts awkwardly with `Sendable` and
`Codable` conformance, and the saving is three lines per type.

**Deferred.** Identifiers currently encode as `{"rawValue": "<uuid>"}` via
synthesized `Codable`. A bare-string representation would be nicer on the wire.
Changing it is free until M2 defines the persistence format and impossible to do
casually afterwards — decide it there.

---

## 2026-08-13 — `owner` is threaded through from M0, with a fixed value

**Options.** (a) Add ownership when accounts arrive. (b) Carry an `OwnerID` on
every object now, always `OwnerID.localDefault`.

**Chose (b).** Invariant 4. Adding a required field to a model whose instances
are already sitting in files on real devices is a migration; adding it now costs
one property. `localDefault` is a fixed UUID rather than a per-install random one
so that data created across launches on one device shares an owner, which is the
only thing that makes the value useful before accounts exist.

---

## 2026-08-13 — `Provenance` bundles `lastModified` and `owner`

**Options.** (a) Two independent properties on every entity. (b) One value type
holding both.

**Chose (b).** "Touch this object" becomes a single assignment that cannot
half-happen. Updating the timestamp while forgetting the owner is exactly the
class of bug that stays invisible until sync exists and then corrupts merges.

---

## 2026-08-13 — `TutorConfig` validates rather than clamps

**Options.** (a) Clamp out-of-range values silently. (b) Report issues and let
the caller decide. (c) Make the initializer throwing.

**Chose (b).** The tuning screen is developer-facing and takes free-form numbers.
Silently correcting a value someone deliberately typed produces tuning sessions
whose results cannot be reproduced. (c) makes constructing a config in tests
noisy for no benefit. `validationIssues()` reports every problem at once rather
than the first, because fixing configuration one error per build is miserable.

**Included a relational check.** `dwellThreshold` must exceed `stallThreshold`, or
the stall trigger preempts dwell entirely and dwell looks like a setting that
does nothing rather than one that is wrong.

---

## 2026-08-13 — Layer purity is enforced by a script, not by review

**Options.** (a) Trust review. (b) Rely on the Linux CI build failing. (c) A
dedicated check that runs before the build.

**Chose (c), keeping (b).** (b) alone does catch violations, but it reports them
as a compile error ninety seconds in, and it cannot catch a type that happens to
exist on both platforms. The script also catches `CGFloat` and friends, which are
available on Apple platforms without an explicit import because Foundation
re-exports CoreFoundation there — the single most likely accidental Layer 1
violation, and the one that compiles fine on a Mac.

**Verified.** The check was run against a planted violation
(`import PencilKit`, `CGPoint`, `UIView`) and failed with three specific,
line-numbered errors, then passed again once removed. A guard that has never been
seen to fail is not a guard.

---

## 2026-08-13 — CI runs Linux only, in the official Swift container

**Options.** (a) Linux plus a macOS job building the app. (b) Linux only.
(c) A third-party Swift setup action instead of a container.

**Chose (b) with the container.** A green macOS build proves nothing about
portability — every Apple framework is sitting right there. The Linux job is the
invariant. A macOS job is worth adding once Layer 2 has enough in it to be worth
compiling in CI, which it does not at M0. (c) was rejected as a third-party
dependency in the build pipeline for something a container tag does natively.

---

## 2026-08-13 — Swift 6 language mode, no per-target escape hatch yet

**Options.** (a) Swift 5 language mode throughout. (b) Swift 6 mode throughout.
(c) Swift 6 for Layer 1, Swift 5 for Layer 2.

**Chose (b) for now.** Layer 1 is pure value types and satisfies strict
concurrency trivially. Layer 2 currently contains one adapter and has no
concurrency surface. (c) is the likely end state — UIKit and PencilKit delegate
conformances under strict concurrency are a known source of churn and Layer 2 is
thin adapters where the safety payoff is lowest — but adopting it now would be
solving a problem we do not yet have. Revisit at M1, when ink capture lands.

---

## 2026-08-13 — XcodeGen generates the project; the .xcodeproj is not committed

**Options.** (a) Create the Xcode project by hand once and commit it.
(b) Hand-write `project.pbxproj`. (c) Generate it from a spec with XcodeGen.

**Chose (c).** This reverses the M0 decision made a few hours earlier, and the
reason is worth recording: (a) makes project configuration an undocumented
manual artifact that drifts, merges badly, and can only be inspected by opening
Xcode. (b) is not something that can be produced reliably without Xcode, which
is what ruled it out in the first place. (c) makes "how is this project wired"
a question with a readable, diffable, forty-line answer.

**The dependency question, since this is the project's first third-party tool.**
XcodeGen is a build-time generator. Nothing in the app links against it, no
shipped code imports it, and it does not appear in the dependency graph of
either package. If it is abandoned: run `xcodegen generate` one final time,
commit the resulting `Slate.xcodeproj`, delete `project.yml`, and continue with
option (a). The exit cost is one command and a commit, which is the cheapest
abandonment story a dependency can have.

**Consequence.** `*.xcodeproj` is gitignored. A fresh clone requires
`xcodegen generate` before Xcode will open anything, which is documented in the
README and the runbook.

---

## 2026-08-13 — `Entity` does not refine `Identifiable`; SlateCore declares platforms

**Context.** The first real compile of Layer 1 failed on `Entity.swift` with two
diagnostics, both of them consequences of choices made earlier the same day:

    redeclaration of associated type 'ID' from protocol 'Identifiable'
    is better expressed as a 'where' clause on the protocol

    'Identifiable' is only available in macOS 10.15 or newer

**Options for the first.** (a) `protocol Entity: Identifiable, Sendable where
ID: UniqueIdentifier`. (b) Drop the `Identifiable` refinement and declare the
associated type directly.

**Chose (b).** (a) compiles and is the mechanical fix, which is why it is
tempting. But `Identifiable` exists for SwiftUI — it is how a `List` tells rows
apart — and on Apple platforms it carries an availability annotation. Refining
it drags a UI framework's deployment-target constraint into the domain core in
exchange for nothing the domain uses. Any type conforming to `Entity` already
satisfies `Identifiable`'s single requirement, so Layer 3 writes
`extension Document: Identifiable {}` where it actually needs it, and Layer 1
stays free of the concept.

**Options for the second.** (a) Add `@available` annotations. (b) Declare
`platforms:` in SlateCore's manifest.

**Chose (b), reversing an earlier decision made for bad reasons.** The original
manifest deliberately omitted `platforms:` on the theory that declaring them
would make Layer 1 "look Apple-shaped." That was aesthetics, and it was wrong.
`platforms:` sets minimum deployment targets used only when building for Apple
platforms; SwiftPM ignores it entirely on Linux, so it costs nothing in
portability. Omitting it means SwiftPM assumes macOS 10.13, under which any
standard-library API from the last eight years is an availability error — a trap
that would have fired repeatedly through M1 and whose tempting fix is
`@available` scattered through the domain core.

**Lesson worth keeping.** Both errors were introduced by reasoning about
portability from appearances rather than from what the build system actually
does. The Linux CI job is the check that matters; a manifest that merely looks
platform-neutral proves nothing.

---

## 2026-08-13 — M1: control points, not interpolated points, are the record

**Options.** (a) Store the on-curve points from `interpolatedPoints(in:by:)`.
(b) Store the B-spline control points obtained by iterating `PKStrokePath`.

**Chose (b).** The control points are what PencilKit itself stores, which makes
them the closest available thing to a raw capture; the on-curve points are
derived from them and can be recomputed at any density at any time. Storing a
derivative as the canonical record would mean permanently baking in whatever
stride we happened to choose, and would lose information every save.

**Unverified at the time of writing.** That iterating a `PKStrokePath` yields
`PKStrokePoint` control points is not stated outright in the documentation,
which describes the type's collection conformances only in the abstract. It is
the first thing to check when this compiles.

---

## 2026-08-13 — Stroke transforms are baked into coordinates at capture

**Options.** (a) Carry `PKStroke.transform` alongside the points, applying it at
render time. (b) Apply it once at capture so stored coordinates are final.

**Chose (b).** A stroke whose positions are only correct once some other field
is applied is an implicit coupling, and the first renderer on another platform
that does not know about the extra field draws the document wrong. Widths scale
by the transform's uniform scale, since a width is a scalar and cannot be
transformed as a point.

**Consequence.** `CanvasTransform.uniformScale` takes the square root of the
*absolute* determinant. Without the absolute value a mirroring transform
produces NaN, which propagates into every width in the document silently.
There is a test for exactly this.

---

## 2026-08-13 — Input capabilities are inferred from variance, in Layer 1

**Problem.** Capture frameworks do not report which device produced a stroke.
Pressure and tilt fields arrive populated whether or not the hardware can
measure them, filled with a constant when it cannot.

**Chose** inferring from variance — a value that never changes across a stroke
was not measured — and putting the inference in the domain core rather than in
the PencilKit adapter, so every platform's capture path shares one
implementation and it is testable without a device.

**Known false negative.** A very short stroke, or one drawn with unusually even
pressure, reads as having none. That is the right way to be wrong: treating
absent data as present makes a renderer draw a mouse line with a fake pressure
taper, while treating present data as absent only loses a subtlety.

---

## 2026-08-13 — Ingestion happens on pen-up, and incrementally

**Options.** (a) Convert the whole drawing on `canvasViewDrawingDidChange`.
(b) Convert on `canvasViewDidEndUsingTool`, converting only appended strokes.

**Chose (b).** (a) is O(every point ever drawn) on every change event, and
change events fire repeatedly *during* a stroke — so it does the work many times
over, on the hot path of writing, and produces intermediate records for strokes
that were never finished. Ink feel outranks every other consideration; this is
the first place that rule has teeth.

**The fallback is deliberate.** Anything that is not a pure append — erase, undo,
clear — triggers a full rebuild, because `PKCanvasViewDelegate` reports *that*
the drawing changed and never *how*. There is no erase callback at all. That
absence is also why the v1.5 addendum's erase-burst trigger (T2) is flagged as
needing a spike rather than costed as a given.

---

## 2026-08-13 — Ink type is mapped by equality, not by exhaustive switch

**Context.** `PKInk.InkType` is a type alias for `PKInkingTool.InkType`, whose
membership has grown across releases (monoline, fountain pen, watercolor,
crayon), and whose documentation returned 404 at every URL tried.

**Chose** comparing against the three types that have existed since iOS 14 and
falling back to `.pen`, rather than switching exhaustively. An exhaustive switch
would stop compiling on a future SDK. More importantly, pinning the domain's
vocabulary to Apple's would break Invariant 5 the moment a platform with no
"watercolor" had to open the document. An unrecognised mark renders as a pen
mark, which is the correct failure.

---

## 2026-08-13 — Layer 2 compiles for macOS, via conditional colour types

**Context.** The first build of the PencilKit adapter failed with
`no such module 'UIKit'`. The cause is not obvious and is worth writing down:
`swift test --package-path Packages/SlatePlatform` on a Mac builds the package
**for macOS**, and UIKit does not exist there. There is no way to make
`swift test` target iOS; that requires xcodebuild and a simulator destination.

**What is actually available where.** PencilKit's *model* types — `PKStroke`,
`PKInk`, `PKDrawing`, `PKStrokePath`, `PKStrokePoint` — are macOS 11+. Only
`PKCanvasView` is iOS-only, and that lives in Layer 3. The single genuinely
platform-divided thing in the adapter is colour: `PKInk.color` is `UIColor` on
iOS and `NSColor` on macOS. Apple's documentation lists two `color` properties
for this reason, which read as a documentation quirk until you hit it.

**Options.** (a) Drop SlatePlatform from the test script and test it only
through Xcode against an iOS destination. (b) Conditionally alias the colour
type so the adapter compiles for both.

**Chose (b).** (a) would have cost the fast `swift test` loop for the entire
platform layer, which is where the fiddly conversion logic lives and therefore
where a fast loop is worth the most. (b) costs two `#if canImport` branches and
buys a Layer 2 that already compiles for platform number two on the roadmap.

**One asymmetry worth knowing.** `UIColor.getRed` returns false for colours it
cannot express; `NSColor.getRed` returns nothing and *traps* if the receiver is
not in an RGB colour space. The macOS branch converts with
`usingColorSpace(.sRGB)` first — that call is mandatory, not defensive.

---

## 2026-08-13 — M2: identifiers encode as bare strings

Resolves the deferral recorded at M0.

**Options.** (a) Keep synthesized `Codable`, giving
`{"rawValue": "8B1F…"}`. (b) Encode as a bare `"8B1F…"`.

**Chose (b), and the timing is the point.** M2 is the first milestone that
writes a document to disk. Before it, this is a free choice; after it, it is a
migration against files sitting on a real iPad. A document holds an identifier
for every element and every operation, so the wrapper costs about fifteen bytes
per occurrence for nothing, and a format that gets read during debugging is
worth keeping legible.

**Implementation note.** The encoding helpers live on the `UniqueIdentifier`
protocol, but each concrete type wires up `init(from:)` and `encode(to:)`
itself in two lines. Providing the `Codable` witnesses directly in a protocol
extension competes with the compiler's own synthesis for conforming types,
which is a quiet way to end up with a wire format nobody chose.

---

## 2026-08-13 — Document state is derived from an operation log

**Options.** (a) Store the document as a blob and re-save it on change.
(b) Model every change as a discrete ordered operation and derive state by
replaying them.

**Chose (b).** Invariant 4 requires it, and the reason is worth restating: (a)
gives two devices two whole files where one has to win, while (b) gives two
operation streams that can be merged. It also makes undo a replay to an earlier
point rather than a snapshot stack, and it records what the student did in what
order — which the tutor loop wants anyway.

**Strictness is deliberate.** Operations carry a gapless sequence number and
`apply` throws on a gap rather than skipping. A lost operation replayed loosely
produces a document that looks fine and is quietly missing a stroke from the
middle of a worked problem, with nothing to indicate it. Failing at the gap is
recoverable; carrying on is not.

**Deferred, explicitly.** Sequence numbers are per-document and monotonic,
which is sufficient for one device. Two devices both appending will eventually
claim the same number. That is where a real CRDT goes; `OperationID` exists
separately from `sequence` so that a genuine duplicate can be told from two
different edits landing in the same slot.

---

## 2026-08-13 — `DocumentRepository` is async from the start

**Options.** (a) Synchronous, since the v1 implementation is local files.
(b) `async` throughout.

**Chose (b).** Retrofitting `async` onto a synchronous protocol means touching
every call site — precisely the "restructuring" that a cloud-ready shape is
meant to avoid. An await against a local file costs nothing.

**Errors are translated at the boundary.** `DocumentRepositoryError` speaks in
documents, not in file paths or HTTP status codes. Layer 1 must not know what a
path is, and a feature deciding what to show the user should not be switching
on someone else's error taxonomy.

**`InMemoryDocumentRepository` lives in Layer 1** rather than in tests, because
it depends on nothing outside the domain and doubles as the reference
implementation. If it and the file-backed adapter ever disagree, one of them is
wrong, and this one is easier to read.
