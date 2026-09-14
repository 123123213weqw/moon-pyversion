///|
/// M9 tests: `index.mbt`, the offline package-index reader and candidate
/// resolver.
///
/// Where the expectations come from, all of them checked offline:
///
/// * **RFC 8259** for the JSON grammar. `parse_json` is a deliberate subset:
///   strict, no `NaN`/`Infinity`, member names must be unique, surrogate
///   escapes must pair, and a leading byte order mark is refused. Every rule
///   the doc comment on `parse_json` claims is pinned by a block below, and the
///   blocks assert the *error code* and, where it is meaningful, the UTF-16
///   offset, because the code is the diagnostic a caller reads.
/// * **PEP 691 / PEP 592 / PEP 700** for the simple-index JSON mapping, **PEP
///   427** and **PEP 625** for distribution filenames, **PEP 503** for name
///   normalization and **PEP 440** for version ordering and the prerelease
///   policy.
/// * **PyPA `packaging` 26.3** and **pip 26.x** for the resolver. The filenames
///   exercised in the scan blocks were run through
///   `packaging.utils.parse_wheel_filename` / `parse_sdist_filename`,
///   `canonicalize_name` and `canonicalize_version` in
///   `~/oracle-versions/venv26.3`; the classification, normalized names, parsed
///   versions and expanded tag sets below are that oracle's answers, and the
///   same names exist as real files in `fixtures_index/` beside this module.
///   The ordering rules are those of pip's
///   `pip._internal.index.package_finder.CandidateEvaluator._sort_key`:
///   version, then wheel-over-sdist, then the wheel's most preferred tag, then
///   the PEP 427 build tag. `index.mbt` adds a filename tie-break on top,
///   because pip's `max()` is otherwise free to depend on server order, and a
///   resolver that writes lock files must not be.
///
/// There is no I/O anywhere in this file: `LocalIndex::scan` takes an injected
/// `DirectoryLister`, so every scan block is a list of names in and a
/// `LocalIndex` out. The directory of real files (`fixtures_index/`) exists for
/// the packaging cross-check described above, not for these tests to read.

// --- shared helpers --------------------------------------------------------

