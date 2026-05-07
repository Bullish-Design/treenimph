import treenimph

let grammar = mkGrammar(
  "simple_lang",
  rules = [
    mkRule("source_file", ZeroOrMore(Ref("statement"))),
    mkRule("statement", Choice(Ref("let_stmt"), Ref("expr_stmt"))),
    mkRule("let_stmt", Sequence(Text("let"), Field("name", Ref("identifier")), Text("="), Field("value", Ref("expression")), Text(";"))),
    mkRule("expr_stmt", Sequence(Ref("expression"), Text(";"))),
    mkRule("expression", Choice(Ref("identifier"), Ref("number"))),
    mkRule("identifier", Regex("[a-zA-Z_][a-zA-Z0-9_]*")),
    mkRule("number", Regex("[0-9]+")),
  ],
)

run(grammar)
