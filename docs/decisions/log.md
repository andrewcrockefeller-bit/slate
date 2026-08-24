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

## 2026-08-14 — `AnthropicProvider` lives in Layer 1, not Layer 2

**Options.** (a) The whole Anthropic adapter, including request/response
handling, in Layer 2 alongside the actual socket work. (b) Split: an
`HTTPTransport` protocol declared in Layer 1, a `URLSessionTransport`
implementation in Layer 2, and the Anthropic-specific request building,
response parsing, JSON wire format, and error classification in Layer 1 against
that protocol.

**Chose (b).** Building a Messages API request body, parsing the reply, pulling
a JSON object out of text that may be wrapped in a code fence, and classifying
an HTTP status into a retry decision are all pure data transformations with no
Apple dependency — and they are where the actual bugs live. Only the socket
call itself needs `URLSession`. Keeping the adapter logic in Layer 1 means the
whole request/response cycle, including the ladder-enforcement step (R5), is
testable on Linux with a stub transport and no network, no key, and no cost.
`HTTPRequest`/`HTTPResponse` are plain Foundation value types, not `URLRequest`,
specifically so they don't require `FoundationNetworking` on Linux.

**Cost.** One more protocol and two more small types (`HTTPRequest`,
`HTTPResponse`) than putting everything in Layer 2 would have needed. Worth it —
this is the file most likely to need debugging against a real API response
shape, and Linux-testable beats device-testable for that.

---

## 2026-08-14 — The wire format lives in its own file, separate from the adapter

**Options.** (a) Keep `AnthropicWireRequest`/`AnthropicWireResponse` and friends
inside `AnthropicProvider.swift`. (b) Split them into `AnthropicWireFormat.swift`.

**Chose (b).** `AnthropicProvider.swift` was approaching 400 lines with both in
one file. The wire types are a contract with something outside the process —
Anthropic's actual JSON shape — and are expected to change independently of the
adapter's logic (retry policy, validation, prompt building). Separating them
means a wire-format change is a diff in one small file instead of noise inside
the code that classifies errors and enforces the ladder.

---

## 2026-08-14 — Confidence is clamped, not rejected, when a model returns an
out-of-range value

**Options.** (a) Reject a response whose `confidence` is outside 0...1.
(b) Clamp it into range and continue.

**Chose (b).** A model reporting 1.2 is being enthusiastic about a real
finding, not returning malformed data — the field means the same thing at 1.2
as at 1.0, it's just poorly calibrated at the top end. Rejecting it means
throwing away an otherwise-valid hint over a formatting quirk. The
`confidenceFloor` check that matters (R5, silence beats a wrong hint) only
cares about the bottom of the range, which clamping does not touch.

---

## 2026-08-14 — Development moved from Cowork to Claude Code CLI for
implementation

**Options.** (a) Keep driving implementation through Cowork's remote-device
bridge to Andrew's Mac. (b) Move implementation to Claude Code running natively
in Andrew's Terminal; keep this claude.ai Project for planning and the
founding-brief/decisions-log/status documents.

**Chose (b).** By M4 the bridge's overhead was concrete, not theoretical: every
file write required a sandbox → `SendUserFile` → `device_commit_files` relay
instead of a direct write; there was no Swift toolchain in the Cowork sandbox
to run `swift test` against, so verification depended on Andrew running it and
reporting back; git operations through the bridge left stale `.lock` files that
`device_bash` cannot `rm` (only `mv`), requiring a manual workaround on two
separate commits; and the SSH push to GitHub failed outright because the
bridge's network egress does not permit an outbound connection to
`github.com:22` — pushing required a `.command` file double-clicked on the Mac
directly. None of that is a property of the code; all of it is a property of
working through a remote bridge instead of as a native process on Andrew's own
machine. Claude Code, run from Andrew's Terminal, has his real toolchain, his
real git, and his real network, and eliminates the relay step for every file.

**What does not change.** Xcode's Signing & Capabilities panel, picking the
iPad in the destination menu, trusting the dev certificate, and watching the
app run on device are GUI/hardware steps neither Cowork nor Claude Code
performs on Andrew's behalf.

**Mechanism.** The project instructions (the five invariants, the
pre-delivery checklist, "how to work with me," the already-decided list) were
copied into `CLAUDE.md` at the repo root, and the founding brief, the v1.5
addendum, the origin-context document, this decisions log, and the status
document were copied into `docs/` in the repo, so Claude Code has the same
standing context this claude.ai Project has, without depending on the Project
being open. The claude.ai Project remains the place for planning conversations
and stays in sync by hand — `docs/` and this Project's files should not be
allowed to drift apart silently. Whoever next changes an invariant, adds a
decision, or updates status should update both, or at minimum note here that
they diverged.
