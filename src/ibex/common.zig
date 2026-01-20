const std = @import("std");

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const bytes = @import("./bytes.zig");
const ByteReader = bytes.ByteReader;
const IbexInt = @import("./IbexInt.zig");
const mantissa = @import("./IbexNumber/mantissa.zig");

fn makeSkipper(comptime check: fn (tag: IbexTag) bool) type {
    return struct {
        fn skipNumPos(r: *ByteReader) IbexError!void {
            try IbexInt.skip(r);
            try mantissa.skipMantissa(r);
        }

        fn skipNumNeg(r: *ByteReader) IbexError!void {
            r.negate();
            defer r.negate();
            return -try skipNumPos(r);
        }

        fn skipPastEnd(r: *ByteReader) IbexError!void {
            while (true) {
                const nb = try r.peek();
                const tag: IbexTag = @enumFromInt(nb);
                if (tag == .End) break;
                try skip(r);
            }

            try r.next(); // swallow .End
        }

        fn skipPastZero(r: *ByteReader) IbexError!void {
            if (std.mem.findScalar(u8, r.tail(), 0x00)) |pos|
                return r.skip(pos + 1);

            return IbexError.InvalidData;
        }

        fn skipOryxString(r: *ByteReader) IbexError!void {
            const len = try IbexInt.read(r);
            try r.skip(len);
        }

        fn skipOryxArray(r: *ByteReader) IbexError!void {
            const len = try IbexInt.read(r);
            for (0..len) |_|
                try skip(r);
        }

        fn skipOryxObject(r: *ByteReader) IbexError!void {
            try IbexInt.skip(r); // class or parent
            try skipOryxArray(r);
        }

        pub fn impl(r: *ByteReader) IbexError!void {
            const nb = try r.next();
            const tag: IbexTag = @enumFromInt(nb);
            if (!check(tag))
                return IbexError.InvalidData;
            return switch (tag) {
                .End => IbexError.InvalidData, // may not occur on its own
                .Null => {},
                .False => {},
                .True => {},
                .String => skipPastZero(r),
                .NumNegNaN => {},
                .NumNegInf => {},
                .NumNegZero => {},
                .NumPosZero => {},
                .NumPosInf => {},
                .NumPosNaN => {},
                .NumPos => skipNumPos(r),
                .NumNeg => skipNumNeg(r),
                .Array => skipPastEnd(r),
                .Object => skipPastEnd(r),
                .Multi => skipPastEnd(r),
                .OryxInt => IbexInt.skip(r),
                .OryxString => skipOryxString(r),
                .OryxClass => skipOryxObject(r),
                .OryxArray => skipOryxArray(r),
                .OryxObject => skipOryxObject(r),
                else => IbexError.InvalidData,
            };
        }
    };
}

pub const skip = makeSkipper(IbexTag.valid).impl;
pub const checkIndex = makeSkipper(IbexTag.indexSafe).impl;
pub const checkOryx = makeSkipper(IbexTag.oryxSafe).impl;
