import treenimph/dsl

grammar "arithmetic":
  expression = number | binary_expression | parenthesized_expression
  binary_expression = prec_left(1, [
    left@expression,
    operator@("+" | "-" | "*" | "/"),
    right@expression,
  ])
  parenthesized_expression = balanced("(", ")", expression)
  number = re"[0-9]+"
