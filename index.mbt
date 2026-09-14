// index.mbt -- an offline package-index reader and candidate resolver.
//
// Layers: `parse_json` (a strict RFC 8259 reader) -> `SimpleIndex::parse`
// (PEP 691 simple-API responses) -> `LocalIndex::scan` (a directory of files,
// no network at all) -> `resolve_candidates` / `select_best` /
// `explain_rejection`.
//
// `moonbitlang/core` on the pinned toolchain has no filesystem package, so the
// directory listing is injected; see `DirectoryLister` and `LocalIndex::scan`.

// --- 1. JSON (RFC 8259) ----------------------------------------------------

///|
/// Maximum container nesting accepted by `parse_json`. RFC 8259 has no limit;
/// this bound keeps the recursion of the reader finite on every backend.
/// A document nested exactly this deep is accepted, one level more raises
/// `JSON_DEPTH`.
const JSON_MAX_DEPTH : Int = 128

///|
/// A JSON value. `JsonNumber` keeps the **source text** of the number, so
/// `"1.40"` and `"1.4e0"` stay distinct and nothing here depends on
/// floating-point formatting or precision. `JsonObject` keeps document order.
pub(all) enum JsonValue {
  JsonNull
  JsonBool(Bool)
  JsonNumber(String)
  JsonString(String)
  JsonArray(Array[JsonValue])
  JsonObject(Array[(String, JsonValue)])
} derive(Eq, @debug.Debug)

