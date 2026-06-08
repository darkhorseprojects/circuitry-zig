const std = @import("std");

pub const value = @import("value.zig");
pub const shape = @import("shape.zig");
pub const library = @import("library.zig");

pub const Shape = shape.Shape;
pub const ActionCard = shape.ActionCard;
pub const Confirmation = shape.Confirmation;

pub const loadText = shape.loadText;
pub const loadFile = shape.loadFile;
pub const card = shape.card;
pub const confirm = shape.confirm;
pub const renderCard = shape.renderCard;

test {
    _ = value;
    _ = shape;
    _ = library;
}
