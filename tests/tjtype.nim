{.experimental: "codeReordering".}
import unittest
import macros
import dali

# dumpTree:
#   int[][]

# dumpTree:
#   java.lang.Object[][]

test "some builtin types":
  check "I" == jtype int
  check "J" == jtype long

test "object types":
  check "Ljava/lang/String;" == jtype java.lang.String
  check "Lhw;" == jtype hw

test "array types":
  check "[I" == jtype int[]
  check "[[I" == jtype int[][]
  check "[Ljava/lang/Object;" == jtype java.lang.Object[]
  check "[[Ljava/lang/Object;" == jtype java.lang.Object[][]

