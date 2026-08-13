# Slate

An infinite handwriting canvas with an AI tutor that watches you work and places
hints beside your problem — never the answer.

Milestone: **M0 — skeleton.**

## Layout

```
Packages/SlateCore/       Layer 1 — domain core. Foundation only. Builds on Linux.
Packages/SlatePlatform/   Layer 2 — platform adapters. Apple frameworks live here.
App/Slate/                Layer 3 — SwiftUI. Zero business logic.
Tools/                    check-layer-purity.sh
docs/decisions.md         Why things are the way they are.
```

## The rule everything else depends on

`SlateCore` imports Foundation and nothing else, has no package dependencies, and
compiles and passes its tests on Linux. That single property is what makes the
Android and Windows ports a port rather than a rewrite. It is enforced by CI on
every push, and by `Tools/check-layer-purity.sh` before the build so that a
violation is reported as a violation instead of as a compile error.

If you need a platform capability in the domain core, declare a protocol in
`SlateCore` and implement it in `SlatePlatform`. Do not relax the check.

## Running things

```bash
# Layer 1, the part that must stay portable
swift test --package-path Packages/SlateCore

# The invariant guard — run it before you commit
./Tools/check-layer-purity.sh

# Layer 2 (Apple platforms only)
swift test --package-path Packages/SlatePlatform
```

The iPad app is built from Xcode. See `M0-xcode-setup.txt` for first-time setup.

## Where the design lives

The founding brief, the v1.5 addendum, and the prototype origin story are in the
project knowledge base, not in this repo. Section 10 of the founding brief lists
the six model decisions v1 has to make correctly so that v1.5 is not a migration.
