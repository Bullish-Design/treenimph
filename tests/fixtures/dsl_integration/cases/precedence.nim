import treenimph/dsl

grammar "arith":
  expression = number | binary_expression
  binary_expression = prec_left(1, [left@expression, operator@("+" | "-"), right@expression])
  number = re"[0-9]+"
