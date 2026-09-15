///|
/// PEP 503 / PEP 427 / PEP 625 helpers: distribution names, version key forms
/// and distribution filenames.
///
/// Everything here is a pure function over strings. The semantics are aligned
/// with PyPA `packaging` 26.3 and verified by the differential corpus in
/// `examples/diff` (record kinds `canon` and `file`).
///
/// Known boundary: `packaging` validates wheel project names with a Unicode
/// aware regex (`^[\w._]+$`) and lowercases names with Unicode rules, while this
/// module works on ASCII. PEP 427 requires escaped ASCII names in wheel
/// filenames, so real inputs are unaffected; the corpus keeps non-ASCII out of
/// these records on purpose.

///|
/// True for the three characters PEP 503 treats as equivalent separators.
fn is_name_separator(c : Char) -> Bool {
  c == '-' || c == '_' || c == '.'
}

///|
/// ASCII word character, matching `\w` for the ASCII range.
fn is_word_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
}

///|
/// True when `c` may appear in a wheel project name: a word character or `.`
/// (that is, `packaging`'s `[\w._]+` restricted to ASCII).
fn is_wheel_name_char(c : Char) -> Bool {
  is_word_char(c) || c == '.'
}

///|
/// True when `c` may start a Python identifier, used to validate interpreter
/// components of a tag.
fn is_identifier_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_'
}

///|
/// True when `c` may continue a Python identifier.
fn is_identifier_continue(c : Char) -> Bool {
  is_word_char(c)
}

///|
/// Python's `str.isidentifier()` for the ASCII range: non-empty, starts with a
/// letter or `_`, and continues with word characters. Keywords are identifiers
/// for this purpose, which is what `packaging` relies on.
fn is_identifier(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    return false
  }
  if !is_identifier_start(chars[0]) {
    return false
  }
  for i = 1; i < chars.length(); i = i + 1 {
    if !is_identifier_continue(chars[i]) {
      return false
    }
  }
  true
}

///|
/// PEP 503 name normalization: lowercase, then collapse every run of `-`, `_`
/// and `.` into a single `-`.
///
/// Leading and trailing separators survive as a single `-`, matching
/// `packaging`: `canonicalize_name("-foo-") == "-foo-"`.
///
/// ```moonbit nocheck
/// canonicalize_name("Flask")                 // "flask"
/// canonicalize_name("importlib_metadata")    // "importlib-metadata"
/// canonicalize_name("zope.interface")        // "zope-interface"
/// canonicalize_name("Foo__Bar")              // "foo-bar"
/// ```
pub fn canonicalize_name(name : String) -> String {
  let out : Array[Char] = []
  let mut pending_separator = false
  for c in name.to_lower() {
    if is_name_separator(c) {
      pending_separator = true
    } else {
      if pending_separator {
        out.push('-')
        pending_separator = false
      }
      out.push(c)
    }
  }
  if pending_separator {
    out.push('-')
  }
  String::from_array(out)
}

///|
/// Release segments without trailing zeros, but never empty: `_TrimmedRelease`
/// in `packaging`, which "leaves one 0".
fn trim_release(release : Array[@bigint.BigInt]) -> Array[@bigint.BigInt] {
  let mut keep = release.length()
  while keep > 1 && release[keep - 1].compare(@bigint.BigInt::from_int(0)) == 0 {
    keep = keep - 1
  }
  let out : Array[@bigint.BigInt] = []
  for i = 0; i < keep; i = i + 1 {
    out.push(release[i])
  }
  out
}

