# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "libclang>=18.1.1",
#     "pycparser>=3.0",
# ]
# ///

import clang.cindex

HEADER = "../rocksdb/include/rocksdb/c.h"


def kind_name(kind: clang.cindex.CursorKind) -> str:
    if kind.is_attribute():
        return "attribute"
    elif kind.is_declaration():
        return "declaration"
    elif kind.is_expression():
        return "expression"
    elif kind.is_invalid():
        return "invalid"
    elif kind.is_preprocessing():
        return "preprocessing"
    elif kind.is_reference():
        return "reference"
    elif kind.is_statement():
        return "statement"
    elif kind.is_translation_unit():
        return "translation_unit"
    elif kind.is_unexposed():
        return "unexposed"
    else:
        return "unknown"


def cursor_name(cursor: clang.cindex.Cursor) -> str:
    if cursor.is_abstract_record():
        return "abstract_record"
    elif cursor.is_anonymous():
        return "anonymous"
    elif cursor.is_bitfield():
        return "bitfield"
    elif cursor.is_const_method():
        return "const_method"
    elif cursor.is_converting_constructor():
        return "converting_constructor"
    elif cursor.is_copy_assignment_operator_method():
        return "copy_assignment_operator_method"
    elif cursor.is_copy_constructor():
        return "copy_constructor"
    elif cursor.is_default_constructor():
        return "default_constructor"
    elif cursor.is_default_method():
        return "default_method"
    elif cursor.is_definition():
        return "definition"
    elif cursor.is_deleted_method():
        return "deleted_method"
    elif cursor.is_move_assignment_operator_method():
        return "move_assignment_operator_method"
    elif cursor.is_move_constructor():
        return "move_constructor"
    elif cursor.is_mutable_field():
        return "mutable_field"
    elif cursor.is_pure_virtual_method():
        return "pure_virtual_method"
    elif cursor.is_scoped_enum():
        return "scoped_enum"
    elif cursor.is_static_method():
        return "static_method"
    elif cursor.is_virtual_method():
        return "virtual_method"
    else:
        return "unknown"


def with_cursor(cursor: clang.cindex.Cursor, depth=0) -> None:
    kind = cursor.kind
    print("  " * depth + kind_name(kind) + " / " + cursor_name(cursor), end="")
    type = cursor.type
    if type.kind != clang.cindex.TypeKind.INVALID:
        print(" " + type.spelling, end="")
    print(" " + cursor.spelling)

    for c in cursor.get_children():
        with_cursor(c, depth + 1)


def main(header: str) -> None:
    idx = clang.cindex.Index.create()
    tu = idx.parse(header)
    with_cursor(tu.cursor)


if __name__ == "__main__":
    main(HEADER)
