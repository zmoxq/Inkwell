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

This is the complete whitelist. There are no per-fixture normalizations.

## Adding a genuine normalization later (extension point)

If a future construct legitimately normalizes (e.g. `- ` vs `* ` list
markers), do **not** widen `canon`. Instead give the fixture a sibling
golden file `<name>.expected.md` and assert against it, and add a section
here arguing why the normalization is not data loss. Keeping normalized
cases as explicit golden files keeps every intentional deviation visible
and reviewed, rather than hidden inside a comparison rule. (Not yet
needed — YAGNI; documented so the mechanism is obvious when it is.)

## Known defects currently caught by the net

See the incident list in `PHASE_3_ARCHITECTURE.md` §12. Fixtures that
reproduce an unfixed defect are marked in `RoundTripTests.swift` with
`XCTExpectFailure` and a reference, so the suite stays green-runnable
while documenting the bug; removing the wrapper is how a fix lands.
