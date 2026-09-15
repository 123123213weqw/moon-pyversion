///|
/// The code of the error a raiseing tag call produced, or `<accepted>` when it
/// answered, so a test can name the rule it pins instead of only asserting that
/// something failed. The `try` form is the one the other suites use, and it
/// avoids the deprecated effect inference of an unannotated `fn` closure.
fn cpython_error(f : () -> Unit raise VersionError) -> String {
  try {
    f()
    "<accepted>"
  } catch {
    VersionError::InvalidTag(code, _) => code
    other => "unexpected:\{VersionError::diagnostic(other)}"
  }
}

///|
test "cpython tags follow the reference order: abi, stable abi, none" {
  // One platform keeps the order readable; the corpus does the same comparison
  // with dozens of platforms and yields.
  assert_eq(cpython_tags([3, 12], ["cp312"], ["linux_x86_64"]), [
    "cp312-cp312-linux_x86_64", "cp312-abi3-linux_x86_64", "cp312-none-linux_x86_64",
    "cp311-abi3-linux_x86_64", "cp310-abi3-linux_x86_64", "cp39-abi3-linux_x86_64",
    "cp38-abi3-linux_x86_64", "cp37-abi3-linux_x86_64", "cp36-abi3-linux_x86_64",
    "cp35-abi3-linux_x86_64", "cp34-abi3-linux_x86_64", "cp33-abi3-linux_x86_64",
    "cp32-abi3-linux_x86_64",
  ])
}

///|
test "cpython tags: the abi3 tail stops at cp32 and at the major boundary" {
  // 3.2 is the first version with the stable ABI, so 3.2 has none below it.
  assert_eq(cpython_tags([3, 2], ["cp32"], ["any"]), [
    "cp32-cp32-any", "cp32-abi3-any", "cp32-none-any",
  ])
  // 3.1 predates PEP 384 entirely: no abi3 line at all.
  assert_eq(cpython_tags([3, 1], ["cp31"], ["any"]), [
    "cp31-cp31-any", "cp31-none-any",
  ])
  // A major-only version supports no stable ABI -- the reference requires two
  // version components for that -- and has no minor to count down from.
  assert_eq(cpython_tags([3], ["cp3"], ["any"]), ["cp3-cp3-any", "cp3-none-any"])
}

///|
test "cpython tags: the explicit abis come first, in the order given" {
  // `abi3` and `none` are removed from the caller's list and re-emitted in the
  // reference's fixed positions, so passing them explicitly changes nothing.
  assert_eq(cpython_tags([3, 10], ["abi3", "none"], ["any"]), [
    "cp310-abi3-any", "cp310-none-any", "cp39-abi3-any", "cp38-abi3-any", "cp37-abi3-any",
    "cp36-abi3-any", "cp35-abi3-any", "cp34-abi3-any", "cp33-abi3-any", "cp32-abi3-any",
  ])
  // A debug build reports two ABIs; both are kept, in order, before abi3.
  assert_eq(cpython_tags([3, 7], ["cp37d", "cp37"], ["any"]), [
    "cp37-cp37d-any", "cp37-cp37-any", "cp37-abi3-any", "cp37-none-any", "cp36-abi3-any",
    "cp35-abi3-any", "cp34-abi3-any", "cp33-abi3-any", "cp32-abi3-any",
  ])
}

///|
test "cpython tags: a free-threaded abi swaps abi3 for abi3t" {
  // PEP 703: `cp313t` is threaded, so the stable ABI is the threaded one
  // (`abi3t`, PEP 803) and plain `abi3` is not offered at all.
  assert_eq(cpython_tags([3, 13], ["cp313t"], ["any"]), [
    "cp313-cp313t-any", "cp313-abi3t-any", "cp313-none-any", "cp312-abi3t-any", "cp311-abi3t-any",
    "cp310-abi3t-any", "cp39-abi3t-any", "cp38-abi3t-any", "cp37-abi3t-any", "cp36-abi3t-any",
    "cp35-abi3t-any", "cp34-abi3t-any", "cp33-abi3t-any", "cp32-abi3t-any",
  ])
  // Threading is read off the first ABI only, which is the interpreter's own:
  // a `cp313` first ABI keeps the unthreaded stable ABI even when a later one
  // says `t`, because that is what the reference does.
  assert_true(
    !cpython_tags([3, 13], ["cp313", "cp313t"], ["any"]).contains(
      "cp313-abi3t-any",
    ),
  )
}

