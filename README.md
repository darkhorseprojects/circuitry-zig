# circuitry-zig

Zig library and CLI for reading, confirming, and browsing Circuitry files.

Circuitry is YAML for action systems. Zinc is the host that runs them.

```yaml
circuitry: "0.6.1"
name: cited research answer

takes:
  $question:
    type: text

uses:
  draft:
    model: fast
    takes:
      question: $question
    does: |
      Draft a clear answer.
    gives:
      answer: $answer

gives:
  $answer:
    type: text
```

This package is not a runtime, compiler, or graph engine. It lets Zinc and other Zig hosts work with `.circuitry.yaml` artifacts directly.

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

Zinc owns:

```text
zinc
@package references
model
```

The parsed YAML root preserves Zinc fields and references. `model` is surfaced on `uses` entries but not interpreted.

## System view

The library exposes `systemView`, which extracts:

- top-level `$takes`
- `uses` entries
- top-level `$gives`
- `$` value references
- `@` package references
- diagnostics for unresolved values, duplicate producers, and cycles