///|
/// The `(code, offset)` a JSON text is rejected with, or `("<accepted>", -1)`.
fn json_error_at(text : String) -> (String, Int) {
  try {
    ignore(parse_json(text))
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidIndex(code, offset) => (code, offset)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// The error code of a rejected JSON text.
fn json_error(text : String) -> String {
  json_error_at(text).0
}

///|
/// True when a JSON text parses.
fn json_accepts(text : String) -> Bool {
  try {
    ignore(parse_json(text))
    true
  } catch {
    _ => false
  }
}

///|
/// Assert that a JSON text parses.
fn assert_json_accepts(text : String) -> Unit {
  if !json_accepts(text) {
    abort("expected the JSON to parse, got \{json_error(text)} for: \{text}")
  }
}

///|
/// Assert that a JSON text is rejected with exactly `code`.
fn assert_json_error(text : String, code : String) -> Unit {
  let actual = json_error(text)
  if actual != code {
    abort("expected \{code}, got \{actual} for: \{text}")
  }
}

///|
/// `text` parsed as a JSON value that must parse.
fn json_of(text : String) -> JsonValue {
  parse_json(text) catch {
    _ => abort("expected the JSON to parse: \{text}")
  }
}

///|
/// The payload of a JSON string that must parse.
fn json_string_of(text : String) -> String {
  match json_of(text) {
    JsonString(decoded) => decoded
    other => abort("expected a string, got \{@debug.to_string(other)}")
  }
}

///|
/// The source text of a JSON number that must parse.
fn json_number_of(text : String) -> String {
  match json_of(text) {
    JsonNumber(source) => source
    other => abort("expected a number, got \{@debug.to_string(other)}")
  }
}

///|
/// The JSON text of a one-character string: `"` + `c` + `"`.
fn json_string_with(c : Char) -> String {
  String::from_array(['"', c, '"'])
}

///|
/// The JSON text of a string holding the two-character escape `\c`.
fn json_escape_with(c : Char) -> String {
  String::from_array(['"', '\\', c, '"'])
}

///|
/// `open` repeated `depth` times around the scalar `1`, closed by `close`
/// repeated `depth` times, e.g. `("[", "]")` or `("{\"a\":", "}")`.
fn nested_json(open : String, close : String, depth : Int) -> String {
  let builder = StringBuilder()
  for i = 0; i < depth; i = i + 1 {
    builder.write_string(open)
  }
  builder.write_string("1")
  for i = 0; i < depth; i = i + 1 {
    builder.write_string(close)
  }
  builder.to_string()
}

///|
/// The `(code, ordinal)` a simple-index document is rejected with, or
/// `("<accepted>", -1)`.
fn index_error_at(json : String) -> (String, Int) {
  try {
    ignore(SimpleIndex::parse(json))
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidIndex(code, ordinal) => (code, ordinal)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// The error code of a rejected simple-index document, which may be a JSON-layer
/// code when the document is not even JSON.
fn index_error(json : String) -> String {
  index_error_at(json).0
}

///|
/// Assert that a simple-index document is rejected with exactly `code`.
fn assert_index_error(json : String, code : String) -> Unit {
  let actual = index_error(json)
  if actual != code {
    abort("expected \{code}, got \{actual} for: \{json}")
  }
}

///|
/// Assert that a simple-index document parses.
fn index_accepts_or_abort(json : String) -> Unit {
  ignore(
    SimpleIndex::parse(json) catch {
      _ => abort("expected the document to parse: \{json}")
    },
  )
}

///|
/// A `files[]` entry with the three required members plus `extra` spliced in
/// before the closing brace, so `extra` must start with a comma or be empty.
/// Use this for the *optional* members; the required ones need `entry_json`,
/// because a second `filename` member would be a duplicate name.
fn file_json(extra : String) -> String {
  "{\"filename\":\"demo-1.0-py3-none-any.whl\"," +
  "\"url\":\"https://index.example/demo-1.0-py3-none-any.whl\"," +
  "\"hashes\":{\"sha256\":\"aa\"}" +
  extra +
  "}"
}

///|
/// A `files[]` entry whose three required members are given as JSON source, so
/// a block can vary any one of them without creating a duplicate member name.
fn entry_json(filename : String, url : String, hashes : String) -> String {
  "{\"filename\":" +
  filename +
  ",\"url\":" +
  url +
  ",\"hashes\":" +
  hashes +
  "}"
}

///|
/// A whole simple-index document around the given `files[]` members.
fn document_json(files : String) -> String {
  "{\"meta\":{\"api-version\":\"1.4\"},\"name\":\"demo\",\"files\":[" +
  files +
  "]}"
}

///|
/// Parse the first `files[]` entry of a document that must parse.
fn first_file_of(json : String) -> SimpleIndexFile {
  let index = SimpleIndex::parse(json) catch {
    _ => abort("expected the document to parse: \{json}")
  }
  index.files()[0]
}

///|
/// Parse a `files[]` entry that must be valid, varying only an optional member.
fn simple_file_of(extra : String) -> SimpleIndexFile {
  first_file_of(document_json(file_json(extra)))
}

///|
/// The error code for a `files[]` entry, varying only an optional member.
fn simple_file_error(extra : String) -> String {
  index_error(document_json(file_json(extra)))
}

///|
/// Assert that a `files[]` entry is rejected with exactly `code`.
fn assert_simple_file_error(extra : String, code : String) -> Unit {
  let actual = simple_file_error(extra)
  if actual != code {
    abort("expected \{code}, got \{actual} for extra: \{extra}")
  }
}

///|
/// The filenames of a `SimpleIndexFile` array, in order.
fn index_filenames_of(files : Array[SimpleIndexFile]) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < files.length(); i = i + 1 {
    out.push(files[i].filename)
  }
  out
}

///|
/// The `(code, ordinal)` of a `wheels()`/`sdists()` classification failure, or
/// `("<accepted>", -1)`. The document itself must parse, so a failure here is
/// unambiguously a classification failure.
fn classify_error(json : String, wheels : Bool) -> (String, Int) {
  try {
    let index = SimpleIndex::parse(json)
    if wheels {
      ignore(index.wheels())
    } else {
      ignore(index.sdists())
    }
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidIndex(code, ordinal) => (code, ordinal)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// The error code of `SimpleIndexFile::to_index_file`, or `<accepted>`.
fn to_index_file_error(file : SimpleIndexFile) -> String {
  try {
    ignore(file.to_index_file())
    "<accepted>"
  } catch {
    VersionError::InvalidIndex(code, _) => code
    other => "unexpected:\{other.diagnostic()}"
  }
}

///|
/// Parse a requirement that must be valid.
fn resolve_requirement_of(text : String) -> Requirement {
  Requirement::parse(text) catch {
    _ => abort("expected the requirement to parse: \{text}")
  }
}

///|
/// Parse a version that must be valid.
fn resolve_version_of(text : String) -> Version {
  Version::parse(text) catch {
    _ => abort("expected \{text} to be a version")
  }
}

///|
/// An `IndexFile` for a wheel filename that must be a valid PEP 427 name.
fn wheel_file(filename : String, requires_python : String?) -> IndexFile {
  let wheel = parse_wheel_filename(filename) catch {
    _ => abort("expected a wheel filename: \{filename}")
  }
  {
    filename,
    path: filename,
    kind: WheelFile,
    name: wheel.name,
    version: wheel.version,
    requires_python,
  }
}

///|
/// An `IndexFile` for an sdist filename that must be a valid PEP 625 name.
fn sdist_file(filename : String, requires_python : String?) -> IndexFile {
  let sdist = parse_sdist_filename(filename) catch {
    _ => abort("expected an sdist filename: \{filename}")
  }
  {
    filename,
    path: filename,
    kind: SdistFile,
    name: sdist.name,
    version: sdist.version,
    requires_python,
  }
}

///|
/// The real fixture directory's entry names. Every one of these exists as a file
/// in `fixtures_index/`, and every expected value below is what `packaging` 26.3
/// reports for the same name.
fn fixture_names() -> Array[String] {
  [
    "Flask-3.0.2.tar.gz", "Flask-3.0.3-py3-none-any.whl", "Flask-3.0.4-1-py3-none-any.whl",
    "Flask-3.0.4-py3-none-any.whl", "README.txt", "broken-1.0.whl", "flask-3.0.3-py2.py3-none-any.whl",
    "importlib_metadata-7.0.0-py3-none-any.whl", "numpy-1.26.3.tar.gz", "numpy-1.26.3.zip",
    "numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl", "numpy-2.0.0rc1-cp312-cp312-macosx_11_0_arm64.whl",
    "pkg_a-1.0.0-py3-none-any.whl", "pkg_a-1.0.0.dev1-py3-none-any.whl", "pkg_a-1.0.0.tar.gz",
    "pkg_a-2.0.0-py3-none-any.whl", "zope.interface-6.0.zip", "zope.interface-6.1-cp312-cp312-win_amd64.whl",
  ]
}

///|
/// Scan `directory` with an injected lister returning `names` verbatim.
fn scan_of(directory : String, names : Array[String]) -> LocalIndex {
  LocalIndex::scan(directory, lister=fn(_directory) { names }) catch {
    _ => abort("expected the scan of \{directory} to succeed")
  }
}

///|
/// The fixture index, scanned from the fixture names at `/mirror`.
fn fixture_index() -> LocalIndex {
  scan_of("/mirror", fixture_names())
}

///|
/// The `(code, ordinal)` of a scan failure with a caller-supplied lister.
fn scan_with_error(
  directory : String,
  lister : DirectoryLister,
) -> (String, Int) {
  try {
    ignore(LocalIndex::scan(directory, lister~))
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidIndex(code, ordinal) => (code, ordinal)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// The `(code, ordinal)` of `LocalIndex::scan` called without a lister, which
/// exercises the default one.
fn scan_default_error(directory : String) -> (String, Int) {
  try {
    ignore(LocalIndex::scan(directory))
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidIndex(code, ordinal) => (code, ordinal)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// The file with exactly this filename, which must be present.
fn file_named(files : Array[IndexFile], filename : String) -> IndexFile {
  for i = 0; i < files.length(); i = i + 1 {
    if files[i].filename == filename {
      return files[i]
    }
  }
  abort("no file named \{filename}")
}

///|
/// True when some file has exactly this filename.
fn has_filename(files : Array[IndexFile], filename : String) -> Bool {
  for i = 0; i < files.length(); i = i + 1 {
    if files[i].filename == filename {
      return true
    }
  }
  false
}

///|
/// True when some `(filename, reason)` pair names this file.
fn has_reason(pairs : Array[(String, String)], filename : String) -> Bool {
  for i = 0; i < pairs.length(); i = i + 1 {
    if pairs[i].0 == filename {
      return true
    }
  }
  false
}

///|
/// The filenames of `files`, in order.
fn filenames_of(files : Array[IndexFile]) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < files.length(); i = i + 1 {
    out.push(files[i].filename)
  }
  out
}

///|
/// A plain `py3-none-any` tag list, the least specific wheel target.
fn generic_tags() -> Array[String] {
  ["py3-none-any"]
}

///|
/// A most-specific-first tag list in the shape `packaging.tags.sys_tags()`
/// produces on a CPython 3.12 manylinux machine: the exact interpreter tag
/// first, then the `abi3` tag, then the pure-Python tag.
fn cp312_tags() -> Array[String] {
  [
    "cp312-cp312-manylinux_2_17_x86_64", "cp312-abi3-manylinux_2_17_x86_64", "py3-none-any",
  ]
}

///|
/// The seven files the rejection blocks share. Exactly one trips each rule of
/// `explain_rejection` (given `demo>=2.0`), one is a valid candidate, and one is
/// an sdist that always survives tag filtering.
fn reason_files() -> Array[IndexFile] {
  [
    wheel_file("demo-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-py3-none-any.whl", Some(">=3.12")),
    wheel_file("demo-3.0rc1-py3-none-any.whl", None),
    wheel_file("demo-3.0-py3-none-any.whl", None),
    sdist_file("demo-2.0.tar.gz", None),
    wheel_file("other-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-cp39-cp39-win_amd64.whl", None),
  ]
}

// --- the JSON reader -------------------------------------------------------

///|
/// Every value kind, nested, with the exact shape the reader must produce.
test "json: every value kind parses, nested" {
  assert_eq(json_of("null"), JsonNull)
  assert_eq(json_of("true"), JsonBool(true))
  assert_eq(json_of("false"), JsonBool(false))
  assert_eq(json_of("\"text\""), JsonString("text"))
  assert_eq(json_of("42"), JsonNumber("42"))
  assert_eq(json_of("[]"), JsonArray([]))
  assert_eq(json_of("{}"), JsonObject([]))
  assert_eq(
    json_of("[{\"a\":[true,null]},[false]]"),
    JsonArray([
      JsonObject([("a", JsonArray([JsonBool(true), JsonNull]))]),
      JsonArray([JsonBool(false)]),
    ]),
  )
}

///|
/// RFC 8259 §4: member order is preserved, there is no sorting, and `field`
/// finds a member by exact name.
test "json: objects keep document order and field looks up by name" {
  let value = json_of("{\"b\":1,\"a\":[2],\"c\":{\"d\":null}}")
  assert_eq(value.field("a"), Some(JsonArray([JsonNumber("2")])))
  assert_eq(value.field("b"), Some(JsonNumber("1")))
  assert_eq(value.field("c").unwrap().field("d"), Some(JsonNull))
  assert_eq(value.field("missing"), None)
  // A non-object has no members; `field` answers None instead of raising.
  assert_eq(json_of("1").field("a"), None)
  assert_eq(json_of("[]").field("a"), None)
  assert_eq(json_of("null").field("a"), None)
  match value {
    JsonObject(members) => {
      assert_eq(members.length(), 3)
      assert_eq(members[0].0, "b")
      assert_eq(members[1].0, "a")
      assert_eq(members[2].0, "c")
    }
    _ => abort("expected an object")
  }
}

///|
/// RFC 8259 §7: the two-character escapes. The JSON text is assembled from
/// characters so the block cannot be defeated by host-language escaping rules.
test "json: the two-character escapes decode" {
  let escapes : Array[(Char, Char)] = [
    ('"', '"'),
    ('\\', '\\'),
    ('/', '/'),
    ('b', Int::unsafe_to_char(0x08)),
    ('f', Int::unsafe_to_char(0x0C)),
    ('n', '\n'),
    ('r', '\r'),
    ('t', '\t'),
  ]
  for i = 0; i < escapes.length(); i = i + 1 {
    let decoded = json_string_of(json_escape_with(escapes[i].0))
    assert_eq(decoded, String::from_array([escapes[i].1]))
  }
}

///|
/// RFC 8259 §7: `\uXXXX`, including U+0000 and a correctly ordered surrogate
/// pair, which must collapse into one astral code point.
test "json: \\uXXXX decodes BMP, NUL and surrogate pairs" {
  assert_eq(json_string_of("\"\\u0041\""), "A")
  assert_eq(
    json_string_of("\"\\u00E9\""),
    String::from_array([Int::unsafe_to_char(0xE9)]),
  )
  assert_eq(
    json_string_of("\"\\u0000\""),
    String::from_array([Int::unsafe_to_char(0)]),
  )
  let pair = json_string_of("\"\\uD83D\\uDE00\"")
  assert_eq(pair, "\u{1F600}")
  // One code point, two UTF-16 code units: the reader never leaves a pair as
  // two separate characters.
  assert_eq(pair.to_array().length(), 1)
  assert_eq(pair.length(), 2)
  assert_eq(json_string_of("\"x\\uD83D\\uDE00y\""), "x\u{1F600}y")
  // A raw astral character in the source passes through unchanged (§8.1).
  assert_eq(json_string_of("\"\u{1F600}\""), "\u{1F600}")
}

///|
/// RFC 8259 §7/§8.2: a surrogate escape pair must be high-then-low and both
/// halves must be present. Each malformed shape is refused rather than repaired.
test "json: surrogate escapes must pair, in that order" {
  assert_json_error("\"\\uD83D\"", "JSON_LONE_SURROGATE")
  assert_json_error("\"\\uDE00\"", "JSON_LONE_SURROGATE")
  assert_json_error("\"\\uD83Dx\"", "JSON_LONE_SURROGATE")
  assert_json_error("\"\\uD83D\\uD83D\"", "JSON_LONE_SURROGATE")
  assert_json_error("\"\\uD83D\\u0041\"", "JSON_LONE_SURROGATE")
  assert_json_error("[\"\\uD83D\"]", "JSON_LONE_SURROGATE")
}

///|
/// RFC 8259 §7: `\u` needs four hex digits and only the listed escapes exist.
test "json: \\u needs four hex digits and other escapes are refused" {
  assert_json_error("\"\\u00\"", "JSON_BAD_UNICODE")
  assert_json_error("\"\\uZZZZ\"", "JSON_BAD_UNICODE")
  assert_json_error("\"\\u12g4\"", "JSON_BAD_UNICODE")
  assert_json_error("\"\\q\"", "JSON_BAD_ESCAPE")
  assert_json_error("\"\\'\"", "JSON_BAD_ESCAPE")
}

///|
/// RFC 8259 §6: `JsonNumber` keeps the source text, so the reader is exact
/// about numbers it does not understand and never formats one back.
test "json: number forms are accepted and keep their source text" {
  let forms : Array[String] = [
    "0", "-0", "1", "-1", "42", "1.5", "-1.5", "0.1", "1.0", "1e3", "1E3", "1e+3",
    "1e-3", "1.5e10", "-0.0", "0e0", "123456789012345678901234567890",
  ]
  for i = 0; i < forms.length(); i = i + 1 {
    assert_eq(json_number_of(forms[i]), forms[i])
  }
}

///|
/// RFC 8259 §6: the grammar violations, each with the code the reader promises.
/// `.5` and `+1` never reach the number reader (a value cannot start with `.`
/// or `+`), so they surface as `JSON_UNEXPECTED_CHAR`; `-Infinity` does start
/// with `-` and so reaches the number reader, which reports `JSON_BAD_NUMBER`.
test "json: number grammar violations are rejected by code" {
  assert_json_error("01", "JSON_LEADING_ZERO")
  assert_json_error("00", "JSON_LEADING_ZERO")
  assert_json_error("-01", "JSON_LEADING_ZERO")
  assert_json_error("1.", "JSON_BAD_NUMBER")
  assert_json_error("1e", "JSON_BAD_NUMBER")
  assert_json_error("1e+", "JSON_BAD_NUMBER")
  assert_json_error("-", "JSON_BAD_NUMBER")
  assert_json_error("-Infinity", "JSON_BAD_NUMBER")
  assert_json_error(".5", "JSON_UNEXPECTED_CHAR")
  assert_json_error("+1", "JSON_UNEXPECTED_CHAR")
  assert_json_error("1.2.3", "JSON_TRAILING")
  assert_json_error("1 2", "JSON_TRAILING")
}

///|
/// RFC 8259 §8: literals are the three exact lower-case words, and every other
/// bare word is refused. `truex` parses as `true` and then fails on the trailing
/// `x`, which is the trailing-content rule rather than a literal rule.
test "json: literals are exact and bare words are refused" {
  assert_eq(json_of(" true "), JsonBool(true))
  assert_json_error("True", "JSON_BAD_LITERAL")
  assert_json_error("NULL", "JSON_BAD_LITERAL")
  assert_json_error("nul", "JSON_BAD_LITERAL")
  assert_json_error("undefined", "JSON_BAD_LITERAL")
  assert_json_error("NaN", "JSON_BAD_LITERAL")
  assert_json_error("Infinity", "JSON_BAD_LITERAL")
  assert_json_error("truex", "JSON_TRAILING")
}

///|
/// RFC 8259 §7: U+0000..U+001F must be escaped in a string, while U+007F (DEL)
/// and the C1 range are ordinary characters.
test "json: control characters must be escaped, DEL and C1 need not be" {
  assert_json_error(
    json_string_with(Int::unsafe_to_char(0)),
    "JSON_CONTROL_CHAR",
  )
  assert_json_error(
    json_string_with(Int::unsafe_to_char(1)),
    "JSON_CONTROL_CHAR",
  )
  assert_json_error(json_string_with('\t'), "JSON_CONTROL_CHAR")
  assert_json_error(json_string_with('\n'), "JSON_CONTROL_CHAR")
  assert_json_error(
    json_string_with(Int::unsafe_to_char(0x1F)),
    "JSON_CONTROL_CHAR",
  )
  assert_eq(
    json_string_of(json_string_with(Int::unsafe_to_char(0x7F))),
    String::from_array([Int::unsafe_to_char(0x7F)]),
  )
  assert_eq(
    json_string_of(json_string_with(Int::unsafe_to_char(0x85))),
    String::from_array([Int::unsafe_to_char(0x85)]),
  )
}

///|
/// RFC 8259 says member names *SHOULD* be unique; this reader makes that
/// *MUST*, because a PEP 691 consumer must never see a shadowed `url` or
/// `hashes`. Names that differ only in case are still distinct.
test "json: duplicate member names are refused" {
  assert_json_error("{\"a\":1,\"a\":2}", "JSON_DUPLICATE_KEY")
  assert_json_error("{\"a\":1,\"b\":2,\"a\":3}", "JSON_DUPLICATE_KEY")
  assert_json_error("{\"a\":{\"b\":1,\"b\":2}}", "JSON_DUPLICATE_KEY")
  assert_eq(
    json_of("{\"A\":1,\"a\":2}"),
    JsonObject([("A", JsonNumber("1")), ("a", JsonNumber("2"))]),
  )
}

///|
/// RFC 8259 §2/§3: a document is one value, optionally surrounded by
/// whitespace, and nothing else. Trailing whitespace is not trailing content.
test "json: trailing content is refused" {
  assert_json_error("{} {}", "JSON_TRAILING")
  assert_json_error("[1,2]x", "JSON_TRAILING")
  assert_json_error("[1] []", "JSON_TRAILING")
  assert_eq(json_of("[1] "), JsonArray([JsonNumber("1")]))
  assert_eq(json_of("\n\t{}\r "), JsonObject([]))
}

///|
/// RFC 8259 §2: the only insignificant whitespace is space, tab, LF and CR.
/// U+000B, U+000C and U+00A0 are not whitespace here, and a leading byte order
/// mark is not skipped either -- §8.1 only *permits* ignoring one, and a strict
/// reader fed to lock-file tooling should not guess.
test "json: whitespace is exactly space, tab, LF, CR, and no BOM" {
  assert_json_accepts(" \t\r\n[1, 2] \t\r\n")
  assert_json_error("\u{000B}1", "JSON_UNEXPECTED_CHAR")
  assert_json_error("\u{000C}1", "JSON_UNEXPECTED_CHAR")
  assert_json_error("\u{00A0}1", "JSON_UNEXPECTED_CHAR")
  assert_json_error("\u{FEFF}1", "JSON_UNEXPECTED_CHAR")
  assert_json_error("\u{FEFF}{}", "JSON_UNEXPECTED_CHAR")
  assert_json_error("'single'", "JSON_UNEXPECTED_CHAR")
}

///|
/// Unterminated containers and strings, and a document with no value at all.
test "json: unterminated and empty input" {
  assert_json_error("", "JSON_EOF")
  assert_json_error("   ", "JSON_EOF")
  assert_json_error("\"abc", "JSON_UNTERMINATED")
  assert_json_error("\"abc\\", "JSON_UNTERMINATED")
  assert_json_error("{\"a\":1", "JSON_EXPECT_COMMA")
  assert_json_error("[1,2", "JSON_EXPECT_COMMA")
  assert_json_error("{\"a\":", "JSON_EOF")
}

///|
/// RFC 8259 §4/§5: the punctuation rules. There is no trailing comma in either
/// container, `,` and `:` are mandatory, and a member name must be a string.
test "json: structural punctuation errors" {
  assert_json_error("{\"a\" 1}", "JSON_EXPECT_COLON")
  assert_json_error("{\"a\"}", "JSON_EXPECT_COLON")
  assert_json_error("[1 2]", "JSON_EXPECT_COMMA")
  assert_json_error("{a:1}", "JSON_EXPECT_KEY")
  assert_json_error("{\"a\":1,}", "JSON_EXPECT_KEY")
  assert_json_error("[1,]", "JSON_UNEXPECTED_CHAR")
  assert_json_error("{\"a\":}", "JSON_UNEXPECTED_CHAR")
}

///|
/// `JSON_MAX_DEPTH` bounds the recursion of the reader: a value at depth 128 is
/// accepted and one at depth 129 is refused, so the boundary is pinned here
/// rather than only described.
test "json: nesting is accepted to the limit and refused past it" {
  assert_true(json_accepts(nested_json("[", "]", 128)))
  assert_eq(json_error(nested_json("[", "]", 129)), "JSON_DEPTH")
  assert_true(json_accepts(nested_json("{\"a\":", "}", 128)))
  assert_eq(json_error(nested_json("{\"a\":", "}", 129)), "JSON_DEPTH")
  // A deep but bounded document still parses into the right shape.
  assert_eq(
    json_of(nested_json("[", "]", 3)),
    JsonArray([JsonArray([JsonArray([JsonNumber("1")])])]),
  )
}

///|
/// The reader reports UTF-16 code unit offsets, the convention `VersionError`
/// documents, so an astral character earlier in the document shifts a later
/// offset by two, and an index-layer position is an ordinal instead.
test "json: error offsets count UTF-16 code units" {
  assert_eq(json_error_at("1 2"), ("JSON_TRAILING", 2))
  assert_eq(json_error_at("\"ab\"x"), ("JSON_TRAILING", 4))
  assert_eq(json_error_at("\"\u{1F600}\"x"), ("JSON_TRAILING", 4))
  assert_eq(json_error_at("[\"\u{1F600}\", 01]"), ("JSON_LEADING_ZERO", 8))
  assert_eq(json_error_at("{\"a\":1,\"a\":2}"), ("JSON_DUPLICATE_KEY", 10))
  assert_eq(json_error_at("ok"), ("JSON_BAD_LITERAL", 0))
  assert_eq(json_error_at(""), ("JSON_EOF", 0))
}

///|
/// A MoonBit `String` is a sequence of Unicode scalar values, so a byte sequence
/// that is not well-formed UTF-8 cannot be constructed, let alone passed to
/// `parse_json`. The closest things to "invalid UTF-8-ish input" are a lone
/// surrogate escape (unrepresentable as a `Char`, refused) and a raw control
/// character (refused); a raw U+FFFD, which is what a lossy decoder produces, is
/// an ordinary character and passes through.
test "json: malformed encodings cannot be expressed; surrogates are the analogue" {
  assert_json_error("\"\\uDC00\\uD800\"", "JSON_LONE_SURROGATE")
  assert_json_error("\"\\uDFFF\"", "JSON_LONE_SURROGATE")
  assert_eq(json_string_of("\"\u{FFFD}\""), "\u{FFFD}")
  assert_eq(json_string_of("\"\u{FFFD}\u{FFFD}\""), "\u{FFFD}\u{FFFD}")
}

// --- PEP 691 simple-index JSON ---------------------------------------------

///|
/// A realistic response: `meta.api-version`, `name`, a wheel and an sdist with
/// the members PEP 691 defines, and `versions` from PEP 700.
test "691: a realistic document maps onto the model" {
  let document = "{" +
    "\"meta\":{\"api-version\":\"1.4\"}," +
    "\"name\":\"Flask\"," +
    "\"versions\":[\"3.0.4\",\"3.0.3\"]," +
    "\"files\":[" +
    "{\"filename\":\"Flask-3.0.4-py3-none-any.whl\"," +
    "\"url\":\"https://files.example/flask/Flask-3.0.4-py3-none-any.whl\"," +
    "\"hashes\":{\"sha256\":\"aa11\",\"md5\":\"bb22\"}," +
    "\"requires-python\":\">=3.8\"," +
    "\"size\":123456," +
    "\"upload-time\":\"2024-04-01T10:00:00.000000Z\"," +
    "\"yanked\":false}," +
    "{\"filename\":\"Flask-3.0.4.tar.gz\"," +
    "\"url\":\"https://files.example/flask/Flask-3.0.4.tar.gz\"," +
    "\"hashes\":{\"sha256\":\"cc33\"}," +
    "\"yanked\":\"broken sdist\"}" +
    "]}"
  let index = SimpleIndex::parse(document) catch {
    _ => abort("expected the document to parse")
  }
  assert_eq(index.name(), "Flask")
  assert_eq(canonicalize_name(index.name()), "flask")
  assert_eq(index.api_version(), Some("1.4"))
  assert_eq(index.versions(), ["3.0.4", "3.0.3"])
  assert_eq(index.files().length(), 2)
  assert_eq(index.wheels().length(), 1)
  assert_eq(index.sdists().length(), 1)
  let wheel = index.files()[0]
  assert_eq(wheel.filename, "Flask-3.0.4-py3-none-any.whl")
  assert_eq(
    wheel.url,
    "https://files.example/flask/Flask-3.0.4-py3-none-any.whl",
  )
  assert_eq(wheel.requires_python, Some(">=3.8"))
  assert_eq(wheel.size, Some(123456))
  assert_eq(wheel.upload_time, Some("2024-04-01T10:00:00.000000Z"))
  assert_eq(wheel.yanked, NotYanked)
  assert_eq(wheel.hashes, [("sha256", "aa11"), ("md5", "bb22")])
  assert_eq(wheel.hash_for("sha256"), Some("aa11"))
  assert_eq(wheel.hash_for("md5"), Some("bb22"))
  assert_eq(wheel.hash_for("blake2b"), None)
  let sdist = index.files()[1]
  assert_eq(sdist.yanked, Yanked("broken sdist"))
  assert_eq(sdist.requires_python, None)
  assert_eq(sdist.size, None)
  assert_eq(sdist.upload_time, None)
}

///|
/// PEP 691 requires `meta`, but the version only gates optional features, so a
/// document without it is readable and reports `None`; `name` is carried
/// verbatim, since the index chooses its spelling.
test "691: name is verbatim and api-version is optional" {
  let index = SimpleIndex::parse("{\"name\":\"Zope.Interface\",\"files\":[]}") catch {
    _ => abort("expected the document to parse")
  }
  assert_eq(index.name(), "Zope.Interface")
  assert_eq(index.api_version(), None)
  assert_eq(index.files().length(), 0)
  assert_eq(index.versions(), [])
  let empty_meta = SimpleIndex::parse(
    "{\"meta\":{},\"name\":\"x\",\"files\":[]}",
  ) catch {
    _ => abort("expected the document to parse")
  }
  assert_eq(empty_meta.api_version(), None)
  // An explicitly null api-version counts as absent, not as an error.
  let null_meta = SimpleIndex::parse(
    "{\"meta\":{\"api-version\":null},\"name\":\"x\",\"files\":[]}",
  ) catch {
    _ => abort("expected the document to parse")
  }
  assert_eq(null_meta.api_version(), None)
}

///|
/// PEP 691 `requires-python` is "a version specifier or the empty string". An
/// empty (or blank) one is normalized to `None` so the resolver has a single
/// spelling of "no constraint".
test "691: requires-python is kept, and an empty one becomes absent" {
  assert_eq(simple_file_of("").requires_python, None)
  assert_eq(
    simple_file_of(",\"requires-python\":\">=3.8,!=3.9.*\"").requires_python,
    Some(">=3.8,!=3.9.*"),
  )
  assert_eq(simple_file_of(",\"requires-python\":\"\"").requires_python, None)
  assert_eq(
    simple_file_of(",\"requires-python\":\"   \"").requires_python,
    None,
  )
  assert_eq(simple_file_of(",\"requires-python\":null").requires_python, None)
  assert_simple_file_error(
    ",\"requires-python\":1", "INDEX_BAD_REQUIRES_PYTHON",
  )
  assert_simple_file_error(
    ",\"requires-python\":[]", "INDEX_BAD_REQUIRES_PYTHON",
  )
}

///|
/// PEP 592: `yanked` is either a boolean or a string. `true` means yanked with
/// no reason, which is spelled `Yanked("")`; both shapes are kept distinct from
/// "not yanked" so a caller can report the reason. Note that an explicit `null`
/// is not one of the two shapes PEP 592 defines, so it is refused.
test "691: yanked in both shapes" {
  assert_eq(simple_file_of("").yanked, NotYanked)
  assert_eq(simple_file_of(",\"yanked\":false").yanked, NotYanked)
  assert_eq(simple_file_of(",\"yanked\":true").yanked, Yanked(""))
  assert_eq(simple_file_of(",\"yanked\":\"broken\"").yanked, Yanked("broken"))
  assert_eq(simple_file_of(",\"yanked\":\"\"").yanked, Yanked(""))
  assert_simple_file_error(",\"yanked\":null", "INDEX_BAD_YANKED")
  assert_simple_file_error(",\"yanked\":1", "INDEX_BAD_YANKED")
  assert_simple_file_error(",\"yanked\":{\"reason\":\"x\"}", "INDEX_BAD_YANKED")
}

///|
/// PEP 691 requires the `hashes` member but says nothing about its contents, so
/// an empty object is legal. A non-string digest is not.
test "691: hashes are a required object of strings" {
  let good = document_json(
    entry_json(
      "\"demo-1.0-py3-none-any.whl\"", "\"u\"", "{\"sha256\":\"aa\",\"blake2b\":\"bb\"}",
    ),
  )
  assert_eq(first_file_of(good).hashes, [("sha256", "aa"), ("blake2b", "bb")])
  let empty = document_json(
    entry_json("\"demo-1.0-py3-none-any.whl\"", "\"u\"", "{}"),
  )
  assert_eq(first_file_of(empty).hashes, [])
  assert_eq(first_file_of(empty).hash_for("sha256"), None)
  assert_index_error(
    document_json(entry_json("\"demo-1.0-py3-none-any.whl\"", "\"u\"", "[]")),
    "INDEX_BAD_HASHES",
  )
  assert_index_error(
    document_json(
      entry_json("\"demo-1.0-py3-none-any.whl\"", "\"u\"", "\"aa\""),
    ),
    "INDEX_BAD_HASHES",
  )
  assert_index_error(
    document_json(
      entry_json("\"demo-1.0-py3-none-any.whl\"", "\"u\"", "{\"sha256\":1}"),
    ),
    "INDEX_BAD_HASH",
  )
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[{\"filename\":\"demo-1.0-py3-none-any.whl\",\"url\":\"u\"}]}",
    "INDEX_MISSING_HASHES",
  )
}

///|
/// PEP 691 `size` is a non-negative byte count. The text is validated rather
/// than read as a float, so the legal-JSON-but-meaningless `1.0` and `1e3` are
/// refused instead of rounded.
test "691: size and upload-time are typed" {
  assert_eq(simple_file_of(",\"size\":0").size, Some(0))
  assert_eq(simple_file_of(",\"size\":123").size, Some(123))
  assert_eq(simple_file_of(",\"size\":null").size, None)
  assert_eq(
    simple_file_of(",\"upload-time\":\"2024-01-01T00:00:00Z\"").upload_time,
    Some("2024-01-01T00:00:00Z"),
  )
  assert_eq(simple_file_of(",\"upload-time\":null").upload_time, None)
  assert_simple_file_error(",\"size\":1.0", "INDEX_BAD_SIZE")
  assert_simple_file_error(",\"size\":1e3", "INDEX_BAD_SIZE")
  assert_simple_file_error(",\"size\":-1", "INDEX_BAD_SIZE")
  assert_simple_file_error(",\"size\":\"123\"", "INDEX_BAD_SIZE")
  assert_simple_file_error(",\"size\":true", "INDEX_BAD_SIZE")
  assert_simple_file_error(",\"upload-time\":5", "INDEX_BAD_UPLOAD_TIME")
}

///|
/// PEP 658 / PEP 714 `dist-info-metadata` and `core-metadata`. `index.mbt` has
/// no accessor for either, which is a deliberate reduction: they are unknown
/// members to this reader, and PEP 691 requires clients to ignore unknown
/// members. This block pins that they are accepted in every shape PEP 658 and
/// PEP 714 define and that they change nothing else about the entry.
test "691: dist-info-metadata and core-metadata are accepted and ignored" {
  let plain = simple_file_of("")
  assert_eq(simple_file_of(",\"dist-info-metadata\":true"), plain)
  assert_eq(simple_file_of(",\"dist-info-metadata\":false"), plain)
  assert_eq(
    simple_file_of(",\"dist-info-metadata\":{\"sha256\":\"bb\"}"),
    plain,
  )
  assert_eq(simple_file_of(",\"core-metadata\":true"), plain)
  assert_eq(simple_file_of(",\"core-metadata\":false"), plain)
  assert_eq(simple_file_of(",\"core-metadata\":{\"sha256\":\"bb\"}"), plain)
  assert_eq(
    simple_file_of(
      ",\"dist-info-metadata\":true,\"core-metadata\":{\"sha256\":\"bb\"}",
    ),
    plain,
  )
}

///|
/// PEP 691 clients must ignore members they do not know, but a *duplicate*
/// member is not an unknown member: the JSON layer refuses it, so a `url` can
/// never be shadowed.
test "691: unknown members are ignored, duplicate members are refused" {
  assert_eq(
    simple_file_of(",\"provenance\":\"https://example/p\""),
    simple_file_of(""),
  )
  assert_eq(
    simple_file_of(",\"unknown\":{\"nested\":[1,2,{\"deep\":null}]}"),
    simple_file_of(""),
  )
  index_accepts_or_abort(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[],\"unknown\":[1,2]}",
  )
  assert_json_error(
    "{\"name\":\"a\",\"name\":\"b\",\"files\":[]}", "JSON_DUPLICATE_KEY",
  )
}

///|
/// PEP 700's `versions` is optional, keeps the order the index published (it is
/// not sorted) and must contain only strings.
test "691: versions are optional, ordered and strings" {
  let document = "{\"meta\":{},\"name\":\"demo\",\"files\":[],\"versions\":[\"2.0\",\"1.0\",\"1.5\"]}"
  let index = SimpleIndex::parse(document) catch {
    _ => abort("expected the document to parse")
  }
  assert_eq(index.versions(), ["2.0", "1.0", "1.5"])
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[],\"versions\":[1]}", "INDEX_BAD_VERSIONS",
  )
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[],\"versions\":\"1.0\"}", "INDEX_BAD_VERSIONS",
  )
  assert_eq(
    index_error_at(
      "{\"meta\":{},\"name\":\"demo\",\"files\":[],\"versions\":[1]}",
    ),
    ("INDEX_BAD_VERSIONS", 0),
  )
}

///|
/// Document-level rejections, each with its code. A document whose root is not
/// an object has no `files`, so it is reported as `INDEX_MISSING_FILES`: the
/// reader has no separate "root must be an object" code, and this block records
/// that as the observable behaviour.
test "691: document-level errors are reported by code" {
  assert_index_error("[]", "INDEX_MISSING_FILES")
  assert_index_error("1", "INDEX_MISSING_FILES")
  assert_index_error("\"demo\"", "INDEX_MISSING_FILES")
  assert_index_error("{\"name\":\"demo\"}", "INDEX_MISSING_FILES")
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":1}", "INDEX_BAD_FILES",
  )
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":\"x\"}", "INDEX_BAD_FILES",
  )
  assert_index_error(
    "{\"meta\":1,\"name\":\"demo\",\"files\":[]}", "INDEX_BAD_META",
  )
  assert_index_error(
    "{\"meta\":{\"api-version\":1},\"name\":\"demo\",\"files\":[]}", "INDEX_BAD_API_VERSION",
  )
  assert_index_error("{\"meta\":{},\"files\":[]}", "INDEX_NAME_MISSING")
  assert_index_error("{\"meta\":{},\"name\":1,\"files\":[]}", "INDEX_NAME_TYPE")
  // A malformed document still reports the JSON layer's code.
  assert_index_error("{\"name\":\"demo\",\"files\":[}", "JSON_UNEXPECTED_CHAR")
}

///|
/// `files[]`-level rejections. The position is the ordinal of the offending
/// entry, not a byte offset, which is a different convention from the JSON
/// layer's.
test "691: file-level errors carry the entry ordinal" {
  assert_eq(simple_file_error(""), "<accepted>")
  // `file_json` already carries `filename` and `url`, so splicing a second one
  // is a duplicate member, which the JSON layer refuses: the typed cases below
  // use `entry_json` to vary a required member without duplicating it.
  assert_simple_file_error(
    ",\"filename\":\"demo-1.0-py3-none-any.whl\"", "JSON_DUPLICATE_KEY",
  )
  assert_simple_file_error(",\"url\":\"u\"", "JSON_DUPLICATE_KEY")
  assert_index_error(
    document_json(entry_json("null", "\"u\"", "{}")),
    "INDEX_FILENAME_TYPE",
  )
  assert_index_error(
    document_json(entry_json("\"demo-1.0-py3-none-any.whl\"", "1", "{}")),
    "INDEX_URL_TYPE",
  )
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[{\"url\":\"u\",\"hashes\":{}}]}",
    "INDEX_FILENAME_MISSING",
  )
  assert_index_error(
    "{\"meta\":{},\"name\":\"demo\",\"files\":[{\"filename\":\"a-1.0-py3-none-any.whl\",\"hashes\":{}}]}",
    "INDEX_URL_MISSING",
  )
  // The ordinal, not an offset: the second entry is at fault.
  let two_entries = "{\"meta\":{},\"name\":\"demo\",\"files\":[" +
    "{\"filename\":\"a-1.0-py3-none-any.whl\",\"url\":\"u\",\"hashes\":{}}," +
    "{\"filename\":\"a-2.0-py3-none-any.whl\",\"url\":\"u\",\"hashes\":[]}]}"
  assert_eq(index_error_at(two_entries), ("INDEX_BAD_HASHES", 1))
}

///|
/// `wheels()` and `sdists()` classify by filename. A `files[]` entry that is
/// neither is an error rather than a silent omission, and the position names the
/// entry; `SimpleIndex::parse` alone accepts such an entry, which is why the
/// block checks both.
test "691: wheels and sdists classify, and a non-distribution is an error" {
  let mixed = document_json(
    "{\"filename\":\"demo-1.0-py3-none-any.whl\",\"url\":\"u\",\"hashes\":{}}," +
    "{\"filename\":\"demo-1.0.tar.gz\",\"url\":\"u\",\"hashes\":{}}",
  )
  let index = SimpleIndex::parse(mixed) catch { _ => abort("expected a parse") }
  assert_eq(index_filenames_of(index.wheels()), ["demo-1.0-py3-none-any.whl"])
  assert_eq(index_filenames_of(index.sdists()), ["demo-1.0.tar.gz"])
  let unknown = document_json(
    "{\"filename\":\"README.txt\",\"url\":\"u\",\"hashes\":{}}",
  )
  // Parsing is fine: PEP 691 does not require every entry to be a distribution.
  index_accepts_or_abort(unknown)
  // Classification is where it becomes an error, at the entry's ordinal.
  assert_eq(classify_error(unknown, true), ("INDEX_UNKNOWN_DIST", 0))
  assert_eq(classify_error(unknown, false), ("INDEX_UNKNOWN_DIST", 0))
  let later = document_json(
    "{\"filename\":\"demo-1.0-py3-none-any.whl\",\"url\":\"u\",\"hashes\":{}}," +
    "{\"filename\":\"broken-1.0.whl\",\"url\":\"u\",\"hashes\":{}}",
  )
  assert_eq(classify_error(later, true), ("INDEX_UNKNOWN_DIST", 1))
  assert_eq(classify_error(later, false), ("INDEX_UNKNOWN_DIST", 1))
}

///|
/// `to_index_file` is the bridge from an index response to a resolver input: it
/// uses the entry's `url` as the path and carries the `requires-python`
/// constraint that a directory scan cannot know.
test "691: to_index_file uses the url and carries requires-python" {
  let json = document_json(
    "{\"filename\":\"demo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl\"," +
    "\"url\":\"https://index.example/demo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl\"," +
    "\"hashes\":{},\"requires-python\":\">=3.12\"}," +
    "{\"filename\":\"demo-1.0.tar.gz\",\"url\":\"https://index.example/demo-1.0.tar.gz\"," +
    "\"hashes\":{}}",
  )
  let index = SimpleIndex::parse(json) catch { _ => abort("expected a parse") }
  let wheel = index.files()[0].to_index_file() catch {
    _ => abort("expected a wheel")
  }
  assert_eq(
    wheel.path,
    "https://index.example/demo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl",
  )
  assert_eq(wheel.name, "demo")
  assert_eq(wheel.version.to_string(), "1.0")
  assert_eq(wheel.requires_python, Some(">=3.12"))
  assert_eq(wheel.kind, WheelFile)
  assert_eq(wheel.tags(), ["cp312-cp312-manylinux_2_17_x86_64"])
  let sdist = index.files()[1].to_index_file() catch {
    _ => abort("expected an sdist")
  }
  assert_eq(sdist.kind, SdistFile)
  assert_eq(sdist.requires_python, None)
  assert_eq(sdist.tags(), [])
  let bad = document_json(
    "{\"filename\":\"README.txt\",\"url\":\"u\",\"hashes\":{}}",
  )
  let bad_index = SimpleIndex::parse(bad) catch {
    _ => abort("expected a parse")
  }
  assert_eq(to_index_file_error(bad_index.files()[0]), "INDEX_UNKNOWN_DIST")
}

// --- the local directory scan ----------------------------------------------

///|
/// The fixture directory in full. Two entries are ignored (`README.txt` and
/// `broken-1.0.whl`), leaving sixteen distributions; every name, normalized
/// name, version and tag set is what `packaging` 26.3 reports.
test "scan: real fixture filenames classify as packaging 26.3 does" {
  let index = fixture_index()
  assert_eq(index.directory, "/mirror")
  assert_eq(index.files.length(), 16)
  let sdist = file_named(index.files, "Flask-3.0.2.tar.gz")
  assert_eq(sdist.kind, SdistFile)
  assert_eq(sdist.name, "flask")
  assert_eq(sdist.version.to_string(), "3.0.2")
  assert_eq(sdist.tags(), [])
  assert_eq(sdist.path, "/mirror/Flask-3.0.2.tar.gz")
  assert_eq(sdist.requires_python, None)
  let wheel = file_named(index.files, "Flask-3.0.3-py3-none-any.whl")
  assert_eq(wheel.kind, WheelFile)
  assert_eq(wheel.name, "flask")
  assert_eq(wheel.version.to_string(), "3.0.3")
  assert_eq(wheel.tags(), ["py3-none-any"])
  // PEP 503 normalization: `importlib_metadata` and `zope.interface`.
  assert_eq(
    file_named(index.files, "importlib_metadata-7.0.0-py3-none-any.whl").name,
    "importlib-metadata",
  )
  assert_eq(
    file_named(index.files, "zope.interface-6.0.zip").name,
    "zope-interface",
  )
  assert_eq(
    file_named(index.files, "zope.interface-6.0.zip").version.to_string(),
    "6.0",
  )
  assert_eq(file_named(index.files, "pkg_a-1.0.0.tar.gz").name, "pkg-a")
  // A prerelease version survives parsing unharmed.
  assert_eq(
    file_named(index.files, "numpy-2.0.0rc1-cp312-cp312-macosx_11_0_arm64.whl").version.to_string(),
    "2.0.0rc1",
  )
  // Two sdists of one project and version, distinguished by extension.
  assert_eq(
    file_named(index.files, "numpy-1.26.3.tar.gz").version.to_string(),
    "1.26.3",
  )
  assert_eq(
    file_named(index.files, "numpy-1.26.3.zip").version.to_string(),
    "1.26.3",
  )
}

///|
/// A PEP 427 build tag is parsed off the name, and a compressed PEP 425 tag set
/// is expanded and sorted, exactly as `parse_wheel_filename` documents.
test "scan: build tags and compressed tag sets are visible" {
  let index = fixture_index()
  let built = file_named(index.files, "Flask-3.0.4-1-py3-none-any.whl")
  assert_eq(built.kind, WheelFile)
  assert_eq(built.version.to_string(), "3.0.4")
  let unbuilt = file_named(index.files, "Flask-3.0.4-py3-none-any.whl")
  assert_eq(unbuilt.version.to_string(), "3.0.4")
  // The build tag is not part of `IndexFile`, but it is still visible through
  // the filename parser, and the two files remain distinct entries.
  assert_false(built.filename == unbuilt.filename)
  assert_eq(parse_wheel_filename(built.filename).build, Some((1, "")))
  assert_eq(parse_wheel_filename(unbuilt.filename).build, None)
  // A compressed tag set expands, and the expansion is sorted.
  let compressed = file_named(index.files, "flask-3.0.3-py2.py3-none-any.whl")
  assert_eq(compressed.tags(), ["py2-none-any", "py3-none-any"])
  let multi = file_named(
    index.files,
    "numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
  )
  assert_eq(multi.tags(), [
    "cp312-cp312-manylinux2014_x86_64", "cp312-cp312-manylinux_2_17_x86_64",
  ])
}

///|
/// Files that are neither wheels nor sdists are ignored, not reported: a
/// directory is expected to hold anything. `broken-1.0.whl` has the wheel
/// extension but not the four dashes PEP 427 requires.
test "scan: files that are neither wheel nor sdist are ignored" {
  let index = fixture_index()
  assert_false(has_filename(index.files, "README.txt"))
  assert_false(has_filename(index.files, "broken-1.0.whl"))
  assert_eq(
    scan_of("/m", ["README.txt", "Makefile", "demo-1.0.tar.bz2"]).files.length(),
    0,
  )
  assert_eq(scan_of("/m", ["demo.whl", "demo.tar.gz"]).files.length(), 0)
  assert_eq(scan_of("/m", []).files.length(), 0)
  assert_eq(scan_of("/m", []).packages(), [])
}

///|
/// `packages()` returns canonicalized names, deduplicated and sorted with
/// `String::lexical_compare`. The second scan deliberately contains a
/// length-inversion (`b` before `aa` under a length-first sort) to pin that the
/// order is by code point.
test "scan: packages are canonical, deduplicated and sorted by code point" {
  assert_eq(fixture_index().packages(), [
    "flask", "importlib-metadata", "numpy", "pkg-a", "zope-interface",
  ])
  let inverted = scan_of("/m", [
    "b-1.0-py3-none-any.whl", "aa-1.0-py3-none-any.whl", "B-2.0-py3-none-any.whl",
  ])
  assert_eq(inverted.packages(), ["aa", "b"])
  assert_eq(inverted.files.length(), 3)
}

///|
/// `files_for` normalizes its argument with PEP 503 rules before comparing, so
/// any spelling of a project name finds the same files, and an unknown name
/// yields an empty array rather than an error.
test "scan: files_for normalizes the query" {
  let index = fixture_index()
  assert_eq(index.files_for("flask").length(), 5)
  assert_eq(index.files_for("Flask").length(), 5)
  assert_eq(index.files_for("FLASK").length(), 5)
  assert_eq(index.files_for("fl_ask").length(), 0)
  assert_eq(index.files_for("Zope.Interface").length(), 2)
  assert_eq(index.files_for("zope-interface").length(), 2)
  assert_eq(index.files_for("importlib_metadata").length(), 1)
  assert_eq(index.files_for("importlib.metadata").length(), 1)
  assert_eq(index.files_for("nope").length(), 0)
  assert_eq(index.files_for("").length(), 0)
}

///|
/// Duplicate entries and names that differ only in case are all kept: the scan
/// reports what the directory holds and does not silently merge. `packages()` is
/// where the case difference collapses.
test "scan: duplicates and case differences are all kept" {
  let names = [
    "demo-1.0-py3-none-any.whl", "demo-1.0-py3-none-any.whl", "DEMO-1.0-py3-none-any.whl",
    "Demo-1.0.tar.gz",
  ]
  let index = scan_of("/m", names)
  assert_eq(index.files.length(), 4)
  assert_eq(index.packages(), ["demo"])
  assert_eq(index.files_for("demo").length(), 4)
  // Ordering inside the index is by normalized name, then by filename, so the
  // scan is reproducible regardless of the order the lister returned.
  assert_eq(filenames_of(index.files), [
    "DEMO-1.0-py3-none-any.whl", "Demo-1.0.tar.gz", "demo-1.0-py3-none-any.whl",
    "demo-1.0-py3-none-any.whl",
  ])
  let reversed = scan_of("/m", [
    "Demo-1.0.tar.gz", "demo-1.0-py3-none-any.whl", "DEMO-1.0-py3-none-any.whl",
    "demo-1.0-py3-none-any.whl",
  ])
  assert_eq(filenames_of(reversed.files), filenames_of(index.files))
}

///|
/// `path` is the scanned directory joined to the entry name, with a single `/`
/// even when the caller supplied a trailing separator, and with no leading
/// separator when the directory is empty.
test "scan: paths are joined from the scanned directory" {
  let names = ["demo-1.0-py3-none-any.whl"]
  assert_eq(
    scan_of("/mirror", names).files[0].path,
    "/mirror/demo-1.0-py3-none-any.whl",
  )
  assert_eq(
    scan_of("/mirror/", names).files[0].path,
    "/mirror/demo-1.0-py3-none-any.whl",
  )
  assert_eq(scan_of("", names).files[0].path, "demo-1.0-py3-none-any.whl")
  assert_eq(scan_of("mirror", names).directory, "mirror")
}

///|
/// The default lister reports `INDEX_NO_FS` instead of pretending the directory
/// is empty: this build of `moonbitlang/core` has no filesystem package, so an
/// empty answer would be a lie. The listing is injected precisely so that a host
/// which does have a filesystem can supply one.
test "scan: the default lister refuses instead of reporting an empty index" {
  assert_eq(scan_default_error("/anything"), ("INDEX_NO_FS", 0))
  // A caller-supplied lister that fails is reported with its own code and
  // position, untouched.
  let failing : DirectoryLister = _directory => {
    raise VersionError::InvalidIndex("LISTER_FAILED", 7)
  }
  assert_eq(scan_with_error("/x", failing), ("LISTER_FAILED", 7))
}

///|
/// `IndexFile::tags` reads a wheel's tags through the filename parser and is
/// empty for an sdist. An `IndexFile` built by hand around a name the parser
/// rejects has no tags, which the resolver reads as "matches nothing".
test "scan: an sdist has no tags, and an unparseable wheel name has none" {
  let index = fixture_index()
  assert_eq(file_named(index.files, "Flask-3.0.2.tar.gz").tags(), [])
  assert_eq(file_named(index.files, "numpy-1.26.3.zip").tags(), [])
  let hand_built : IndexFile = {
    filename: "broken-1.0.whl",
    path: "broken-1.0.whl",
    kind: WheelFile,
    name: "broken",
    version: resolve_version_of("1.0"),
    requires_python: None,
  }
  assert_eq(hand_built.tags(), [])
  // Such a file can never be a candidate, because its tag set is empty.
  let requirement = resolve_requirement_of("broken")
  assert_eq(
    resolve_candidates([hand_built], requirement, generic_tags(), None).length(),
    0,
  )
  assert_eq(
    explain_rejection([hand_built], requirement, generic_tags(), None),
    [("broken-1.0.whl", "tags")],
  )
}

// --- candidate resolution --------------------------------------------------

///|
/// Rule 1: the highest PEP 440 version is offered first, whatever the file kind,
/// and the input array is left alone.
test "resolver: candidates are ordered by version first" {
  let files : Array[IndexFile] = [
    wheel_file("demo-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-py3-none-any.whl", None),
    wheel_file("demo-1.5-py3-none-any.whl", None),
    sdist_file("demo-0.9.tar.gz", None),
  ]
  let candidates = resolve_candidates(
    files,
    resolve_requirement_of("demo"),
    generic_tags(),
    None,
  )
  assert_eq(filenames_of(candidates), [
    "demo-2.0-py3-none-any.whl", "demo-1.5-py3-none-any.whl", "demo-1.0-py3-none-any.whl",
    "demo-0.9.tar.gz",
  ])
  assert_eq(files.length(), 4)
  assert_eq(files[0].filename, "demo-1.0-py3-none-any.whl")
}

///|
/// Rule 2: at one version a wheel outranks an sdist, which is pip's
/// wheel-over-source preference expressed through the tag component of its sort
/// key.
test "resolver: a wheel outranks an sdist of the same version" {
  let files : Array[IndexFile] = [
    sdist_file("demo-2.0.tar.gz", None),
    wheel_file("demo-2.0-py3-none-any.whl", None),
    sdist_file("demo-2.0.zip", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-2.0-py3-none-any.whl", "demo-2.0.tar.gz", "demo-2.0.zip"],
  )
}

///|
/// Rule 3: among wheels of one version, the one whose best tag appears earliest
/// in the caller's most-specific-first list wins. pip's
/// `Wheel.find_most_preferred_tag` takes the minimum priority over the file's
/// tags and its sort key negates it, so the smallest index is preferred.
test "resolver: the more preferred tag wins among equal wheels" {
  let files : Array[IndexFile] = [
    wheel_file("demo-2.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-cp312-abi3-manylinux_2_17_x86_64.whl", None),
    wheel_file("demo-2.0-cp312-cp312-manylinux_2_17_x86_64.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        cp312_tags(),
        None,
      ),
    ),
    [
      "demo-2.0-cp312-cp312-manylinux_2_17_x86_64.whl", "demo-2.0-cp312-abi3-manylinux_2_17_x86_64.whl",
      "demo-2.0-py3-none-any.whl",
    ],
  )
  // Reordering the caller's list reorders the answer: the ranking follows the
  // interpreter, not the filename.
  let generic_first = ["py3-none-any", "cp312-cp312-manylinux_2_17_x86_64"]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        generic_first,
        None,
      ),
    ),
    [
      "demo-2.0-py3-none-any.whl", "demo-2.0-cp312-cp312-manylinux_2_17_x86_64.whl",
    ],
  )
}

///|
/// Rule 4: a PEP 427 build tag breaks a version-and-tag tie, with the larger
/// build number first and a tagged wheel above an untagged one, matching pip's
/// `(int, str)`-versus-empty-tuple build component.
test "resolver: a higher build tag wins a version tie" {
  let files : Array[IndexFile] = [
    wheel_file("demo-2.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-1-py3-none-any.whl", None),
    wheel_file("demo-2.0-2-py3-none-any.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
      ),
    ),
    [
      "demo-2.0-2-py3-none-any.whl", "demo-2.0-1-py3-none-any.whl", "demo-2.0-py3-none-any.whl",
    ],
  )
}

///|
/// With no supported tags every wheel is filtered out and only sdists remain,
/// because PEP 425 constrains wheels and an sdist is built from source.
test "resolver: an empty tag list leaves only sdists" {
  let files : Array[IndexFile] = [
    wheel_file("demo-2.0-py3-none-any.whl", None),
    sdist_file("demo-2.0.tar.gz", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(files, resolve_requirement_of("demo"), [], None),
    ),
    ["demo-2.0.tar.gz"],
  )
  assert_eq(
    explain_rejection(files, resolve_requirement_of("demo"), [], None),
    [("demo-2.0-py3-none-any.whl", "tags")],
  )
}

///|
/// The three filters that are not about ordering. Each of the four files trips
/// exactly one of them, and the "version" rule is checked before "tags".
test "resolver: name, version and tag filters" {
  let files : Array[IndexFile] = [
    wheel_file("demo-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-py3-none-any.whl", None),
    wheel_file("other-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0-cp39-cp39-win_amd64.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo==1.0"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-1.0-py3-none-any.whl"],
  )
  assert_eq(
    explain_rejection(
      files,
      resolve_requirement_of("demo==1.0"),
      generic_tags(),
      None,
    ),
    [
      ("demo-2.0-py3-none-any.whl", "version"),
      ("other-1.0-py3-none-any.whl", "name"),
      ("demo-2.0-cp39-cp39-win_amd64.whl", "version"),
    ],
  )
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-2.0-py3-none-any.whl", "demo-1.0-py3-none-any.whl"],
  )
  assert_eq(
    explain_rejection(
      files,
      resolve_requirement_of("demo"),
      generic_tags(),
      None,
    ),
    [
      ("other-1.0-py3-none-any.whl", "name"),
      ("demo-2.0-cp39-cp39-win_amd64.whl", "tags"),
    ],
  )
}

///|
/// `requires-python` is applied only when both sides are known: the file must
/// carry the constraint and the caller must pass an interpreter version. A
/// caller that passes `None` gets no filtering, which is what an offline planner
/// with no target interpreter wants.
test "resolver: requires-python is honoured when both sides are known" {
  let files = reason_files()
  let requirement = resolve_requirement_of("demo>=2.0")
  let py312 = resolve_candidates(
    files,
    requirement,
    generic_tags(),
    Some(resolve_version_of("3.12.4")),
  )
  assert_true(has_filename(py312, "demo-2.0-py3-none-any.whl"))
  let py39 = resolve_candidates(
    files,
    requirement,
    generic_tags(),
    Some(resolve_version_of("3.9.18")),
  )
  assert_false(has_filename(py39, "demo-2.0-py3-none-any.whl"))
  assert_eq(
    explain_rejection(
      files,
      requirement,
      generic_tags(),
      Some(resolve_version_of("3.9.18")),
    ),
    [
      ("demo-1.0-py3-none-any.whl", "version"),
      ("demo-2.0-py3-none-any.whl", "requires-python"),
      ("demo-3.0rc1-py3-none-any.whl", "prerelease"),
      ("other-1.0-py3-none-any.whl", "name"),
      ("demo-2.0-cp39-cp39-win_amd64.whl", "tags"),
    ],
  )
  // No interpreter known: the constraint is not applied.
  let unknown = resolve_candidates(files, requirement, generic_tags(), None)
  assert_true(has_filename(unknown, "demo-2.0-py3-none-any.whl"))
  assert_false(
    has_reason(
      explain_rejection(files, requirement, generic_tags(), None),
      "demo-2.0-py3-none-any.whl",
    ),
  )
}

///|
/// An unparseable `requires-python` is treated as no constraint, which is what
/// pip does: `check_requires_python` raises `InvalidSpecifier` and
/// `_check_link_requires_python` logs "Ignoring invalid Requires-Python" and
/// keeps the link. An empty one is likewise no constraint.
test "resolver: an invalid requires-python is ignored, like pip" {
  let files : Array[IndexFile] = [
    wheel_file("demo-1.0-py3-none-any.whl", Some("not-a-specifier")),
    wheel_file("demo-2.0-py3-none-any.whl", Some("")),
    wheel_file("demo-3.0-py3-none-any.whl", Some("   ")),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        files,
        resolve_requirement_of("demo"),
        generic_tags(),
        Some(resolve_version_of("3.9")),
      ),
    ),
    [
      "demo-3.0-py3-none-any.whl", "demo-2.0-py3-none-any.whl", "demo-1.0-py3-none-any.whl",
    ],
  )
  assert_eq(
    explain_rejection(
      files,
      resolve_requirement_of("demo"),
      generic_tags(),
      Some(resolve_version_of("3.9")),
    ),
    [],
  )
}

