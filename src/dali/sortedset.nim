{.experimental: "codeReordering".}

type SortedSet*[T] = distinct seq[T]

proc newSortedSet*[T](): SortedSet[T] {.inline.} = SortedSet[T](newSeq[T]())
proc newSortedSet*[T](s: var SortedSet[T]): SortedSet[T] {.inline.} = s = SortedSet[T](newSeq[T]())
proc init*[T](s: var SortedSet[T]) {.inline.} = s = SortedSet[T](newSeq[T]())

proc incl*[T](s: var SortedSet[T], item: T) =
  let i = s.search(item)
  if i == s.len:
    seq[T](s).add(item)
  elif s[i] != item:
    seq[T](s).insert(item, i)
  # # HACK: 3 lines, as the following oneliner seems to fail with an error on Nim 19.4:
  # # (HeapQueue[T](s)).push(item)
  # var workaround = seq[T](s)
  # workaround.push(item)
  # s = SortedSet[T](workaround)

proc `[]`*[T](s: SortedSet[T], i: int): T {.inline.} = seq[T](s)[i]

proc len*[T](s: SortedSet[T]): int {.inline.} = seq[T](s).len

proc search*[T](s: SortedSet[T], item: T): int =
  # Based on algorithm.binarySearch, but returns position where element would be inserted if not found
  var i = s.len
  while result < i:
    let mid = (result + i) shr 1
    # echo result, mid, i
    if item < s[mid]:
      i = mid
    elif s[mid] < item:
      result = mid + 1
    else:
      return mid

iterator items*[T](s: SortedSet[T]): T =
  for item in seq[T](s):
    yield item

# iterator pairs*[T](s: SortedSet[T]): tuple[idx: int, item: T] =
#   for idx, item in seq[T](s):
#     yield (idx, item)


when isMainModule:
  var x = newSortedSet[int]()
  x.incl(5)
  x.incl(3)
  x.incl(4)
  for i in x:
    echo i
