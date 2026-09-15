///|
/// PEP 425 tag **computation**: the ordered tag list for a target the caller
/// describes, in the same order as `packaging.tags`.
///
/// The library already *matches* and *ranks* tags -- `parse_wheel_filename`
/// expands a wheel's compressed tag set, `IndexFile::tags` reports it, and the
/// resolver ranks candidates by the smallest index a wheel's tags occupy in the
/// caller's ordered tag list. What it did not do is *produce* that list. This
/// module does, and it is the same boundary as everywhere else in the library:
/// **the caller describes the target, the library computes from it, and nothing
/// is probed**.
///
/// That boundary decides what can be here. `packaging.tags.sys_tags()` is a
/// tuple of four probes -- `sys.version_info`, `sysconfig` config variables for
/// the ABI, `EXT_SUFFIX`, and `platform_tags()`, which on Linux inspects the
/// running libc to decide between `manylinux` and `musllinux`. None of that can
/// be reproduced from a document, and a library that guesses would give
/// different answers on different machines, which is exactly what this one is
/// built not to do. So:
///
/// - `cpython_tags`, `generic_tags`, `pure_python_tags`, `compatible_tags` and
///   `mac_platforms` take their interpreter, ABI list and platform list as
///   arguments, and behave exactly like the reference for those arguments;
/// - `manylinux` / `musllinux` / `linux` platform tags are **not** computed:
///   the caller passes whatever `packaging.tags.platform_tags()` said on the
///   machine it is describing, including the `manylinux` spellings;
/// - a missing argument that `packaging` would fill in from the host (an empty
///   Python version, an empty interpreter name) is a stable error here rather
///   than a silent probe.
///
/// The empty **platform** list is the sharpest edge of that boundary, because it
/// does not look like a probe at all. Every reference function here writes
/// `platforms = list(platforms or platform_tags())`, so an empty list does not
/// mean "no platforms", it means "ask the running machine" -- with the same `[]`
/// a caller would pass for a target that has none. This library reads `[]` the
/// way it is written and refuses the ambiguity: an empty platform list is
/// `TAG_PLATFORMS_REQUIRED`, and the three cases are registered as declared
/// divergences in `fixtures/tag_corpus.mbt`.
///
/// Order matters and is preserved: PEP 425 says a tool must prefer an earlier tag,
/// so the results are ordered arrays, most specific first, never sorted sets.

///|
/// The first two entries of a version, the way Python's `python_version[:2]`
/// behaves: a slice clamps instead of raising, so a major-only version yields
/// one entry.
fn first_two(version : Array[Int]) -> Array[Int] {
  if version.length() <= 2 {
    return version.copy()
  }
  [version[0], version[1]]
}

///|
/// `[3, 10]` becomes `"310"`, `[3]` becomes `"3"`, the way `packaging`'s
/// `_version_nodot` spells an interpreter version.
fn version_nodot(version : Array[Int]) -> String {
  let sb = StringBuilder()
  for part in version {
    sb.write_string(part.to_string())
  }
  sb.to_string()
}

///|
/// The `interpreter-abi-platform` spelling, lowercased.
///
/// `packaging`'s `Tag` lowercases all three components in its constructor, so
/// this is the reference's own normalization rather than a choice of ours: the
/// same tag written in any case is one tag.
fn tag_string(interpreter : String, abi : String, platform : String) -> String {
  "\{interpreter.to_lower()}-\{abi.to_lower()}-\{platform.to_lower()}"
}

///|
/// `packaging`'s `_is_threaded_cpython`: the ABI of a `--disable-gil` build (PEP
/// 703) carries a `t` in its flags, so `cp313t` is threaded and `cp313` is not.
/// The reference reads this off the first ABI, which is the one the interpreter
/// itself reported.
fn is_threaded_cpython(abis : Array[String]) -> Bool {
  if abis.length() == 0 {
    return false
  }
  let chars = abis[0].to_array()
  if chars.length() < 3 || chars[0] != 'c' || chars[1] != 'p' {
    return false
  }
  let mut i = 2
  let mut digits = 0
  while i < chars.length() && chars[i].is_ascii_digit() {
    i = i + 1
    digits = digits + 1
  }
  if digits == 0 {
    return false
  }
  for j = i; j < chars.length(); j = j + 1 {
    if chars[j] == 't' {
      return true
    }
  }
  false
}

