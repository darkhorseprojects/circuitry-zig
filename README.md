# circuitry-zig

Native Zig implementation of Circuitry 0.5.

Circuitry is a small YAML format for executable AI graphs. It exists so prompts, model calls, tools, subgraphs, inputs, returns, and value contracts can live in one readable file.

`circuitry-zig` implements the graph semantics needed by native runtimes:

- loading and normalization
- validation for `circuitry: "0.5"`
- imports and module resolution
- exports and runtime input contracts
- `$name` runtime input references
- resources and known resource kinds
- address resolution
- dependency planning
- return projection resolution
- deterministic schema validation
- unknown YAML preservation outside schema
- custom resource payload/query helpers
- diagnostics and inspection

Runtimes provide effects: provider calls, tool implementations, URI materialization, sessions, packages, permissions, memory, policy, and services.

- package version: `0.1.4`
- graph format version: `0.5`
- target Zig: `0.16.0`
- YAML foundation: [`OrlovEvgeny/serde.zig`](https://github.com/OrlovEvgeny/serde.zig)
- public repository: `darkhorseprojects/circuitry-zig`

## Schema

Schema is plain YAML describing YAML values. It is valid only at:

- `exports.*.input`
- `model.schema`
- `run.schema`

Supported schema features match the TypeScript Circuitry implementation:

- scalar names: `string`, `number`, `integer`, `boolean`, `null`, `any`
- plain object maps with required fields and `extra: false` by default
- expanded object form: `object` + `extra`
- `optional`
- `nullable`
- `array` and `list`
- `record` with optional key `pattern`
- `union` and tagged union
- `literal`
- `enum`
- numeric `range`
- `length`
- string `pattern`
- `type` inside schema nodes
- open `annotations`

Unknown schema operators are errors except under `annotations`. Unknown YAML outside schema is preserved.

Pattern support uses `zig-utils/zig-regex` with the portable Circuitry contract: anchors, literals, character classes, ranges, negated classes, `*`, `+`, `?`, `{n}`, `{m,n}`, alternation, groups, `.`, and escaped classes such as `\\d`, `\\w`, and `\\s`.

## API sketch

```zig
const circuitry = @import("circuitry");

var graph = try circuitry.loadFile(allocator, io, "graph.circuitry.yaml");
defer graph.deinit();
try circuitry.validate(allocator, &graph);

const schema = circuitry.query.modelSchema(&graph, "assistant");
const extension = circuitry.query.customResourcePayload(&graph, "example_extension", "extension");

// resolve consumes graph on success. After this call, resolved owns graph deinit.
var resolved = try circuitry.resolve(allocator, io, graph, .{});
defer resolved.deinit();

const main_export = circuitry.getExport(&resolved.graph, "main");
const inputs = try circuitry.requiredInputs(allocator, &resolved, "main");
const plan = try circuitry.planExport(allocator, &resolved, "main");
const returns = try circuitry.returnProjections(allocator, &resolved.graph, "main");
```

## CLI

```bash
zig build run -- check graph.circuitry.yaml
zig build run -- inspect graph.circuitry.yaml
zig build run -- resolve graph.circuitry.yaml
```
