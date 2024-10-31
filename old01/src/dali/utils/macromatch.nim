import macros
import sequtils
import strutils

# TODO: how do I write tests for functions operating on NimNodes ??? :( https://forum.nim-lang.org/t/5261

type
  MatchKind = enum
    mkConcrete, mkOne, mkAny,
    mkStrVal
  MatchNode = ref object
    case level: MatchKind
    of mkStrVal:
      strVal: string
    of mkConcrete:
      kind: NimNodeKind
      kids: seq[MatchNode]
    else:
      discard

proc `$`(m: MatchNode): string =
  case m.level
  of mkStrVal: return "\"" & m.strVal & "\""
  of mkAny:    return "_"
  of mkOne:    return "[]"
  of mkConcrete:
    var kind = $m.kind
    kind.removePrefix "nnk"
    return kind & "(" & m.kids.map(`$`).join(", ") & ")"


proc toMatchable(nTree: NimNode): NimNode =
  case nTree.kind
  of nnkCall:
    if nTree[0].kind != nnkIdent: error "expected identifier", nTree[0]
    let
      kind = ident("nnk" & nTree[0].strVal)
      kids = newTree(nnkBracket)
    for i in 1..<nTree.len:
      kids.add toMatchable(nTree[i])
    return quote do:
      MatchNode(level: mkConcrete, kind: `kind`, kids: @`kids`)
  of nnkBracket:
    return quote do:
      MatchNode(level: mkOne)
  of nnkIdent:
    if nTree.strVal != "_": error "expected _ or [] or Subtree(...)", nTree
    return quote do:
      MatchNode(level: mkAny)
  of nnkStrLit:
    let val = nTree.strVal
    return quote do:
      MatchNode(level: mkStrVal, strVal: `val`)
  else:
    error "expected _ or [] or Subtree(...)", nTree

proc matches(n: NimNode, tree: MatchNode): bool =
  # echo n.treeRepr
  # echo tree
  # # echo tree.repr
  # echo "---"
  if tree.level != mkConcrete:
    raise newException(CatchableError, "whoa?")
  if n.kind != tree.kind:
    return false
  if tree.kids.len == 1:
    case tree.kids[0].level
    of mkStrVal:
      return tree.kids[0].strVal == n.strVal
    else:
      discard
  if n.len < tree.kids.len and
    tree.kids[^1].level != mkAny:
    return false
  for i, nn in n:
    if i >= tree.kids.len:
      return false
    case tree.kids[i].level
    of mkAny:
      return true
    of mkOne:
      continue
    of mkConcrete:
      if not nn.matches(tree.kids[i]):
        return false
    else:
      raise newException(CatchableError, "logic error")
  return true

macro `=~`*(n: NimNode, matchTree: untyped): untyped =
  let
    matchable = toMatchable(matchTree)
    matches = bindSym"matches"
  quote do:
    `matches`(`n`, `matchable`)

template `!~`*(n: NimNode, matchTree: untyped): untyped =
  not(n =~ matchTree)