///|
/// The tuple comparison `python_version >= (3, 2)` the reference uses for the
/// two stable-ABI decisions. A one-element version (a major version only) never
/// supports them, which is what `len(python_version) > 1` says there.
fn at_least_3_2(python_version : Array[Int]) -> Bool {
  if python_version.length() < 2 {
    return false
  }
  python_version[0] > 3 || (python_version[0] == 3 && python_version[1] >= 2)
}

///|
/// `packaging`'s `_abi3_applies`: PEP 384 landed in 3.2, and a free-threaded
/// build does not support the stable ABI.
fn abi3_applies(python_version : Array[Int], threading : Bool) -> Bool {
  at_least_3_2(python_version) && !threading
}

///|
/// `packaging`'s `_abi3t_applies`: PEP 803's threaded stable ABI, which the
/// reference generates back to 3.2 as well, to leave room for `abi3t` wheels
/// that support older limited-API versions.
fn abi3t_applies(python_version : Array[Int], threading : Bool) -> Bool {
  at_least_3_2(python_version) && threading
}

///|
/// Remove the first occurrence of `value`, the way `list.remove` raises nothing
/// in `packaging`'s `try/except ValueError` around each explicit ABI.
fn remove_first(items : Array[String], value : String) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    if items[i] == value {
      ignore(items.remove(i))
      return
    }
  }
}

///|
/// The CPython tags for a target, in `packaging.tags.cpython_tags` order.
///
/// `python_version` is `[3, 12]` or `[3]`; `abis` is what the interpreter
/// reported (`["cp312m"]`, `["cp313t"]`, `["abi3"]`, ...); `platforms` is the
/// platform list, most specific first.
///
/// The order the reference produces is: the explicit ABIs against every
/// platform, then the stable ABI (`abi3`, plus `abi3t` on a free-threaded
/// build) against every platform, then the empty `none` ABI, and finally the
/// same stable ABIs for the previous minor versions down to `cp32` -- older
/// stable-ABI wheels are usable, older version-specific ones are not.
///
/// ```moonbit nocheck
/// cpython_tags([3, 12], ["cp312"], ["linux_x86_64"])
/// // ["cp312-cp312-linux_x86_64", "cp312-abi3-linux_x86_64",
/// //  "cp312-none-linux_x86_64", "cp311-abi3-linux_x86_64", ...]
/// ```
pub fn cpython_tags(
  python_version : Array[Int],
  abis : Array[String],
  platforms : Array[String],
) -> Array[String] raise VersionError {
  if python_version.length() == 0 {
    // `packaging` would fall back to `sys.version_info`, which is the host. The
    // caller has to say which interpreter it is describing.
    raise VersionError::InvalidTag("TAG_VERSION_REQUIRED", 0)
  }
  if platforms.length() == 0 {
    // `platforms or platform_tags()`: an empty list means "probe the host"
    // there, and an empty tag list here. Refusing is the honest reading.
    raise VersionError::InvalidTag("TAG_PLATFORMS_REQUIRED", 0)
  }
  let interpreter = "cp\{version_nodot(first_two(python_version))}"
  let threading = is_threaded_cpython(abis)
  let explicit : Array[String] = if threading {
    ["abi3", "abi3t", "none"]
  } else {
    ["abi3", "none"]
  }
  let remaining : Array[String] = []
  for abi in abis {
    remaining.push(abi)
  }
  for abi in explicit {
    remove_first(remaining, abi)
  }
  let out : Array[String] = []
  for abi in remaining {
    for platform in platforms {
      out.push(tag_string(interpreter, abi, platform))
    }
  }
  let use_abi3 = abi3_applies(python_version, threading)
  let use_abi3t = abi3t_applies(python_version, threading)
  if use_abi3 {
    for platform in platforms {
      out.push(tag_string(interpreter, "abi3", platform))
    }
  }
  if use_abi3t {
    for platform in platforms {
      out.push(tag_string(interpreter, "abi3t", platform))
    }
  }
  for platform in platforms {
    out.push(tag_string(interpreter, "none", platform))
  }
  if use_abi3 || use_abi3t {
    let major = python_version[0]
    let minor = python_version[1]
    for older = minor - 1; older > 1; older = older - 1 {
      let older_interpreter = "cp\{version_nodot([major, older])}"
      for platform in platforms {
        if use_abi3 {
          out.push(tag_string(older_interpreter, "abi3", platform))
        }
        if use_abi3t {
          out.push(tag_string(older_interpreter, "abi3t", platform))
        }
      }
    }
  }
  out
}

