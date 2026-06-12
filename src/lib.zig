const std = @import("std");

pub const value = @import("value.zig");
pub const version = @import("version.zig");
pub const shape = @import("shape.zig");
pub const library = @import("library.zig");

pub const Shape = shape.Shape;
pub const ActionCard = shape.ActionCard;
pub const Confirmation = shape.Confirmation;
pub const SystemDiagnostic = shape.SystemDiagnostic;
pub const Direction = shape.Direction;
pub const NormalizedValue = shape.NormalizedValue;
pub const NormalizedBinding = shape.NormalizedBinding;
pub const NormalizedPart = shape.NormalizedPart;
pub const NormalizedDoc = shape.NormalizedDoc;
pub const MaterializedBinding = shape.MaterializedBinding;
pub const Materializer = shape.Materializer;

pub const loadText = shape.loadText;
pub const loadFile = shape.loadFile;
pub const card = shape.card;
pub const confirm = shape.confirm;
pub const normalize = shape.normalize;
pub const stableDocId = shape.stableDocId;
pub const partKey = shape.partKey;
pub const valueKey = shape.valueKey;
pub const bindingKey = shape.bindingKey;
pub const materialize = shape.materialize;
pub const renderCard = shape.renderCard;

test {
    _ = value;
    _ = version;
    _ = shape;
    _ = library;
}
