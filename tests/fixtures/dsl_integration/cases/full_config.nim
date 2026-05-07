import treenimph/dsl

grammar "full_config":
  extras = [re"\\s+"]
  word = identifier
  supertypes = [expression_node]
  inline = [helper_rule]
  conflicts = [[expression_node, binary_expression]]

  source = *expression_node
  expression_node = identifier | binary_expression
  binary_expression = prec_left(1, [expression_node, "+", expression_node])
  identifier = re"[a-zA-Z_]+"
  helper_rule = re"\\s+"
