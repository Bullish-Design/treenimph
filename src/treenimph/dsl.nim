import std/[macros, sets, strutils]

import ../treenimph
export treenimph

proc isReservedConfigName(name: string): bool =
  name in ["extras", "word", "conflicts", "supertypes", "inline",
           "externals", "scannerPath", "queryFiles"]

proc flattenInfix(node: NimNode, op: string): seq[NimNode] =
  if node.kind == nnkInfix and node[0].eqIdent(op):
    result = flattenInfix(node[1], op) & flattenInfix(node[2], op)
  else:
    result = @[node]

proc transformExpr(node: NimNode, letBound: HashSet[string]): NimNode =
  case node.kind

  of nnkIdent, nnkSym:
    let name = node.strVal
    if name in letBound:
      return node
    else:
      return newCall(ident("Ref"), newStrLitNode(name))

  of nnkStrLit..nnkTripleStrLit:
    return newCall(ident("Text"), node)

  of nnkCallStrLit:
    if node[0].eqIdent("re"):
      return newCall(ident("Regex"), node[1])
    else:
      return node

  of nnkBracket:
    if node.len == 0:
      error("Empty brackets [] are not allowed — a sequence must have at least one item", node)
    if node.len == 1:
      return transformExpr(node[0], letBound)
    var args = newNimNode(nnkArgList)
    for child in node:
      args.add transformExpr(child, letBound)
    result = newCall(ident("Sequence"))
    for i in 0 ..< args.len:
      result.add args[i]
    return result

  of nnkInfix:
    let op = node[0].strVal

    if op == "|":
      let leaves = flattenInfix(node, "|")
      result = newCall(ident("Choice"))
      for leaf in leaves:
        result.add transformExpr(leaf, letBound)
      return result

    elif op == "@":
      let lhs = node[1]
      if lhs.kind != nnkIdent:
        error("Left side of @ must be a field name (bare identifier), got " & $lhs.kind, lhs)
      let fieldName = lhs.strVal
      let fieldExpr = transformExpr(node[2], letBound)
      return newCall(ident("Field"), newStrLitNode(fieldName), fieldExpr)

    else:
      result = newNimNode(nnkInfix)
      result.add node[0]
      result.add transformExpr(node[1], letBound)
      result.add transformExpr(node[2], letBound)
      return result

  of nnkPrefix:
    let op = node[0].strVal

    if op == "?":
      return newCall(ident("Optional"), transformExpr(node[1], letBound))
    elif op == "*":
      return newCall(ident("ZeroOrMore"), transformExpr(node[1], letBound))
    elif op == "+":
      return newCall(ident("OneOrMore"), transformExpr(node[1], letBound))
    else:
      result = newNimNode(nnkPrefix)
      result.add node[0]
      result.add transformExpr(node[1], letBound)
      return result

  of nnkCall, nnkCommand:
    let funcName = if node[0].kind == nnkIdent: node[0].strVal else: ""

    case funcName
    of "prec":
      if node.len < 3:
        error("prec() requires at least 2 arguments: prec(level, expr)", node)
      let level = node[1]
      let body = transformExpr(node[2], letBound)
      result = newCall(ident("Prec"), level, body)
      for i in 3 ..< node.len:
        result.add node[i]
      return result

    of "prec_left":
      if node.len < 3:
        error("prec_left() requires at least 2 arguments: prec_left(level, expr)", node)
      return newCall(ident("PrecLeft"), node[1], transformExpr(node[2], letBound))

    of "prec_right":
      if node.len < 3:
        error("prec_right() requires at least 2 arguments: prec_right(level, expr)", node)
      return newCall(ident("PrecRight"), node[1], transformExpr(node[2], letBound))

    of "prec_dynamic":
      if node.len < 3:
        error("prec_dynamic() requires at least 2 arguments: prec_dynamic(level, expr)", node)
      return newCall(ident("PrecDynamic"), node[1], transformExpr(node[2], letBound))

    of "token":
      if node.len < 2:
        error("token() requires 1 argument", node)
      return newCall(ident("Token"), transformExpr(node[1], letBound))

    of "immediate_token":
      if node.len < 2:
        error("immediate_token() requires 1 argument", node)
      return newCall(ident("ImmediateToken"), transformExpr(node[1], letBound))

    of "alias":
      if node.len < 3:
        error("alias() requires at least 2 arguments: alias(name, expr)", node)
      let aliasName = node[1]
      let aliasExpr = transformExpr(node[2], letBound)
      result = newCall(ident("Alias"), aliasName, aliasExpr)
      for i in 3 ..< node.len:
        result.add node[i]
      return result

    else:
      result = newNimNode(nnkCall)
      result.add node[0]
      for i in 1 ..< node.len:
        let arg = node[i]
        if arg.kind == nnkExprEqExpr:
          var namedArg = newNimNode(nnkExprEqExpr)
          namedArg.add arg[0]
          namedArg.add transformExpr(arg[1], letBound)
          result.add namedArg
        else:
          result.add transformExpr(arg, letBound)
      return result

  of nnkPar:
    if node.len == 1:
      return transformExpr(node[0], letBound)
    result = newNimNode(nnkPar)
    for child in node:
      result.add transformExpr(child, letBound)
    return result

  of nnkIntLit..nnkFloat128Lit:
    return node

  of nnkNilLit:
    return node

  else:
    return node