///|
/// PEP 440's prerelease policy, all three modes. With `None` the automatic rule
/// applies (finals win, and prereleases are used only when no final matches);
/// `Some(true)` admits prereleases and `Some(false)` excludes them. The policy
/// is decided over every name-matching file at once, so a prerelease is dropped
/// only because a final version exists.
test "resolver: the prerelease policy in all three modes" {
  let mixed : Array[IndexFile] = [
    wheel_file("demo-1.0-py3-none-any.whl", None),
    wheel_file("demo-2.0rc1-py3-none-any.whl", None),
    wheel_file("demo-2.0.dev1-py3-none-any.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        mixed,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-1.0-py3-none-any.whl"],
  )
  assert_eq(
    filenames_of(
      resolve_candidates(
        mixed,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
        prereleases=Some(true),
      ),
    ),
    [
      "demo-2.0rc1-py3-none-any.whl", "demo-2.0.dev1-py3-none-any.whl", "demo-1.0-py3-none-any.whl",
    ],
  )
  assert_eq(
    filenames_of(
      resolve_candidates(
        mixed,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
        prereleases=Some(false),
      ),
    ),
    ["demo-1.0-py3-none-any.whl"],
  )
  // Only prereleases available: the automatic rule falls back to them.
  let only_pre : Array[IndexFile] = [
    wheel_file("demo-2.0rc1-py3-none-any.whl", None),
    wheel_file("demo-2.0.dev1-py3-none-any.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        only_pre,
        resolve_requirement_of("demo"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-2.0rc1-py3-none-any.whl", "demo-2.0.dev1-py3-none-any.whl"],
  )
  // A specifier that is itself a prerelease admits prereleases, per PEP 440.
  let pinned : Array[IndexFile] = [
    wheel_file("demo-2.0rc1-py3-none-any.whl", None),
    wheel_file("demo-1.0-py3-none-any.whl", None),
  ]
  assert_eq(
    filenames_of(
      resolve_candidates(
        pinned,
        resolve_requirement_of("demo>=2.0rc1"),
        generic_tags(),
        None,
      ),
    ),
    ["demo-2.0rc1-py3-none-any.whl"],
  )
  // `explain_rejection` reports the policy as its own reason, and with
  // `prereleases = Some(true)` that reason cannot occur.
  assert_eq(
    explain_rejection(
      mixed,
      resolve_requirement_of("demo"),
      generic_tags(),
      None,
    ),
    [
      ("demo-2.0rc1-py3-none-any.whl", "prerelease"),
      ("demo-2.0.dev1-py3-none-any.whl", "prerelease"),
    ],
  )
  assert_eq(
    explain_rejection(
      mixed,
      resolve_requirement_of("demo"),
      generic_tags(),
      None,
      prereleases=Some(true),
    ),
    [],
  )
}

///|
/// `select_best` is the head of `resolve_candidates`, and `None` when nothing
/// qualifies -- including when the requirement names a different project.
test "resolver: select_best returns the head, or None" {
  let files = reason_files()
  let best = select_best(
    files,
    resolve_requirement_of("demo"),
    cp312_tags(),
    Some(resolve_version_of("3.12.4")),
  )
  assert_eq(best.unwrap().filename, "demo-3.0-py3-none-any.whl")
  let none = select_best(
    files,
    resolve_requirement_of("missing"),
    cp312_tags(),
    Some(resolve_version_of("3.12.4")),
  )
  assert_true(none is None)
  // The same answer as taking the head of the ordered candidate list.
  let candidates = resolve_candidates(
    files,
    resolve_requirement_of("demo"),
    cp312_tags(),
    Some(resolve_version_of("3.12.4")),
  )
  assert_eq(candidates[0].filename, best.unwrap().filename)
  // An exact pin that only a prerelease satisfies still resolves.
  let pinned : Array[IndexFile] = [
    wheel_file("demo-2.0rc1-py3-none-any.whl", None),
    wheel_file("demo-1.0-py3-none-any.whl", None),
  ]
  assert_eq(
    select_best(
      pinned,
      resolve_requirement_of("demo==2.0rc1"),
      generic_tags(),
      None,
    ).unwrap().filename,
    "demo-2.0rc1-py3-none-any.whl",
  )
}

///|
/// `explain_rejection` maps each rejected file to the first rule that failed and
/// reports the five stable reason strings a CLI prints. With an empty tag list
/// every wheel fails, so this one block exercises all five reasons at once; the
/// expected list is the documented rule order, not merely the set of reasons.
test "resolver: explain_rejection reports every reason with a stable code" {
  let files = reason_files()
  let requirement = resolve_requirement_of("demo>=2.0")
  let python = Some(resolve_version_of("3.9.18"))
  assert_eq(explain_rejection(files, requirement, [], python), [
    ("demo-1.0-py3-none-any.whl", "version"),
    ("demo-2.0-py3-none-any.whl", "requires-python"),
    ("demo-3.0rc1-py3-none-any.whl", "prerelease"),
    ("demo-3.0-py3-none-any.whl", "tags"),
    ("other-1.0-py3-none-any.whl", "name"),
    ("demo-2.0-cp39-cp39-win_amd64.whl", "tags"),
  ])
  // Only the sdist survives an empty tag list.
  assert_eq(filenames_of(resolve_candidates(files, requirement, [], python)), [
    "demo-2.0.tar.gz",
  ])
  // The first rule wins: a file failing both name and version is "name", and
  // one failing both version and tags is "version".
  let both : Array[IndexFile] = [
    wheel_file("other-0.1-cp39-cp39-win_amd64.whl", Some(">=9")),
  ]
  assert_eq(explain_rejection(both, requirement, [], python), [
    ("other-0.1-cp39-cp39-win_amd64.whl", "name"),
  ])
  assert_eq(
    explain_rejection(both, resolve_requirement_of("other>=99"), [], python),
    [("other-0.1-cp39-cp39-win_amd64.whl", "version")],
  )
  // With the tags available, the two wheels that only failed on tags are
  // ordered by version instead, and their reason disappears.
  let with_tags = explain_rejection(files, requirement, cp312_tags(), python)
  assert_eq(with_tags, [
    ("demo-1.0-py3-none-any.whl", "version"),
    ("demo-2.0-py3-none-any.whl", "requires-python"),
    ("demo-3.0rc1-py3-none-any.whl", "prerelease"),
    ("other-1.0-py3-none-any.whl", "name"),
    ("demo-2.0-cp39-cp39-win_amd64.whl", "tags"),
  ])
}

///|
/// `explain_rejection` and `resolve_candidates` describe the same partition of
/// the input: every file is either kept or explained, never both and never
/// neither, and the kept order is what the ordering rules predict.
test "resolver: explain_rejection agrees with resolve_candidates" {
  let files = reason_files()
  let requirement = resolve_requirement_of("demo>=2.0")
  let python = Some(resolve_version_of("3.12.4"))
  let kept = resolve_candidates(files, requirement, generic_tags(), python)
  let dropped = explain_rejection(files, requirement, generic_tags(), python)
  assert_eq(kept.length() + dropped.length(), files.length())
  for i = 0; i < kept.length(); i = i + 1 {
    assert_false(has_reason(dropped, kept[i].filename))
  }
  for i = 0; i < dropped.length(); i = i + 1 {
    assert_false(has_filename(kept, dropped[i].0))
  }
  assert_eq(filenames_of(kept), [
    "demo-3.0-py3-none-any.whl", "demo-2.0-py3-none-any.whl", "demo-2.0.tar.gz",
  ])
}