///|
/// The tags for an interpreter that needs no specialization
/// (`packaging.tags.generic_tags`): every ABI against every platform, with the
/// empty `none` ABI appended when the caller did not list it.
///
/// The `none` test is exact, exactly as it is there: `["NONE"]` does not contain
/// `none`, so `none` is appended and the resulting list carries the same tag
/// twice. That is a duplicate in the reference too, and a corpus that silently
/// deduplicated it would be testing a different function.
pub fn generic_tags(
  interpreter : String,
  abis : Array[String],
  platforms : Array[String],
) -> Array[String] raise VersionError {
  if interpreter.is_empty() {
    // `packaging` would ask the running interpreter what it is.
    raise VersionError::InvalidTag("TAG_INTERPRETER_REQUIRED", 0)
  }
  if platforms.length() == 0 {
    raise VersionError::InvalidTag("TAG_PLATFORMS_REQUIRED", 0)
  }
  let all : Array[String] = []
  for abi in abis {
    all.push(abi)
  }
  if !all.contains("none") {
    all.push("none")
  }
  let out : Array[String] = []
  for abi in all {
    for platform in platforms {
      out.push(tag_string(interpreter, abi, platform))
    }
  }
  out
}

///|
/// `py310`, `py3`, `py39`, ... `py30`: the interpreter versions a project
/// supports without a compiled component, in `packaging`'s
/// `_py_interpreter_range` order -- the exact version, then the major-only one,
/// then every earlier minor of that major.
fn py_interpreter_range(python_version : Array[Int]) -> Array[String] {
  let out : Array[String] = []
  if python_version.length() > 1 {
    out.push("py\{version_nodot(first_two(python_version))}")
  }
  out.push("py\{python_version[0]}")
  if python_version.length() > 1 {
    let major = python_version[0]
    for minor = python_version[1] - 1; minor >= 0; minor = minor - 1 {
      out.push("py\{version_nodot([major, minor])}")
    }
  }
  out
}

///|
/// The pure-Python tags (`packaging.tags.pure_python_tags`): `none` ABI, `any`
/// platform, one per interpreter version in `py_interpreter_range` order. These
/// are the only tags whose computation does not depend on the target platform
/// at all, which is why a single-platform library can still ship them.
pub fn pure_python_tags(
  python_version : Array[Int],
) -> Array[String] raise VersionError {
  if python_version.length() == 0 {
    raise VersionError::InvalidTag("TAG_VERSION_REQUIRED", 0)
  }
  let out : Array[String] = []
  for version in py_interpreter_range(python_version) {
    out.push(tag_string(version, "none", "any"))
  }
  out
}

///|
/// The tags for a non-CPython interpreter that is compatible with the given
/// Python version (`packaging.tags.compatible_tags`): every `py*` version
/// against every platform, then `<interpreter>-none-any` when the caller named
/// an interpreter, then the pure-Python tags.
///
/// `interpreter` may be `None` (an unnamed interpreter) or an empty string: the
/// reference tests truthiness, so both mean "do not emit that line".
pub fn compatible_tags(
  python_version : Array[Int],
  interpreter : String?,
  platforms : Array[String],
) -> Array[String] raise VersionError {
  if python_version.length() == 0 {
    raise VersionError::InvalidTag("TAG_VERSION_REQUIRED", 0)
  }
  if platforms.length() == 0 {
    raise VersionError::InvalidTag("TAG_PLATFORMS_REQUIRED", 0)
  }
  let out : Array[String] = []
  for version in py_interpreter_range(python_version) {
    for platform in platforms {
      out.push(tag_string(version, "none", platform))
    }
  }
  match interpreter {
    Some(name) =>
      if !name.is_empty() {
        out.push(tag_string(name, "none", "any"))
      }
    None => ()
  }
  for tag in pure_python_tags(python_version) {
    out.push(tag)
  }
  out
}