///|
/// PEP 625 canonical version form. With `strip_trailing_zero` (the default)
/// the release segment loses its trailing zeros, which is the form used as an
/// index lookup key; without it the spelling is only normalized.
///
/// Invalid versions are returned unaltered rather than raising, matching
/// `packaging.utils.canonicalize_version`.
///
/// ```moonbit nocheck
/// canonicalize_version("1.0.0")                    // "1"
/// canonicalize_version("1.4.0.0.0")                // "1.4"
/// canonicalize_version("1.0.0.post0")              // "1.post0"
/// canonicalize_version("1!2.0")                    // "1!2"
/// canonicalize_version("0.0")                      // "0"
/// canonicalize_version("nope")                     // "nope"
/// canonicalize_version("1.0.0", strip_trailing_zero=false) // "1.0.0"
/// ```
pub fn canonicalize_version(
  version : String,
  strip_trailing_zero? : Bool = true,
) -> String {
  match parse_version_opt(version) {
    Some(v) =>
      if strip_trailing_zero {
        Version::to_string({ ..v, release: trim_release(v.release), })
      } else {
        Version::to_string(v)
      }
    None => version
  }
}

///|
fn parse_version_opt(raw : String) -> Version? {
  Some(Version::parse(raw)) catch {
    _ => None
  }
}

///|
/// Split `text` on `-` into at most `max_parts` pieces, the remainder staying
/// in the last piece (`str.split(sep, maxsplit)`).
fn split_limited(text : String, max_parts : Int) -> Array[String] {
  let out : Array[String] = []
  let chars = text.to_array()
  let current : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '-' && out.length() < max_parts - 1 {
      out.push(String::from_array(current))
      current.clear()
    } else {
      current.push(chars[i])
    }
  }
  out.push(String::from_array(current))
  out
}

///|
fn count_char(text : String, needle : Char) -> Int {
  let mut count = 0
  for c in text {
    if c == needle {
      count = count + 1
    }
  }
  count
}

///|
/// A parsed wheel filename: a normalized project name, the version, the
/// optional PEP 427 build tag split into `(leading digits, remainder)` and the
/// expanded tag set.
pub(all) struct WheelFilename {
  name : String
  version : Version
  build : (Int, String)?
  tags : Array[String]
} derive(Eq, @debug.Debug)

///|
/// A parsed source distribution filename.
pub(all) struct SdistFilename {
  name : String
  version : Version
} derive(Eq, @debug.Debug)

///|
/// Parse a PEP 427 wheel filename. Only the compressed tag set is expanded:
/// the returned tags are strings in `interpreter-abi-platform` form, sorted and
/// deduplicated, which is the stable projection of `packaging`'s frozenset of
/// `Tag` objects.
///
/// ```moonbit nocheck
/// let w = parse_wheel_filename("numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.whl")
/// w.name                       // "numpy"
/// w.version.to_string()        // "1.26.4"
/// w.build                      // None
/// w.tags                       // ["cp312-cp312-manylinux_2_17_x86_64"]
/// ```
pub fn parse_wheel_filename(
  filename : String,
) -> WheelFilename raise VersionError {
  let stem = match filename.strip_suffix(".whl") {
    Some(view) => view.to_owned()
    None => raise VersionError::InvalidFilename("WHEEL_EXTENSION", 0)
  }
  let dashes = count_char(stem, '-')
  if dashes != 4 && dashes != 5 {
    raise VersionError::InvalidFilename("WHEEL_PART_COUNT", 0)
  }
  let parts = split_limited(stem, dashes - 1)
  let name_part = parts[0]
  if name_part.contains("__") || !is_valid_wheel_name(name_part) {
    raise VersionError::InvalidFilename("WHEEL_PROJECT_NAME", 0)
  }
  let name = canonicalize_name(name_part)
  let version = match parse_version_opt(parts[1]) {
    Some(v) => v
    None => raise VersionError::InvalidFilename("WHEEL_VERSION", 0)
  }
  let build : (Int, String)? = if dashes == 5 {
    let build_part = parts[2]
    match split_build_tag(build_part) {
      Some(tag) => Some(tag)
      None => raise VersionError::InvalidFilename("WHEEL_BUILD_TAG", 0)
    }
  } else {
    None
  }
  let tags = parse_tag_set(parts[parts.length() - 1])
  { name, version, build, tags, }
}

///|
/// `[\w._]+` restricted to ASCII, and non-empty.
fn is_valid_wheel_name(name : String) -> Bool {
  let chars = name.to_array()
  if chars.length() == 0 {
    return false
  }
  for c in chars {
    if !is_wheel_name_char(c) {
      return false
    }
  }
  true
}

