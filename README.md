# circuitry-zig

Native Zig implementation of Circuitry 0.5.

Circuitry is a tiny YAML-native format for executable AI graphs. It describes the wiring of agentic systems: inputs, resources, model calls, tools, subgraphs, schemas, imports, and returns.

`circuitry-zig` implements the runtime-neutral graph semantics for native runtimes:

- loading and normalization
- version validation for `circuitry: "0.5"`
- imports and module resolution
- exports and runtime input contracts
- runtime input references such as `$question`
- resources and known resource kinds
- address resolution
- dependency planning
- return projection resolution
- deterministic schema validation
- unknown YAML preservation outside schema
- custom resource payload/query helpers
- diagnostics and inspection

It does not execute models, tools, shell commands, package scripts, Zinc packages, sessions, permissions, provider config, prompts, services, hooks, routines, or runtime URI materialization. Runtimes own those effects.

- package version: `0.1.3`
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
- `array` and compatibility alias `list`
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

Pattern support is deterministic and intentionally small: anchors, literal text, bracket character classes/ranges, and `*`, `+`, `?` quantifiers for the subset used by portable Circuitry schemas.

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
const inputs = try circuitry.requiredInputs(allocator, &resolved.graph, "main");
const plan = try circuitry.planExport(allocator, &resolved.graph, "main");
const returns = try circuitry.returnProjections(allocator, &resolved.graph, "main");
```

## CLI

```bash
zig build run -- check graph.circuitry.yaml
zig build run -- inspect graph.circuitry.yaml
zig build run -- resolve graph.circuitry.yaml
```
