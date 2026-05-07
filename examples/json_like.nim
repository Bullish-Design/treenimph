import treenimph/dsl

grammar "json":
  extras = [re"\\s+"]

  let value = value_node
  let comma = ","

  document = value
  value_node = json_object | array | string_rule | number_rule | true_lit | false_lit | null_lit
  json_object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string_rule, ":", val@value]
  array = ["[", ?delimitedList(value, comma, trailing = true), "]"]
  string_rule = re"[a-zA-Z_]+"
  number_rule = re"-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"
  true_lit = "true"
  false_lit = "false"
  null_lit = "null"