///|
/// PEP 427 build tag: leading ASCII digits plus an arbitrary remainder.
fn split_build_tag(text : String) -> (Int, String)? {
  let chars = text.to_array()
  if chars.length() == 0 || !chars[0].is_ascii_digit() {
    return None
  }
  let mut end = 0
  while end < chars.length() && chars[end].is_ascii_digit() {
    end = end + 1
  }
  let digits = String::from_array(chars[:end].to_owned())
  let rest = String::from_array(chars[end:].to_owned())
  Some((@string.parse_int(digits), rest)) catch {
    _ => None
  }
}

///|
/// Expand a compressed tag set (`py2.py3-none-any`) into sorted, deduplicated
/// `interpreter-abi-platform` strings. Rejects empty components and
/// interpreters that are not identifiers, and requires exactly three
/// dash separated components.
///
/// Every component is lowercased, because `packaging`'s `Tag` lowercases all
/// three in its constructor: `CP312-CP312-Manylinux_2_17_X86_64` and
/// `cp312-cp312-manylinux_2_17_x86_64` are the same tag, and the corpus
/// projection is the lowercase spelling. A wheel filename is allowed to spell
/// them either way, so this is not a leniency -- it is the normalization the
/// reference implementation performs.
fn parse_tag_set(tag : String) -> Array[String] raise VersionError {
  let components = tag.split("-")
  let groups : Array[Array[String]] = []
  for component in components {
    let parts : Array[String] = []
    for part in component.split(".") {
      let text = part.to_owned()
      if text.is_empty() {
        raise VersionError::InvalidFilename("TAG_EMPTY_COMPONENT", 0)
      }
      parts.push(text.to_lower())
    }
    groups.push(parts)
  }
  if groups.length() != 3 {
    raise VersionError::InvalidFilename("TAG_COMPONENT_COUNT", 0)
  }
  for interpreter in groups[0] {
    if !is_identifier(interpreter) {
      raise VersionError::InvalidFilename("TAG_INTERPRETER", 0)
    }
  }
  let out : Array[String] = []
  for interpreter in groups[0] {
    for abi in groups[1] {
      for platform in groups[2] {
        let one = "\{interpreter}-\{abi}-\{platform}"
        if !out.contains(one) {
          out.push(one)
        }
      }
    }
  }
  // `Array::sort` would order by length first for strings, which is not the
  // code point order that packaging's `sorted()` produces.
  out.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  out
}

///|
/// Parse a PEP 625 source distribution filename. The name is normalized; the
/// version must be a valid PEP 440 version. The stem is split on the last
/// dash, because a PEP 440 version cannot contain one.
///
/// ```moonbit nocheck
/// let s = parse_sdist_filename("flask-3.0.3.tar.gz")
/// s.name                  // "flask"
/// s.version.to_string()   // "3.0.3"
/// ```
pub fn parse_sdist_filename(
  filename : String,
) -> SdistFilename raise VersionError {
  let stem = match filename.strip_suffix(".tar.gz") {
    Some(view) => view.to_owned()
    None =>
      match filename.strip_suffix(".zip") {
        Some(view) => view.to_owned()
        None => raise VersionError::InvalidFilename("SDIST_EXTENSION", 0)
      }
  }
  let chars = stem.to_array()
  let mut cut = -1
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    if chars[i] == '-' {
      cut = i
      break
    }
  }
  if cut < 0 {
    raise VersionError::InvalidFilename("SDIST_NO_SEPARATOR", 0)
  }
  if cut == 0 {
    raise VersionError::InvalidFilename("SDIST_EMPTY_NAME", 0)
  }
  let name = canonicalize_name(String::from_array(chars[:cut].to_owned()))
  let version_part = String::from_array(chars[cut + 1:].to_owned())
  let version = match parse_version_opt(version_part) {
    Some(v) => v
    None => raise VersionError::InvalidFilename("SDIST_VERSION", 0)
  }
  { name, version, }
}
