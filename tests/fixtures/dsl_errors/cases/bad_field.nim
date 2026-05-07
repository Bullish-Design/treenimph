import treenimph/dsl

grammar "bad_field":
  source = "bad"@identifier
  identifier = re"[a-z]+"
