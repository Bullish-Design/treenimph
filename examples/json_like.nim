import treenimph

let
  value = Ref("_value")
  comma = Text(",")

let grammar = mkGrammar(
  "json",
  extras = [Regex("\\s+")],
  rules = [
    mkRule("document", value),
    mkRule("_value", Choice(Ref("object"), Ref("array"), Ref("string"), Ref("number"), Ref("true"), Ref("false"), Ref("null"))),
    mkRule("object", Sequence(Text("{"), Optional(delimitedList(Ref("pair"), comma, trailing = true)), Text("}"))),
    mkRule("pair", Sequence(Field("key", Ref("string")), Text(":"), Field("value", value))),
    mkRule("array", Sequence(Text("["), Optional(delimitedList(value, comma, trailing = true)), Text("]"))),
    mkRule("string", Regex("\"[^\"]*\"")),
    mkRule("number", Regex("-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
    mkRule("true", Text("true")),
    mkRule("false", Text("false")),
    mkRule("null", Text("null")),
  ],
)

grammar.validateOrRaise()
echo grammar.summary()
echo grammar.renderGrammarJs()
