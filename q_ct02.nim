import std/sha1
static:
  when defined(gcc):
    echo "gcc!"
  else:
    echo "else!"
  let tmp02 = "hello"
  let tmp03 = secureHash(tmp02)
  echo tmp03.Sha1Digest
