# circuitry-zig

Zig library and CLI for reading, confirming, and browsing Circuitry files.

Circuitry is YAML for action systems.

```yaml
circuitry: "0.6.2"
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

## System view

The library exposes `systemView`, which extracts:

- top-level `$takes`
- `uses` entries
- top-level `$gives`
- `$` value references
- diagnostics for unresolved values, duplicate producers, and cycles
