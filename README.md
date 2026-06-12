# circuitry-zig

Zig library and CLI for reading, confirming, normalizing, and browsing Circuitry files.

Circuitry is YAML for action systems.

```yaml
circuitry: "0.6.4"
name: cited answer

takes:
  $question: text
  $notes: text

uses:
  draft:
    takes:
      question: $question
      notes: $notes
    does: |
      Draft a clear answer from the notes.
    gives:
      answer: $answer

gives:
  $answer: text
```

## Commands

```bash
zig build
zig build test
zig build run -- read examples/deep-search.circuitry.yaml
zig build run -- confirm examples/deep-search.circuitry.yaml
zig build run -- asks examples/deep-search.circuitry.yaml
zig build run -- uses examples/deep-search.circuitry.yaml
zig build run -- gives examples/deep-search.circuitry.yaml
zig build run -- library examples
```

## Native fields

```text
circuitry
name
about
takes
uses
does
gives
```

Circuitry also owns `$value` references.

## Normalized facts

The library exposes `normalize`, which returns stable document facts:

- top-level `takes` values
- top-level `gives` values
- `parts` from `uses` entries
- local part bindings
- diagnostics for unresolved values, duplicate producers, and cycles

`materialize` walks those normalized facts with caller-provided callbacks, so tools can write the facts into their own substrate.

Universal value labels are `bytes`, `text`, `number`, `boolean`, `list`, and `map`. Other labels are valid and preserved.
