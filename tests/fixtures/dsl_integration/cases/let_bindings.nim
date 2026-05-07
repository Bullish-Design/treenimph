import treenimph/dsl

grammar "json":
  extras = [re"\\s+"]

  let value = val_node
  let comma = ","

  document = value
  val_node = obj_rule | string_rule | number_rule
  obj_rule = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string_rule, ":", val@value]
  string_rule = re"[a-zA-Z_]+"
  number_rule = re"[0-9]+"
