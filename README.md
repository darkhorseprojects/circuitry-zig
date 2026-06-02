# circuitry-zig

Native Zig implementation of Circuitry 0.5.

- target Zig: `0.16.0`
- YAML foundation: [`OrlovEvgeny/serde.zig`](https://github.com/OrlovEvgeny/serde.zig)
- public repository: `darkhorseprojects/circuitry-zig`

`circuitry-zig` owns graph-format semantics only: loading, validation, normalization, imports, addresses, reachable input discovery, dependency plans, return projections, schema parsing, query helpers, diagnostics, and inspection.

It does not execute models, tools, shell commands, package scripts, Zinc packages, sessions, permissions, prompts, or runtime URI materialization.

## API sketch

```zig
const circuitry = @import("circuitry");

var graph = try circuitry.loadFile(allocator, io, "graph.circuitry.yaml");
try circuitry.validate(allocator, &graph);

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
