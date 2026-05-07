import treenimph/dsl

grammar "bad_prec":
  source = prec_left(1)
