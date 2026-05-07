import unittest

import treenimph/[helpers, model]

suite "helpers":
  test "delimitedList no trailing":
    let e = delimitedList(Ref("item"), Text(","))
    check e.kind == ekSequence
    check e.items.len == 2

  test "delimitedList trailing":
    let e = delimitedList(Ref("item"), Text(","), trailing = true)
    check e.kind == ekSequence
    check e.items.len == 3

  test "optionalDelimitedList":
    let e = optionalDelimitedList(Ref("item"), Text(","))
    check e.kind == ekOptional

  test "balanced":
    let e = balanced("(", ")", Ref("expr"))
    check e.kind == ekSequence

  test "keyword":
    let e = keyword("if")
    check e.kind == ekText
    check e.textValue == "if"