///|
test "cpython tags: an empty platform list is refused, an empty ABI list is not" {
  // These two empty lists look alike and are not. `platforms or platform_tags()`
  // turns an empty platform list into a probe of the running machine, which is a
  // different question from the one the caller asked; an empty ABI list is taken
  // literally -- the interpreter reported no ABI, so only the stable ABI and
  // `none` are offered.
  assert_eq(
    cpython_error(() => ignore(cpython_tags([3, 12], ["cp312"], []))),
    "TAG_PLATFORMS_REQUIRED",
  )
  assert_eq(
    cpython_error(() => ignore(generic_tags("pp310", ["pp73"], []))),
    "TAG_PLATFORMS_REQUIRED",
  )
  assert_eq(
    cpython_error(() => ignore(compatible_tags([3, 12], Some("cp312"), []))),
    "TAG_PLATFORMS_REQUIRED",
  )
  // An empty ABI list means the interpreter reported none, so only the stable
  // ABI and `none` are offered.
  assert_eq(cpython_tags([3, 12], [], ["any"]), [
    "cp312-abi3-any", "cp312-none-any", "cp311-abi3-any", "cp310-abi3-any", "cp39-abi3-any",
    "cp38-abi3-any", "cp37-abi3-any", "cp36-abi3-any", "cp35-abi3-any", "cp34-abi3-any",
    "cp33-abi3-any", "cp32-abi3-any",
  ])
}

///|
test "cpython tags refuse to guess the interpreter version" {
  // `packaging` would read `sys.version_info` here. This library does not read
  // the host, so the caller has to say which interpreter it is describing.
  assert_eq(
    cpython_error(() => ignore(cpython_tags([], ["cp312"], ["any"]))),
    "TAG_VERSION_REQUIRED",
  )
}

///|
test "cpython tags lowercase every component" {
  // `Tag` lowercases in its constructor, so the caller's spelling is irrelevant.
  assert_eq(cpython_tags([3, 12], ["CP312"], ["Linux_X86_64"]), [
    "cp312-cp312-linux_x86_64", "cp312-abi3-linux_x86_64", "cp312-none-linux_x86_64",
    "cp311-abi3-linux_x86_64", "cp310-abi3-linux_x86_64", "cp39-abi3-linux_x86_64",
    "cp38-abi3-linux_x86_64", "cp37-abi3-linux_x86_64", "cp36-abi3-linux_x86_64",
    "cp35-abi3-linux_x86_64", "cp34-abi3-linux_x86_64", "cp33-abi3-linux_x86_64",
    "cp32-abi3-linux_x86_64",
  ])
}

///|
test "generic tags append the empty abi, exactly and only once" {
  assert_eq(generic_tags("pp310", ["pp73"], ["linux_x86_64"]), [
    "pp310-pp73-linux_x86_64", "pp310-none-linux_x86_64",
  ])
  assert_eq(generic_tags("pp310", ["none"], ["any"]), ["pp310-none-any"])
  // The membership test is exact, so `NONE` does not count as `none` and the
  // tag is emitted twice -- the reference produces the duplicate as well.
  assert_eq(generic_tags("pp310", ["NONE"], ["any"]), [
    "pp310-none-any", "pp310-none-any",
  ])
  // An empty ABI list is the "no compiled component" case, not an error.
  assert_eq(generic_tags("graalpy_38_native", [], ["any"]), [
    "graalpy_38_native-none-any",
  ])
  // An empty platform list, on the other hand, is refused: see the cpython suite.

}

///|
test "generic tags refuse to ask the host what interpreter this is" {
  assert_eq(
    cpython_error(() => ignore(generic_tags("", ["abi3"], ["any"]))),
    "TAG_INTERPRETER_REQUIRED",
  )
}

///|
test "pure python tags count down to py30" {
  assert_eq(pure_python_tags([3, 3]), [
    "py33-none-any", "py3-none-any", "py32-none-any", "py31-none-any", "py30-none-any",
  ])
  // A major-only version yields just the two.
  assert_eq(pure_python_tags([2]), ["py2-none-any"])
  assert_eq(
    cpython_error(() => ignore(pure_python_tags([]))),
    "TAG_VERSION_REQUIRED",
  )
}

///|
test "compatible tags put the named interpreter before the pure tags" {
  assert_eq(compatible_tags([3, 11], Some("cp311"), ["linux_x86_64"]), [
    "py311-none-linux_x86_64", "py3-none-linux_x86_64", "py310-none-linux_x86_64",
    "py39-none-linux_x86_64", "py38-none-linux_x86_64", "py37-none-linux_x86_64",
    "py36-none-linux_x86_64", "py35-none-linux_x86_64", "py34-none-linux_x86_64",
    "py33-none-linux_x86_64", "py32-none-linux_x86_64", "py31-none-linux_x86_64",
    "py30-none-linux_x86_64", "cp311-none-any", "py311-none-any", "py3-none-any",
    "py310-none-any", "py39-none-any", "py38-none-any", "py37-none-any", "py36-none-any",
    "py35-none-any", "py34-none-any", "py33-none-any", "py32-none-any", "py31-none-any",
    "py30-none-any",
  ])
}

