import ./model

proc delimitedList*(item: Expr, sep: Expr, trailing = false): Expr =
  if trailing:
    Sequence(item, ZeroOrMore(Sequence(sep, item)), Optional(sep))
  else:
    Sequence(item, ZeroOrMore(Sequence(sep, item)))

proc optionalDelimitedList*(item: Expr, sep: Expr, trailing = false): Expr =
  Optional(delimitedList(item, sep, trailing))

proc balanced*(open, close: string, content: Expr): Expr =
  Sequence(Text(open), content, Text(close))

proc keyword*(word: string): Expr =
  Text(word)
