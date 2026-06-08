# circuitry-zig

Zig library and CLI for reading, confirming, and browsing Circuitry files.

```yaml
circuitry: 0.6
name: deep search

takes:
  - question

does: |
  Spend the least action needed to answer with support.

gives:
  - answer
  - citations
```

Circuitry files are reusable shapes of action. This package is not a runtime, compiler, or graph engine. It lets Zinc and other Zig hosts work with `.circuitry.yaml` artifacts directly.

## Commands

```bash
zig build
zig build test
zig build run -- read examples/deep-search.circuitry.yaml
zig build run -- confirm examples/deep-search.circuitry.yaml
zig build run -- asks examples/deep-search.circuitry.yaml
zig build run -- gives examples/deep-search.circuitry.yaml
zig build run -- library examples
```

## Native fields

```text
circuitry
name
about
takes
does
gives
```

All other fields are preserved and ignored by core Circuitry.
