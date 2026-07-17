# Round-trip normalization whitelist

The round-trip test net asserts that every fixture survives
`parse → decorate → serialize` **byte-for-byte**. The only tolerated
difference is the single normalization documented below. Anything else is
a defect (底线 1:磁盘产物必须是干净标准 Markdown).

## The one global normalization: trailing newline at EOF

`InkwellEditor.getMarkdown()` emits no trailing newline. A fixture that
ends with `\n` (the normal convention for a text file) therefore differs
from the serializer output by trailing newline characters only.

- **Why it is not corruption**: a trailing newline at end-of-file is not
  document content — it is a text-file convention. No block, inline span,
  or character of the user's writing is affected.
- **How the net applies it**: before comparison, both the fixture and the
  serializer output are canonicalized by stripping trailing `\n`
  characters (`RoundTripTests.canon`). Everything before the final
  newline(s) must match exactly.

This is the one *global* normalization applied to every fixture. Per-fixture
normalizations below are asserted explicitly against golden files.

## Per-fixture normalization: emphasis marker `_` → `*`

The serializer emits all emphasis with asterisks: real `_emphasis_` becomes
`*emphasis*`, and `__bold__` becomes `**bold**`.

- **Why it is not corruption**: `*emphasis*` and `_emphasis_` are both valid
  CommonMark emphasis and render identically; only the delimiter style
  changes, like `-` vs `*` list markers. No word, character, or structure of
  the document is altered.
- **Scope**: this is *inter-word* emphasis only. *Intra-word* underscores
  (`PHASE_3_ARCHITECTURE`, `foo_bar_baz`) are not emphasis at all and stay
  literal — a correctness requirement, guarded byte-exact by
  `testEmphasisUnderscore`, not a normalization.
- **How the net asserts it**: fixture `emphasis-marker.md` is asserted
  against golden `emphasis-marker.expected.md` (`testEmphasisMarkerNormalization`).
  The normalization is pinned, never left unasserted.

## Adding a genuine normalization later (mechanism)

Give the fixture a sibling golden file `<name>.expected.md`, assert with
`assertRoundTrip(_, produces:)`, and add a section here arguing why the
normalization is not data loss. Keeping normalized cases as explicit golden
files keeps every intentional deviation visible and reviewed, rather than
hidden inside a comparison rule.

## Known defects currently caught by the net

See the incident list in `PHASE_3_ARCHITECTURE.md` §12. Fixtures that
reproduce an unfixed defect are marked in `RoundTripTests.swift` with
`XCTExpectFailure` and a reference, so the suite stays green-runnable
while documenting the bug; removing the wrapper is how a fix lands.