///|
/// The member named `key` of a `JsonObject`, or `None`. The answer is
/// unambiguous because `parse_json` rejects duplicate names.
pub fn JsonValue::field(self : JsonValue, key : String) -> JsonValue? {
  match self {
    JsonObject(members) => {
      let mut found : JsonValue? = None
      for i = 0; i < members.length(); i = i + 1 {
        if members[i].0 == key {
          found = Some(members[i].1)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// An `InvalidIndex` error whose position is the UTF-16 code unit offset of
/// the character at `index`, the offset convention of `version.mbt`.
fn json_error(code : String, chars : Array[Char], index : Int) -> VersionError {
  let stop = if index < chars.length() { index } else { chars.length() }
  let mut offset = 0
  for i = 0; i < stop; i = i + 1 {
    offset = offset + chars[i].utf16_len()
  }
  VersionError::InvalidIndex(code, offset)
}

///|
/// RFC 8259 §2: the only four insignificant whitespace characters.
fn is_json_space(c : Char) -> Bool {
  let code = c.to_int()
  code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D
}

///|
/// Offset of the first non-whitespace character at or after `start`.
fn skip_json_space(chars : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < chars.length() && is_json_space(chars[i]) {
    i = i + 1
  }
  i
}

///|
/// Offset just past the run of ASCII digits beginning at `start`.
fn skip_json_digits(chars : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < chars.length() && chars[i].is_ascii_digit() {
    i = i + 1
  }
  i
}

///|
/// The code unit denoted by the four hex digits at `start` (RFC 8259 `\uXXXX`).
fn read_hex4(chars : Array[Char], start : Int) -> Int raise VersionError {
  if start + 4 > chars.length() {
    raise json_error("JSON_BAD_UNICODE", chars, start)
  }
  for i = start; i < start + 4; i = i + 1 {
    if !chars[i].is_ascii_hexdigit() {
      raise json_error("JSON_BAD_UNICODE", chars, i)
    }
  }
  let text = String::from_array(chars[start:start + 4])
  @string.parse_int(text, base=16) catch {
    _ => raise json_error("JSON_BAD_UNICODE", chars, start)
  }
}

///|
/// The single character denoted by one of the seven two-character JSON escapes,
/// or `None` for any other escape character (including `u`).
fn simple_escape(c : Char) -> Char? {
  match c {
    '"' => Some('"')
    '\\' => Some('\\')
    '/' => Some('/')
    'b' => Some(Int::unsafe_to_char(0x08))
    'f' => Some(Int::unsafe_to_char(0x0C))
    'n' => Some('\n')
    'r' => Some('\r')
    't' => Some('\t')
    _ => None
  }
}

///|
/// True when `chars` at `start` spells `word` exactly (RFC 8259 literals are
/// case sensitive).
fn matches_keyword(chars : Array[Char], start : Int, word : String) -> Bool {
  let expected = word.to_array()
  if start + expected.length() > chars.length() {
    return false
  }
  for i = 0; i < expected.length(); i = i + 1 {
    if chars[start + i] != expected[i] {
      return false
    }
  }
  true
}

///|
/// Parse a string, with `start` on the opening quote.
///
/// Handles the seven two-character escapes and `\uXXXX`, combining a correctly
/// ordered surrogate escape pair into the code point it denotes. A MoonBit
/// `Char` is a Unicode scalar value, so a lone surrogate cannot be represented
/// and is rejected rather than replaced.
fn parse_json_string(
  chars : Array[Char],
  start : Int,
) -> (String, Int) raise VersionError {
  let out : Array[Char] = []
  let mut i = start + 1
  while true {
    if i >= chars.length() {
      raise json_error("JSON_UNTERMINATED", chars, i)
    }
    let c = chars[i]
    if c == '"' {
      i = i + 1
      break
    }
    if c != '\\' {
      // RFC 8259 §7 escapes U+0000..U+001F but leaves U+007F legal raw, so
      // `is_ascii_control` would be too strict here.
      if c.to_int() < 0x20 {
        raise json_error("JSON_CONTROL_CHAR", chars, i)
      }
      out.push(c)
      i = i + 1
      continue
    }
    i = i + 1
    if i >= chars.length() {
      raise json_error("JSON_UNTERMINATED", chars, i)
    }
    let escape = chars[i]
    i = i + 1
    match simple_escape(escape) {
      Some(decoded) => {
        out.push(decoded)
        continue
      }
      None => ()
    }
    if escape != 'u' {
      raise json_error("JSON_BAD_ESCAPE", chars, i - 1)
    }
    let high = read_hex4(chars, i)
    i = i + 4
    if high >= 0xD800 && high <= 0xDBFF {
      // RFC 8259 §7: the low half must follow immediately.
      if i + 1 >= chars.length() || chars[i] != '\\' || chars[i + 1] != 'u' {
        raise json_error("JSON_LONE_SURROGATE", chars, i)
      }
      let low = read_hex4(chars, i + 2)
      if low < 0xDC00 || low > 0xDFFF {
        raise json_error("JSON_LONE_SURROGATE", chars, i)
      }
      i = i + 6
      out.push(
        Int::unsafe_to_char(0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)),
      )
    } else if high >= 0xDC00 && high <= 0xDFFF {
      raise json_error("JSON_LONE_SURROGATE", chars, i - 4)
    } else {
      out.push(Int::unsafe_to_char(high))
    }
  }
  (String::from_array(out), i)
}

///|
/// Parse a number, with `start` on `-` or the first digit, and return its
/// **source text** with the offset after it.
///
/// Implements the RFC 8259 §6 grammar exactly: no leading zero, no `.5`, no
/// `1.`, no `1e`, no leading `+`. `NaN` and `Infinity` are not numbers at all
/// and are rejected by `parse_json_value`.
fn parse_json_number(
  chars : Array[Char],
  start : Int,
) -> (String, Int) raise VersionError {
  let mut i = start
  if i < chars.length() && chars[i] == '-' {
    i = i + 1
  }
  if i >= chars.length() || !chars[i].is_ascii_digit() {
    raise json_error("JSON_BAD_NUMBER", chars, i)
  }
  if chars[i] == '0' {
    i = i + 1
    if i < chars.length() && chars[i].is_ascii_digit() {
      raise json_error("JSON_LEADING_ZERO", chars, i)
    }
  } else {
    i = skip_json_digits(chars, i)
  }
  if i < chars.length() && chars[i] == '.' {
    let after = skip_json_digits(chars, i + 1)
    if after == i + 1 {
      raise json_error("JSON_BAD_NUMBER", chars, after)
    }
    i = after
  }
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    let mut j = i + 1
    if j < chars.length() && (chars[j] == '+' || chars[j] == '-') {
      j = j + 1
    }
    let after = skip_json_digits(chars, j)
    if after == j {
      raise json_error("JSON_BAD_NUMBER", chars, after)
    }
    i = after
  }
  (String::from_array(chars[start:i]), i)
}

///|
/// Parse an object, with `start` on the opening brace.
fn parse_json_object(
  chars : Array[Char],
  start : Int,
  depth : Int,
) -> (JsonValue, Int) raise VersionError {
  let members : Array[(String, JsonValue)] = []
  let mut i = skip_json_space(chars, start + 1)
  let mut finished = false
  if i < chars.length() && chars[i] == '}' {
    finished = true
    i = i + 1
  }
  while !finished {
    if i >= chars.length() {
      raise json_error("JSON_UNTERMINATED", chars, i)
    }
    if chars[i] != '"' {
      raise json_error("JSON_EXPECT_KEY", chars, i)
    }
    let (key, after_key) = parse_json_string(chars, i)
    i = skip_json_space(chars, after_key)
    if i >= chars.length() || chars[i] != ':' {
      raise json_error("JSON_EXPECT_COLON", chars, i)
    }
    let (value, after_value) = parse_json_value(
      chars,
      skip_json_space(chars, i + 1),
      depth + 1,
    )
    for j = 0; j < members.length(); j = j + 1 {
      if members[j].0 == key {
        raise json_error("JSON_DUPLICATE_KEY", chars, i)
      }
    }
    members.push((key, value))
    i = skip_json_space(chars, after_value)
    if i < chars.length() && chars[i] == ',' {
      i = skip_json_space(chars, i + 1)
    } else if i < chars.length() && chars[i] == '}' {
      finished = true
      i = i + 1
    } else {
      raise json_error("JSON_EXPECT_COMMA", chars, i)
    }
  }
  (JsonObject(members), i)
}

///|
/// Parse an array, with `start` on the opening bracket.
fn parse_json_array(
  chars : Array[Char],
  start : Int,
  depth : Int,
) -> (JsonValue, Int) raise VersionError {
  let items : Array[JsonValue] = []
  let mut i = skip_json_space(chars, start + 1)
  let mut finished = false
  if i < chars.length() && chars[i] == ']' {
    finished = true
    i = i + 1
  }
  while !finished {
    if i >= chars.length() {
      raise json_error("JSON_UNTERMINATED", chars, i)
    }
    let (value, after_value) = parse_json_value(chars, i, depth + 1)
    items.push(value)
    i = skip_json_space(chars, after_value)
    if i < chars.length() && chars[i] == ',' {
      i = skip_json_space(chars, i + 1)
    } else if i < chars.length() && chars[i] == ']' {
      finished = true
      i = i + 1
    } else {
      raise json_error("JSON_EXPECT_COMMA", chars, i)
    }
  }
  (JsonArray(items), i)
}

///|
/// Parse one value, with `start` on its first character.
fn parse_json_value(
  chars : Array[Char],
  start : Int,
  depth : Int,
) -> (JsonValue, Int) raise VersionError {
  if depth > JSON_MAX_DEPTH {
    raise json_error("JSON_DEPTH", chars, start)
  }
  if start >= chars.length() {
    raise json_error("JSON_EOF", chars, start)
  }
  let c = chars[start]
  if c == '{' {
    parse_json_object(chars, start, depth)
  } else if c == '[' {
    parse_json_array(chars, start, depth)
  } else if c == '"' {
    let (text, next) = parse_json_string(chars, start)
    (JsonString(text), next)
  } else if c == '-' || c.is_ascii_digit() {
    let (text, next) = parse_json_number(chars, start)
    (JsonNumber(text), next)
  } else if c.is_ascii_alphabetic() {
    if matches_keyword(chars, start, "true") {
      (JsonBool(true), start + 4)
    } else if matches_keyword(chars, start, "false") {
      (JsonBool(false), start + 5)
    } else if matches_keyword(chars, start, "null") {
      (JsonNull, start + 4)
    } else {
      // `NaN`, `Infinity`, `undefined` and every other bare word land here.
      raise json_error("JSON_BAD_LITERAL", chars, start)
    }
  } else {
    raise json_error("JSON_UNEXPECTED_CHAR", chars, start)
  }
}

///|
/// Parse one complete RFC 8259 JSON text.
///
/// **Exactly which rules are enforced**; the reader accepts a subset of JSON
/// and never guesses.
///
/// * §2: the only insignificant whitespace is space, tab, LF and CR.
/// * §2/§3: a document is exactly one value, optionally surrounded by
///   whitespace; anything else is `JSON_TRAILING`.
/// * §4: a member name must be a string, `,` and `:` are mandatory, no trailing
///   comma. RFC 8259 says names *SHOULD* be unique; this reader makes that
///   *MUST* and raises `JSON_DUPLICATE_KEY`, because a PEP 691 consumer must
///   never see a shadowed `url` or `hashes`. Members keep document order.
/// * §6: the full grammar `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE][+-]?[0-9]+)?`.
///   A leading zero is `JSON_LEADING_ZERO`; a missing integer part (`.5`), a
///   missing fraction (`1.`) or a missing exponent (`1e`) is `JSON_BAD_NUMBER`.
///   A number is *not* converted to a numeric type -- `JsonNumber` carries the
///   source text -- so no precision or formatting is lost and there is no
///   range limit here; a caller that needs an `Int` parses it itself.
/// * §7: double quotes only; U+0000..U+001F must be escaped
///   (`JSON_CONTROL_CHAR`); the escapes are `\" \\ \/ \b \f \n \r \t` and
///   `\uXXXX` (`JSON_BAD_ESCAPE`); `\u` needs four hex digits
///   (`JSON_BAD_UNICODE`); a surrogate pair must be high-then-low with both
///   halves present, else `JSON_LONE_SURROGATE` (§8.2 permits lone surrogates
///   in the grammar; a MoonBit `Char` cannot hold one).
/// * §8: no `NaN`, `Infinity` or `-Infinity` and no other bare word -- a value
///   starting with an ASCII letter must be `true`, `false` or `null`, else
///   `JSON_BAD_LITERAL`; any other character that cannot start a value is
///   `JSON_UNEXPECTED_CHAR`.
/// * Unterminated input and a missing `,`/`:`/member name are
///   `JSON_UNTERMINATED`, `JSON_EOF`, `JSON_EXPECT_COMMA`, `JSON_EXPECT_COLON`
///   or `JSON_EXPECT_KEY`.
/// * Deliberate additions and omissions: a leading byte order mark is *not*
///   skipped (§8.1 only permits ignoring it, so U+FEFF is
///   `JSON_UNEXPECTED_CHAR`); no Unicode normalization; and nesting is capped
///   at `JSON_MAX_DEPTH` (`JSON_DEPTH`), which RFC 8259 does not require but
///   which bounds the recursion of this reader.
///
/// Codes are `VersionError::InvalidIndex(code, offset)`, where `offset` counts
/// UTF-16 code units of `text`.
pub fn parse_json(text : String) -> JsonValue raise VersionError {
  let chars = text.to_array()
  let (value, after) = parse_json_value(chars, skip_json_space(chars, 0), 0)
  let end = skip_json_space(chars, after)
  if end != chars.length() {
    raise json_error("JSON_TRAILING", chars, end)
  }
  value
}

// --- 2. PEP 691 simple-repository JSON -------------------------------------

///|
/// PEP 592 yank state of one file. PEP 592 lets `yanked` be a boolean or a
/// string; `Yanked("")` is "yanked with no reason", which is what `true` means
/// and the two spellings are deliberately collapsed, since PEP 592 gives the
/// boolean no other meaning.
pub(all) enum SimpleYanked {
  NotYanked
  Yanked(String)
} derive(Eq, @debug.Debug)

///|
/// One `files[]` entry of a PEP 691 response. `hashes` keeps document order and
/// may be empty (the member is required, its contents are not); `url` is
/// carried through verbatim, resolving it against the index root is the
/// caller's job. Members this module does not model -- including PEP 658's
/// `dist-info-metadata`/`core-metadata` -- are ignored, as PEP 691 requires of
/// clients.
pub(all) struct SimpleIndexFile {
  filename : String
  url : String
  hashes : Array[(String, String)]
  requires_python : String?
  yanked : SimpleYanked
  size : Int?
  upload_time : String?
} derive(Eq, @debug.Debug)

///|
/// The digest advertised for `algorithm` (for example `"sha256"`), or `None`.
/// Names are compared verbatim: PEP 691 does not normalize them.
pub fn SimpleIndexFile::hash_for(
  self : SimpleIndexFile,
  algorithm : String,
) -> String? {
  let mut found : String? = None
  for i = 0; i < self.hashes.length(); i = i + 1 {
    if self.hashes[i].0 == algorithm {
      found = Some(self.hashes[i].1)
    }
  }
  found
}

///|
/// A parsed PEP 691 "simple repository API" document. The fields are private;
/// read them through `SimpleIndex::name`, `SimpleIndex::api_version`,
/// `SimpleIndex::files` and `SimpleIndex::versions`.
pub struct SimpleIndex {
  name : String
  api_version : String?
  files : Array[SimpleIndexFile]
  versions : Array[String]
} derive(@debug.Debug)

///|
/// The `name` member, verbatim. PEP 691 lets the index choose the spelling, so
/// compare it with `canonicalize_name`.
pub fn SimpleIndex::name(self : SimpleIndex) -> String {
  self.name
}

///|
/// The PEP 691 `meta.api-version`, or `None` when `meta` or `api-version` is
/// absent. PEP 691 requires both, but the version only gates optional features,
/// so a missing one is reported as `None`; an ill-typed one is still rejected.
pub fn SimpleIndex::api_version(self : SimpleIndex) -> String? {
  self.api_version
}

///|
/// The `files` array, in document order.
pub fn SimpleIndex::files(self : SimpleIndex) -> Array[SimpleIndexFile] {
  self.files
}

///|
/// The PEP 700 `versions` array in document order, or `[]` when the index
/// publishes none.
pub fn SimpleIndex::versions(self : SimpleIndex) -> Array[String] {
  self.versions
}

///|
/// An `InvalidIndex` whose position is a *structural* index -- the ordinal of
/// the offending `files[]` entry, or `0` for a document-level problem -- not a
/// byte offset, which the JSON layer has already forgotten.
fn index_error(code : String, ordinal : Int) -> VersionError {
  VersionError::InvalidIndex(code, ordinal)
}

///|
/// A required string member of `value`: a missing member is `<code>`, a
/// member of another type is `<code>_TYPE`.
fn require_string(
  value : JsonValue,
  key : String,
  code : String,
  ordinal : Int,
) -> String raise VersionError {
  match value.field(key) {
    Some(JsonString(text)) => text
    Some(_) => raise index_error(code + "_TYPE", ordinal)
    None => raise index_error(code + "_MISSING", ordinal)
  }
}

///|
/// An optional string member. An explicit `null` counts as absent, which is how
/// real indexes spell "not applicable".
fn optional_string(
  value : JsonValue,
  key : String,
  code : String,
  ordinal : Int,
) -> String? raise VersionError {
  match value.field(key) {
    None | Some(JsonNull) => None
    Some(JsonString(text)) => Some(text)
    Some(_) => raise index_error(code, ordinal)
  }
}

///|
/// Parse one `files[]` entry; `ordinal` is used for every error it can
/// produce. PEP 691 requires `filename`, `url` and `hashes`, and allows
/// `size` as a non-negative byte count. The `size` text is validated instead of
/// being read as a `Double`, so the legal-JSON-but-meaningless `1.0` and `1e3`
/// are rejected rather than rounded. An empty `requires-python` (which PEP 691
/// permits) is normalized to `None`, giving the resolver one spelling of "no
/// constraint".
fn parse_simple_file(
  value : JsonValue,
  ordinal : Int,
) -> SimpleIndexFile raise VersionError {
  let hashes : Array[(String, String)] = []
  match value.field("hashes") {
    Some(JsonObject(members)) =>
      for i = 0; i < members.length(); i = i + 1 {
        match members[i].1 {
          JsonString(digest) => hashes.push((members[i].0, digest))
          _ => raise index_error("INDEX_BAD_HASH", ordinal)
        }
      }
    Some(_) => raise index_error("INDEX_BAD_HASHES", ordinal)
    None => raise index_error("INDEX_MISSING_HASHES", ordinal)
  }
  let size = match value.field("size") {
    None | Some(JsonNull) => None
    Some(JsonNumber(text)) =>
      if text.has_prefix("-") ||
        text.contains(".") ||
        text.contains("e") ||
        text.contains("E") {
        raise index_error("INDEX_BAD_SIZE", ordinal)
      } else {
        let count = @string.parse_int(text) catch {
          _ => raise index_error("INDEX_BAD_SIZE", ordinal)
        }
        Some(count)
      }
    Some(_) => raise index_error("INDEX_BAD_SIZE", ordinal)
  }
  {
    filename: require_string(value, "filename", "INDEX_FILENAME", ordinal),
    url: require_string(value, "url", "INDEX_URL", ordinal),
    hashes,
    requires_python: match
      optional_string(
        value, "requires-python", "INDEX_BAD_REQUIRES_PYTHON", ordinal,
      ) {
      Some(text) =>
        if text.trim().to_owned().is_empty() {
          None
        } else {
          Some(text)
        }
      None => None
    },
    yanked: match value.field("yanked") {
      None | Some(JsonBool(false)) => NotYanked
      Some(JsonBool(true)) => Yanked("")
      Some(JsonString(reason)) => Yanked(reason)
      Some(_) => raise index_error("INDEX_BAD_YANKED", ordinal)
    },
    size,
    upload_time: optional_string(
      value, "upload-time", "INDEX_BAD_UPLOAD_TIME", ordinal,
    ),
  }
}

///|
/// Parse a PEP 691 simple-repository JSON response.
///
/// PEP 691 requires `meta`, `name` and `files`; `versions` is the PEP 700
/// addition and optional. `meta` must be an object and `api-version` a string
/// when present; `name` must be a string; every `files[]` entry must carry
/// `filename`, `url` and `hashes`. Unknown members are ignored.
///
/// Errors are `VersionError::InvalidIndex(code, ordinal)`, where `ordinal` is
/// the offending `files[]` entry, or `0` for a document-level problem -- unlike
/// the JSON layer, which reports UTF-16 offsets.
pub fn SimpleIndex::parse(json : String) -> SimpleIndex raise VersionError {
  let root = parse_json(json)
  let meta = match root.field("meta") {
    None | Some(JsonNull) => None
    Some(meta) if meta is JsonObject(_) => Some(meta)
    Some(_) => raise index_error("INDEX_BAD_META", 0)
  }
  let files : Array[SimpleIndexFile] = []
  match root.field("files") {
    Some(JsonArray(items)) =>
      for i = 0; i < items.length(); i = i + 1 {
        files.push(parse_simple_file(items[i], i))
      }
    Some(_) => raise index_error("INDEX_BAD_FILES", 0)
    None => raise index_error("INDEX_MISSING_FILES", 0)
  }
  let versions : Array[String] = []
  match root.field("versions") {
    None | Some(JsonNull) => ()
    Some(JsonArray(items)) =>
      for i = 0; i < items.length(); i = i + 1 {
        match items[i] {
          JsonString(text) => versions.push(text)
          _ => raise index_error("INDEX_BAD_VERSIONS", i)
        }
      }
    Some(_) => raise index_error("INDEX_BAD_VERSIONS", 0)
  }
  {
    name: require_string(root, "name", "INDEX_NAME", 0),
    api_version: match meta {
      Some(meta) =>
        optional_string(meta, "api-version", "INDEX_BAD_API_VERSION", 0)
      None => None
    },
    files,
    versions,
  }
}

///|
/// Every `files[]` entry whose name is a valid wheel, in document order.
///
/// An index is *about* distributions, so an entry that is neither a wheel nor
/// an sdist is a defect: it raises `INDEX_UNKNOWN_DIST` (position = entry
/// ordinal) instead of being silently dropped. Entries that are valid sdists
/// are classified and skipped, not rejected.
pub fn SimpleIndex::wheels(
  self : SimpleIndex,
) -> Array[SimpleIndexFile] raise VersionError {
  let out : Array[SimpleIndexFile] = []
  for i = 0; i < self.files.length(); i = i + 1 {
    match distribution_kind(self.files[i].filename) {
      Some(WheelFile) => out.push(self.files[i])
      Some(SdistFile) => ()
      None => raise index_error("INDEX_UNKNOWN_DIST", i)
    }
  }
  out
}

///|
/// Every `files[]` entry whose name is a valid source distribution, in document
/// order, on the same "neither wheel nor sdist is an error" rule as
/// `SimpleIndex::wheels`.
pub fn SimpleIndex::sdists(
  self : SimpleIndex,
) -> Array[SimpleIndexFile] raise VersionError {
  let out : Array[SimpleIndexFile] = []
  for i = 0; i < self.files.length(); i = i + 1 {
    match distribution_kind(self.files[i].filename) {
      Some(SdistFile) => out.push(self.files[i])
      Some(WheelFile) => ()
      None => raise index_error("INDEX_UNKNOWN_DIST", i)
    }
  }
  out
}

// --- 3. Files, discovery and candidate resolution --------------------------

///|
/// Whether an `IndexFile` is a wheel or a source distribution.
pub(all) enum IndexFileKind {
  WheelFile
  SdistFile
} derive(Eq, @debug.Debug)

///|
/// One distribution file the resolver may consider.
///
/// `name` is already PEP 503 normalized, so it compares directly against
/// `canonicalize_name(requirement.name)`. `version` is the PEP 440 version
/// parsed out of the *file name*: the only version a listing carries. `path` is
/// wherever the file was found (a path for a scan, a URL for an index
/// response). `requires_python` is the PEP 345 / PEP 503 constraint when the
/// source knows it: a bare listing does not and leaves it `None`, while
/// `SimpleIndexFile::to_index_file` carries the JSON member over.
pub(all) struct IndexFile {
  filename : String
  path : String
  kind : IndexFileKind
  name : String
  version : Version
  requires_python : String?
} derive(Eq, @debug.Debug)

///|
/// The expanded PEP 425 tag set of a wheel, and the empty array for an sdist.
/// The tags come from `parse_wheel_filename`, so a compressed tag such as
/// `py2.py3-none-any` is expanded into its combinations. An `IndexFile` built
/// by hand around an unparseable wheel name has no tags, which the resolver
/// reads as "matches nothing".
pub fn IndexFile::tags(self : IndexFile) -> Array[String] {
  if self.kind is SdistFile {
    return []
  }
  match wheel_of(self.filename) {
    Some(wheel) => wheel.tags
    None => []
  }
}

///|
/// A parsed wheel filename, or `None` when the name is not a valid PEP 427
/// wheel name.
fn wheel_of(filename : String) -> WheelFilename? {
  Some(parse_wheel_filename(filename)) catch {
    _ => None
  }
}

///|
/// A parsed sdist filename, or `None` when the name is not a valid PEP 625
/// source distribution name.
fn sdist_of(filename : String) -> SdistFilename? {
  Some(parse_sdist_filename(filename)) catch {
    _ => None
  }
}

///|
/// The kind of a distribution filename, or `None` when it is not one at all.
/// Wheels are tried first; the two grammars cannot overlap because PEP 427 and
/// PEP 625 keep the `.whl` and `.tar.gz`/`.zip` extensions disjoint.
fn distribution_kind(filename : String) -> IndexFileKind? {
  if wheel_of(filename) is Some(_) {
    Some(WheelFile)
  } else if sdist_of(filename) is Some(_) {
    Some(SdistFile)
  } else {
    None
  }
}

///|
/// The `IndexFile` of a filename already known to be a distribution name;
/// re-parsing is what yields the normalized name and the parsed version.
fn make_index_file(
  filename : String,
  path : String,
  kind : IndexFileKind,
  requires_python : String?,
  ordinal : Int,
) -> IndexFile raise VersionError {
  let parsed = match kind {
    WheelFile =>
      match wheel_of(filename) {
        Some(wheel) => Some((wheel.name, wheel.version))
        None => None
      }
    SdistFile =>
      match sdist_of(filename) {
        Some(sdist) => Some((sdist.name, sdist.version))
        None => None
      }
  }
  match parsed {
    Some((name, version)) =>
      { filename, path, kind, name, version, requires_python, }
    None => raise index_error("INDEX_UNKNOWN_DIST", ordinal)
  }
}

///|
/// Join a directory and a file name with `/`, without doubling a separator the
/// caller already supplied. A Windows `\` is not special-cased: a path string
/// is opaque here, so such a caller should pass full paths to the lister.
fn join_path(directory : String, filename : String) -> String {
  if directory.is_empty() {
    filename
  } else if directory.has_suffix("/") {
    directory + filename
  } else {
    directory + "/" + filename
  }
}

///|
/// A function returning the *entry names* of a directory.
///
/// `moonbitlang/core` on the pinned toolchain has no filesystem package: there
/// is no `moonbitlang/core/fs`, and no `read_dir`/`readdir`/`list_dir` anywhere
/// in core, so this module cannot call one. A host that does have a filesystem
/// passes a function of this shape instead (a thin adapter around whatever
/// listing API that host can reach).
pub type DirectoryLister = (String) -> Array[String] raise VersionError

///|
/// The default `DirectoryLister`: it always raises
/// `InvalidIndex("INDEX_NO_FS", 0)`.
///
/// It exists so that `LocalIndex::scan` keeps the documented `scan(directory)`
/// shape even on a toolchain whose core cannot read a directory, and so that
/// the failure is explicit instead of an "empty index".
fn no_directory_lister(_directory : String) -> Array[String] raise VersionError {
  raise index_error("INDEX_NO_FS", 0)
}

///|
/// The distribution files of one directory.
pub(all) struct LocalIndex {
  /// The directory the files were found in, as given to `scan`.
  directory : String
  /// Every recognized distribution file, ordered by normalized name and then
  /// by file name, so a scan is reproducible across filesystems and platforms.
  files : Array[IndexFile]
} derive(@debug.Debug)

///|
/// List `directory` and index every file in it.
///
/// A file is indexed when its name parses as a PEP 427 wheel or a PEP 625
/// sdist; **every other file is ignored**, which includes READMEs, lock files
/// and any name the parsers reject. That is the opposite of the PEP 691 rule in
/// `SimpleIndex::wheels`, deliberately: an index document *claims* to list
/// distributions, while a directory is expected to hold anything.
///
/// Classification is by name only -- no `stat` is performed -- so a
/// subdirectory whose name looks like a distribution is indexed too. Only the
/// entries the lister returns are considered; this never recurses. The listing
/// comes from `lister` (`DirectoryLister`); the default raises `INDEX_NO_FS`
/// rather than pretending the directory is empty.
pub fn LocalIndex::scan(
  directory : String,
  lister? : DirectoryLister = no_directory_lister,
) -> LocalIndex raise VersionError {
  let entries = lister(directory)
  let files : Array[IndexFile] = []
  for i = 0; i < entries.length(); i = i + 1 {
    let entry = entries[i]
    match distribution_kind(entry) {
      Some(kind) =>
        files.push(
          make_index_file(entry, join_path(directory, entry), kind, None, i),
        )
      None => ()
    }
  }
  files.sort_by(fn(a, b) {
    let by_name = String::lexical_compare(a.name, b.name)
    if by_name != 0 {
      by_name
    } else {
      String::lexical_compare(a.filename, b.filename)
    }
  })
  { directory, files, }
}

///|
/// The distinct normalized package names in the index, sorted in code point
/// order with `String::lexical_compare`.
///
/// `Array::sort()` is never used on strings here: MoonBit's default ordering
/// for `String` compares length first, which is not the order a PEP 503
/// consumer expects.
pub fn LocalIndex::packages(self : LocalIndex) -> Array[String] {
  let names : Array[String] = []
  for i = 0; i < self.files.length(); i = i + 1 {
    if !names.contains(self.files[i].name) {
      names.push(self.files[i].name)
    }
  }
  names.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  names
}

///|
/// Every file of `name`, normalized with PEP 503 `canonicalize_name` before the
/// lookup, so `"Zope.Interface"` finds `zope-interface-6.0.zip`. An unknown
/// name yields an empty array.
pub fn LocalIndex::files_for(
  self : LocalIndex,
  name : String,
) -> Array[IndexFile] {
  let target = canonicalize_name(name)
  let out : Array[IndexFile] = []
  for i = 0; i < self.files.length(); i = i + 1 {
    if self.files[i].name == target {
      out.push(self.files[i])
    }
  }
  out
}

///|
/// True when `version` occurs in `versions` under PEP 440 comparison, which is
/// why `1.0` and `1.0.0` are one entry here.
fn in_versions(versions : Array[Version], version : Version) -> Bool {
  for i = 0; i < versions.length(); i = i + 1 {
    if Version::compare(versions[i], version) == 0 {
      return true
    }
  }
  false
}

///|
/// The versions that pass both the requirement's specifier set and its
/// prerelease policy, computed with `SpecifierSet::filter` over every
/// name-matching file at once, so that `resolve_candidates` and
/// `explain_rejection` can never disagree.
///
/// `SpecifierSet::filter` implements PEP 440's prerelease rule: with
/// `prereleases = None` the finals are returned when any final matches and the
/// prereleases only when none does; `Some(true)` admits prereleases and
/// `Some(false)` excludes them.
fn allowed_versions(
  files : Array[IndexFile],
  requirement : Requirement,
  prereleases : Bool?,
) -> Array[Version] {
  let want = canonicalize_name(requirement.name)
  let versions : Array[Version] = []
  for i = 0; i < files.length(); i = i + 1 {
    if files[i].name == want && !in_versions(versions, files[i].version) {
      versions.push(files[i].version)
    }
  }
  SpecifierSet::filter(versions, requirement.specifier, prereleases~)
}

///|
/// True when a file's `requires-python` constraint admits `python`.
///
/// Both sides must be known: PEP 503 lets an index omit `requires-python`, and
/// an offline planner that does not know its interpreter passes `None`, in
/// which case nothing is filtered. An *invalid* constraint is treated as no
/// constraint, which is what pip does: `check_requires_python` raises
/// `InvalidSpecifier` and its caller `_check_link_requires_python` logs
/// "Ignoring invalid Requires-Python" and returns `True`.
///
/// The comparison uses this module's `SpecifierSet::contains` default policy,
/// which admits a prerelease interpreter such as `3.13.0rc1` for `>=3.8` --
/// packaging 26.3's `Version("3.13.0rc1") in SpecifierSet(">=3.8")` is `True`
/// too, so a prerelease CPython is not filtered out.
fn requires_python_ok(file : IndexFile, python : Version?) -> Bool {
  match (file.requires_python, python) {
    (Some(text), Some(interpreter)) => {
      let trimmed = text.trim().to_owned()
      if trimmed.is_empty() {
        true
      } else {
        match (Some(SpecifierSet::parse(trimmed)) catch { _ => None }) {
          None => true
          Some(set) => set.contains(interpreter)
        }
      }
    }
    _ => true
  }
}

///|
/// The priority of a wheel's best tag: the smallest index in `supported` that
/// one of its PEP 425 tags occupies, or `supported.length()` when nothing
/// intersects. Lower is better, because `supported` is ordered
/// most-specific-first exactly like `packaging.tags.sys_tags()`. pip agrees:
/// `Wheel.find_most_preferred_tag` takes the *minimum* priority over the file's
/// tags, and `CandidateEvaluator._sort_key` negates it, so the smallest index
/// wins.
fn tag_priority(file : IndexFile, supported : Array[String]) -> Int {
  let file_tags = file.tags()
  let mut best = supported.length()
  for i = 0; i < file_tags.length(); i = i + 1 {
    for j = 0; j < supported.length(); j = j + 1 {
      if supported[j] == file_tags[i] && j < best {
        best = j
      }
    }
  }
  best
}

///|
/// The PEP 427 build tag of a wheel, or `None` for an sdist or an untagged
/// wheel.
fn build_tag_of(file : IndexFile) -> (Int, String)? {
  if file.kind is SdistFile {
    return None
  }
  match wheel_of(file.filename) {
    Some(wheel) => wheel.build
    None => None
  }
}

///|
/// Order two build tags, negative when `a` is preferred. pip sorts with `max()`
/// over a key whose build component is `(int, str)` for a tagged wheel and the
/// empty tuple otherwise, so a tagged wheel outranks an untagged one and a
/// larger build number outranks a smaller one; the string half compares
/// lexically, as `str` comparison does.
fn compare_build_tag(a : (Int, String)?, b : (Int, String)?) -> Int {
  match (a, b) {
    (None, None) => 0
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (Some((a_number, a_rest)), Some((b_number, b_rest))) =>
      if a_number != b_number {
        if a_number > b_number {
          -1
        } else {
          1
        }
      } else {
        -String::lexical_compare(a_rest, b_rest)
      }
  }
}

///|
/// Order two candidates best-first: negative when `a` comes before `b`.
///
/// 1. **Higher PEP 440 version first.** pip's `CandidateEvaluator._sort_key`
///    places `candidate.version` ahead of every tie-breaker below.
/// 2. **A wheel before an sdist of the same version.** pip reaches the same
///    result through the tag component of its key: a wheel scores
///    `-(index of its best supported tag)` and an sdist
///    `-(number of supported tags)`, and an index is always the smaller number.
/// 3. **For two wheels, the one with the more preferred tag first**, measured
///    as its smallest index in `supported` (`tag_priority`). That array is the
///    caller's ordered tag list -- pip's `sys_tags()` order, most specific
///    first for the running interpreter -- so with `[cp312-cp312-...,
///    cp312-abi3-..., py3-none-any]` the wheels rank in exactly that order.
/// 4. **A larger PEP 427 build number first**, then a larger build string, then
///    (pip leaves this undefined) **the filename in code point order**. The
///    last step is a deliberate addition: pip picks with `max()`, so two
///    candidates that tie may be resolved by server order, while a resolver
///    used to *write* lock files must be deterministic.
///
/// PEP 592 yank state is deliberately not considered: pip puts its yank flag
/// ahead of the version, so pip prefers an older unyanked file over a newer
/// yanked one, but `IndexFile` carries no yank field, and yank handling belongs
/// to the caller that reads `SimpleIndexFile::yanked`.
fn compare_candidates(
  a : IndexFile,
  b : IndexFile,
  supported : Array[String],
) -> Int {
  let by_version = Version::compare(a.version, b.version)
  if by_version != 0 {
    return -by_version
  }
  let a_is_wheel = a.kind is WheelFile
  let b_is_wheel = b.kind is WheelFile
  if a_is_wheel != b_is_wheel {
    return if a_is_wheel { -1 } else { 1 }
  }
  if a_is_wheel {
    let a_priority = tag_priority(a, supported)
    let b_priority = tag_priority(b, supported)
    if a_priority != b_priority {
      return if a_priority < b_priority { -1 } else { 1 }
    }
  }
  let by_build = compare_build_tag(build_tag_of(a), build_tag_of(b))
  if by_build != 0 {
    return by_build
  }
  String::lexical_compare(a.filename, b.filename)
}

///|
/// The first rule that rejects `file`, or `None` when it is a candidate.
///
/// The order is fixed and documented on `explain_rejection`; it is the single
/// source of truth for both that function and `resolve_candidates`.
fn rejection_reason(
  file : IndexFile,
  requirement : Requirement,
  tags : Array[String],
  python : Version?,
  allowed : Array[Version],
) -> String? {
  if file.name != canonicalize_name(requirement.name) {
    Some("name")
  } else if !requirement.specifier.contains(
      file.version,
      prereleases=Some(true),
    ) {
    Some("version")
  } else if !in_versions(allowed, file.version) {
    Some("prerelease")
  } else if !requires_python_ok(file, python) {
    Some("requires-python")
  } else if file.kind is WheelFile && tag_priority(file, tags) == tags.length() {
    Some("tags")
  } else {
    None
  }
}

///|
/// The files that could satisfy `requirement` on a machine described by `tags`
/// and `python`, best candidate first.
///
/// A file is kept when all four hold: its PEP 503 normalized name equals the
/// requirement's; its version passes `requirement.specifier` *and* PEP 440's
/// prerelease policy, evaluated over all name-matching files at once (so the
/// automatic policy means "prefer finals, fall back to prereleases", not "drop
/// every prerelease"); `requires-python` is satisfied whenever both sides know
/// it (`requires_python_ok`); and, for a wheel, its PEP 425 tags intersect
/// `tags` -- an sdist always passes, since PEP 425 applies to wheels only.
///
/// `tags` must be ordered most-specific-first, the order of
/// `packaging.tags.sys_tags()`: it is both the filter and the ranking of rule 3
/// in `compare_candidates`. `python` is the interpreter version or `None`.
/// `prereleases` overrides PEP 440's automatic policy as in
/// `SpecifierSet::filter`. The input array is not modified.
pub fn resolve_candidates(
  files : Array[IndexFile],
  requirement : Requirement,
  tags : Array[String],
  python : Version?,
  prereleases? : Bool? = None,
) -> Array[IndexFile] {
  let allowed = allowed_versions(files, requirement, prereleases)
  let out : Array[IndexFile] = []
  for i = 0; i < files.length(); i = i + 1 {
    if rejection_reason(files[i], requirement, tags, python, allowed) is None {
      out.push(files[i])
    }
  }
  out.sort_by(fn(a, b) { compare_candidates(a, b, tags) })
  out
}

///|
/// The single best candidate, or `None` when `resolve_candidates` is empty.
pub fn select_best(
  files : Array[IndexFile],
  requirement : Requirement,
  tags : Array[String],
  python : Version?,
  prereleases? : Bool? = None,
) -> IndexFile? {
  let candidates = resolve_candidates(
    files,
    requirement,
    tags,
    python,
    prereleases~,
  )
  if candidates.length() == 0 {
    None
  } else {
    Some(candidates[0])
  }
}

///|
/// Why each file was rejected, as `(filename, reason)` in input order, one
/// entry per rejected element.
///
/// The reason is the first rule that fails, in this fixed order, and these five
/// strings are stable API that a CLI prints verbatim:
///
/// * `"name"` -- a different project;
/// * `"version"` -- outside the specifier set even with prereleases allowed;
/// * `"prerelease"` -- in range, but dropped by the prerelease policy;
/// * `"requires-python"` -- the interpreter is excluded by the constraint;
/// * `"tags"` -- a wheel that cannot be installed on this platform.
///
/// A file that `resolve_candidates` would keep is never reported, so the two
/// functions describe the same partition of the input; the `"prerelease"` case
/// reuses `allowed_versions`, which is why they cannot drift apart.
/// `prereleases` has the same meaning as in `resolve_candidates`, so with
/// `Some(true)` the `"prerelease"` reason cannot occur.
pub fn explain_rejection(
  files : Array[IndexFile],
  requirement : Requirement,
  tags : Array[String],
  python : Version?,
  prereleases? : Bool? = None,
) -> Array[(String, String)] {
  let allowed = allowed_versions(files, requirement, prereleases)
  let out : Array[(String, String)] = []
  for i = 0; i < files.length(); i = i + 1 {
    match rejection_reason(files[i], requirement, tags, python, allowed) {
      Some(reason) => out.push((files[i].filename, reason))
      None => ()
    }
  }
  out
}

///|
/// The `IndexFile` of an index entry, with `path` set to the entry's `url`.
/// An entry that is neither a wheel nor an sdist raises `INDEX_UNKNOWN_DIST`,
/// mirroring `SimpleIndex::wheels`.
pub fn SimpleIndexFile::to_index_file(
  self : SimpleIndexFile,
) -> IndexFile raise VersionError {
  match distribution_kind(self.filename) {
    Some(kind) =>
      make_index_file(self.filename, self.url, kind, self.requires_python, 0)
    None => raise index_error("INDEX_UNKNOWN_DIST", 0)
  }
}