///|
test "compatible tags treat an unnamed or empty interpreter as absent" {
  // The reference tests truthiness, so `""` and `None` mean the same thing: the
  // `<interpreter>-none-any` line is not emitted at all.
  let none = compatible_tags([3, 11], None, ["any"])
  let empty = compatible_tags([3, 11], Some(""), ["any"])
  assert_eq(none, empty)
  assert_true(!none.contains("cp311-none-any"))
  assert_eq(none[0], "py311-none-any")
}

///|
test "macos platform tags: the 10.x series walks down to 10.0" {
  assert_eq(mac_platforms((10, 9), "x86_64"), [
    "macosx_10_9_x86_64", "macosx_10_9_intel", "macosx_10_9_fat64", "macosx_10_9_fat3",
    "macosx_10_9_universal2", "macosx_10_9_universal", "macosx_10_8_x86_64", "macosx_10_8_intel",
    "macosx_10_8_fat64", "macosx_10_8_fat3", "macosx_10_8_universal2", "macosx_10_8_universal",
    "macosx_10_7_x86_64", "macosx_10_7_intel", "macosx_10_7_fat64", "macosx_10_7_fat3",
    "macosx_10_7_universal2", "macosx_10_7_universal", "macosx_10_6_x86_64", "macosx_10_6_intel",
    "macosx_10_6_fat64", "macosx_10_6_fat3", "macosx_10_6_universal2", "macosx_10_6_universal",
    "macosx_10_5_x86_64", "macosx_10_5_intel", "macosx_10_5_fat64", "macosx_10_5_fat3",
    "macosx_10_5_universal2", "macosx_10_5_universal", "macosx_10_4_x86_64", "macosx_10_4_intel",
    "macosx_10_4_fat64", "macosx_10_4_fat3", "macosx_10_4_universal2", "macosx_10_4_universal",
    // 10.3 predates x86_64 support, so the reference yields nothing for it.
  ])
}

///|
test "macos platform tags: arm64 has no 10.x range" {
  let tags = mac_platforms((11, 0), "arm64")
  assert_eq(tags[0], "macosx_11_0_arm64")
  assert_eq(tags[1], "macosx_11_0_universal2")
  // No `universal` for arm64, and no 10.x replay: those are x86_64-only.
  assert_true(!tags.contains("macosx_11_0_universal"))
  assert_true(!tags.contains("macosx_10_16_arm64"))
  assert_eq(tags[tags.length() - 1], "macosx_10_4_universal2")
}

///|
test "macos platform tags: an architecture older than the OS version is empty" {
  assert_eq(mac_platforms((10, 3), "x86_64"), [])
  assert_eq(mac_platforms((10, 3), "i386"), [])
  // ppc64 was supported on 10.4 and 10.5 only, so 10.6 skips the newest year
  // and starts at 10.5: empty binary formats remove a year from the list rather
  // than ending the walk.
  assert_eq(mac_platforms((10, 6), "ppc64"), [
    "macosx_10_5_ppc64", "macosx_10_5_fat64", "macosx_10_5_universal", "macosx_10_4_ppc64",
    "macosx_10_4_fat64", "macosx_10_4_universal",
  ])
  // ppc was dropped after 10.6, so 10.7 starts there.
  let ppc = mac_platforms((10, 7), "ppc")
  assert_eq(ppc[0], "macosx_10_6_ppc")
  assert_true(ppc.contains("macosx_10_3_ppc"))
  assert_true(!ppc.contains("macosx_10_7_ppc"))
  // Anything before 10.0 is not a macOS tag set at all.
  assert_eq(mac_platforms((9, 2), "x86_64"), [])
}

///|
test "macos platform tags: 11 and later replay the 10.x range for x86_64" {
  let tags = mac_platforms((12, 3), "x86_64")
  assert_eq(tags[0], "macosx_12_0_x86_64")
  // Six formats for 12.0, then the 11.0 line.
  assert_eq(tags[5], "macosx_12_0_universal")
  assert_eq(tags[6], "macosx_11_0_x86_64")
  assert_eq(tags.length(), 90)
  // The midyear minor version is ignored: 12.3 is still `macosx_12_0_*`.
  assert_true(!tags.contains("macosx_12_3_x86_64"))
  assert_eq(tags[tags.length() - 1], "macosx_10_4_universal")
}

///|
test "tag rank picks the best tag a file carries" {
  let supported = [
    "cp312-cp312-linux_x86_64", "cp312-abi3-linux_x86_64", "cp312-none-any", "py3-none-any",
  ]
  // A file whose tags include several supported ones is ranked by the earliest.
  assert_eq(tag_rank(["py3-none-any", "cp312-abi3-linux_x86_64"], supported), 1)
  assert_eq(tag_rank(["cp312-cp312-linux_x86_64"], supported), 0)
  // Nothing in common: the rank is the length, which makes it lose to every
  // file that intersects at all.
  assert_eq(tag_rank(["cp311-cp311-linux_x86_64"], supported), 4)
  assert_eq(tag_rank([], supported), 4)
  assert_eq(tag_rank(["py3-none-any"], []), 0)
}
