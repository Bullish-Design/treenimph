import treenimph/dsl

grammar "test_lang":
  source = *statement
  statement = let_stmt | expr_stmt
  let_stmt = ["let", name@identifier, "=", value@expression, ";"]
  expr_stmt = [expression, ";"]
  expression = identifier | number
  identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
  number = re"[0-9]+"