///|
/// `packaging`'s `_mac_binary_formats`: the binary formats a macOS version
/// supports for an architecture, oldest first. The empty list for a version that
/// predates the architecture is not an error -- it is how the reference says
/// "no such wheel can exist", and it is what keeps `mac_platforms("10.3",
/// "x86_64")` from inventing tags.
fn mac_binary_formats(version : (Int, Int), arch : String) -> Array[String] {
  let formats : Array[String] = [arch]
  if arch == "x86_64" {
    if version < (10, 4) {
      return []
    }
    formats.push("intel")
    formats.push("fat64")
    formats.push("fat3")
  } else if arch == "i386" {
    if version < (10, 4) {
      return []
    }
    formats.push("intel")
    formats.push("fat3")
    formats.push("fat")
  } else if arch == "ppc64" {
    if version > (10, 5) || version < (10, 4) {
      return []
    }
    formats.push("fat64")
  } else if arch == "ppc" {
    if version > (10, 6) {
      return []
    }
    formats.push("fat3")
    formats.push("fat")
  }
  if arch == "arm64" || arch == "x86_64" {
    formats.push("universal2")
  }
  if arch == "x86_64" ||
    arch == "i386" ||
    arch == "ppc64" ||
    arch == "ppc" ||
    arch == "intel" {
    formats.push("universal")
  }
  formats
}

///|
/// The macOS platform tags for a version and architecture
/// (`packaging.tags.mac_platforms`), most specific first.
///
/// Both arguments are required, unlike the reference, where either may be left
/// out and read from the running machine. The rules are the reference's own:
/// before macOS 11 every release bumped the minor version under major 10; from
/// 11 on the major version is the release and the minor one is a midyear update;
/// and on 11+ the compatible 10.x range is replayed for `x86_64` (with the
/// `universal2` spelling only for other architectures).
pub fn mac_platforms(version : (Int, Int), arch : String) -> Array[String] {
  let out : Array[String] = []
  if version >= (10, 0) && version < (11, 0) {
    for minor = version.1; minor >= 0; minor = minor - 1 {
      for format in mac_binary_formats((10, minor), arch) {
        out.push("macosx_10_\{minor}_\{format}")
      }
    }
  }
  if version >= (11, 0) {
    for major = version.0; major > 10; major = major - 1 {
      for format in mac_binary_formats((major, 0), arch) {
        out.push("macosx_\{major}_0_\{format}")
      }
    }
    let major = 10
    for minor = 16; minor > 3; minor = minor - 1 {
      if arch == "x86_64" {
        for format in mac_binary_formats((major, minor), arch) {
          out.push("macosx_10_\{minor}_\{format}")
        }
      } else {
        out.push("macosx_10_\{minor}_universal2")
      }
    }
  }
  out
}

///|
/// The rank of a file's tag set against an ordered `supported` list: the
/// smallest index any of `tags` occupies, or `supported.length()` when none
/// does.
///
/// This is the selector rule `packaging.tags.create_compatible_tags_selector`
/// applies -- a thing matched by several tags is ranked by its *best* one, and
/// `supported` is ordered most specific first -- and the same rule the resolver
/// uses to order candidates. It is public here so callers who built their tag
/// list with the functions above can rank wheels with it.
pub fn tag_rank(tags : Array[String], supported : Array[String]) -> Int {
  let mut best = supported.length()
  for i = 0; i < tags.length(); i = i + 1 {
    for j = 0; j < supported.length(); j = j + 1 {
      if supported[j] == tags[i] && j < best {
        best = j
      }
    }
  }
  best
}
