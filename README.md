# circuitry-zig

A Zig 0.16-native mirror of Circuitry 0.6 for Zinc.

Circuitry 0.6 files are reusable shapes of action:

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

This package is not a runtime, compiler, graph engine, or tool registry. It helps Zinc read, confirm, edit, compose, and browse `.circuitry.yaml` artifacts directly.

## Zig version

This repo targets Zig 0.16.0.

The build file uses the 0.16 style shown in the official docs: `std.Build`, `b.createModule`, `.root_module`, and `exe.run()`. The CLI and file/directory reads are written around the 0.16 IO model: `main(init: std.process.Init)`, `init.io`, `std.Io.Dir.cwd().readFileAlloc(io, ...)`, `std.Io.Dir.cwd().openDir(io, ...)`, `dir.close(io)`, and iterator `next(io)`.

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

Only these are native:

```text
circuitry
name
about
takes
does
gives
```

All other fields are preserved by YAML implementations and ignored by core Circuitry.
