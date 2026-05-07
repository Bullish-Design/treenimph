import treenimph

let grammar = mkGrammar(
  "arithmetic",
  rules = [
    mkRule("expression", Choice(Ref("number"), Ref("binary_expression"), Ref("parenthesized_expression"))),
    mkRule("binary_expression", PrecLeft(1, Sequence(
      Field("left", Ref("expression")),
      Field("operator", Choice(Text("+"), Text("-"), Text("*"), Text("/"))),
      Field("right", Ref("expression")),
    ))),
    mkRule("parenthesized_expression", balanced("(", ")", Ref("expression"))),
    mkRule("number", Regex("[0-9]+")),
  ],
)

run(grammar)
