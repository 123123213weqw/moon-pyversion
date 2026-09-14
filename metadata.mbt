///|
/// Core metadata: the `METADATA` file inside a wheel's `.dist-info` directory
/// and the `PKG-INFO` file inside a source distribution.
///
/// A metadata file is RFC 822 style headers, a blank line, then the description
/// body:
///
/// ```text
/// Metadata-Version: 2.4
/// Name: demo
/// Version: 1.0
///
/// Long description.
/// ```
///
/// The rules implemented here are those of the core metadata specification
/// (PEP 566, as amended by PEP 621, 639, 643, 685 and 753). The specification has
/// no machine-readable schema, so the same rules are restated in
/// `packaging.metadata.Metadata`; the semantics of this file were checked against
/// PyPA `packaging` 26.3 on a corpus of documents, and the differential run is
/// reported together with this file.
///
/// The parser is strict on purpose: a document that an unknown field, a version
/// gate or a value rule rejects is not usable metadata, and silently ignoring a
/// broken field is how broken distributions reach an index. Every rejection is a
/// `VersionError::InvalidMetadata(code, offset)`, where `code` is a stable
/// upper-snake-case string and `offset` is the character offset of the offending
/// field (0 when the document as a whole is at fault). The rule to code mapping
/// is:
///
/// | rule | code |
/// | --- | --- |
/// | 1 `Metadata-Version` | `METADATA_VERSION_REQUIRED`, `METADATA_VERSION_INVALID` |
/// | 2 `Name` / `Version` | `NAME_REQUIRED`, `VERSION_REQUIRED` |
/// | 3 `Name` syntax | `NAME_INVALID` |
/// | 4 `Version` syntax | `VERSION_INVALID` |
/// | 5 `Requires-Python` | `REQUIRES_PYTHON_INVALID` |
/// | 6 `Requires-Dist` | `REQUIRES_DIST_INVALID` |
/// | 7 `Provides-Extra` | `PROVIDES_EXTRA_INVALID` |
/// | 8 `License-Expression` | `LICENSE_EXPRESSION_INVALID`, `LICENSE_EXPRESSION_CONFLICT` |
/// | 9 version gate | `FIELD_NOT_IN_METADATA_VERSION`, `UNKNOWN_FIELD`, `EXTRA_MARKER_NOT_IN_METADATA_VERSION` |
/// | 10 repeated single-use fields | `DUPLICATE_HEADER` |
/// | 11 `Author-email` / `Maintainer-email` | parsed, not enforced: see the note below |
/// | 12 `Project-URL` | `PROJECT_URL_INVALID`, `PROJECT_URL_DUPLICATE_LABEL` |
/// | 13 `Description-Content-Type` | `DESCRIPTION_CONTENT_TYPE_INVALID` |
/// | `Summary` | `SUMMARY_MULTILINE` |
/// | `License-File` | the codes of `canonicalize_license_file` |
/// | `Dynamic` | `DYNAMIC_INVALID` |
///
/// Where this file deliberately differs from `packaging` 26.3 or from a literal
/// reading of the PEPs — each difference is also marked at the code that
/// implements it:
///
/// - A folded header is unfolded to a single space (RFC 5322 §2.2.3), so
///   `Summary: a` followed by ` b` is the one-line summary `a b`. `packaging`
///   reads with the `compat32` email policy, which keeps the fold, and so rejects
///   a folded `Summary` outright.
/// - A `Description` header wins over a description carried in the body, where
///   `packaging` puts both into its unparsed pile and rejects the document.
/// - `Dynamic`, `License-Expression` and `License-File` are gated at 2.4; PEP 643
///   introduced `Dynamic` in 2.2 and `packaging` gates it there.
/// - `Import-Name` and `Import-Namespace` exist in `packaging` 26.3 at metadata
///   2.5, and this file accepts at most 2.4, so they can never be used.
/// - `Description-Content-Type` only has to be a well formed `type/subtype` with
///   optional parameters, while `packaging` restricts it to `text/plain`,
///   `text/x-rst` and `text/markdown` with a UTF-8 charset and a known Markdown
///   variant.
/// - `Author-email` and `Maintainer-email` are *parsed* into `(name, address)`
///   pairs here, while `packaging` stores the string untouched. A list that does
///   not parse is reported by `Metadata::diagnostics` instead of failing the
///   document: real `METADATA` files carry `Author-email: UNKNOWN` (setuptools)
///   and empty values, and an optional field must not make a document unusable.
///   An empty value counts as absent, so `Author-email: ` is the same as no
///   `Author-email`. PEP 639's
///   "`License-Expression` forbids `License` and `License ::` classifiers" rule is
///   implemented here but not in `packaging` 26.3 at all.

///|
/// The number of entries of the core metadata version order this reader accepts
/// (rule 1): `1.0 1.1 1.2 2.1 2.2 2.3 2.4`. The later versions stay in the order
/// so a field introduced by one of them can still be ranked, but a document
/// declaring one is rejected.
const ACCEPTED_METADATA_VERSION_RANK : Int = 7

///|
/// The rank of the metadata version that first allowed `Provides-Extra` and the
/// `extra` marker variable (2.1), used by the last clause of rule 9.
const EXTRA_SUPPORT_VERSION_RANK : Int = 3

///|
/// Rank of a `Metadata-Version` in the core metadata ordering: `1.0`→0 `1.1`→1
/// `1.2`→2 `2.1`→3 `2.2`→4 `2.3`→5 `2.4`→6 `2.5`→7 `2.6`→8. `None` for anything
/// else, including the 2.0 that PEP 426 never released.
fn version_rank(version : String) -> Int? {
  match version {
    "1.0" => Some(0)
    "1.1" => Some(1)
    "1.2" => Some(2)
    "2.1" => Some(3)
    "2.2" => Some(4)
    "2.3" => Some(5)
    "2.4" => Some(6)
    "2.5" => Some(7)
    "2.6" => Some(8)
    _ => None
  }
}

///|
/// The gate table of rule 9: the metadata version that introduced a field, or
/// `None` when the name is not a core metadata field at all (which is
/// `UNKNOWN_FIELD`). Fields are grouped by the version that added them, which is
/// the way PEP 241/314/345/566/639/794 present them.
///
/// `Dynamic` is listed under 2.4 although PEP 643 introduced it in 2.2, because
/// rule 9 groups it with the two PEP 639 fields. `Import-Name` and
/// `Import-Namespace` are 2.5, which no accepted document may declare, so a
/// document that uses them is always rejected.
///
/// The three deprecated 1.1 fields (`Requires`, `Provides`, `Obsoletes`) are part
/// of the vocabulary because the specification recognises them and the reference
/// implementation accepts them; leaving them out would turn a legal 1.1 document
/// into an `UNKNOWN_FIELD` rejection.
fn field_added_version(key : String) -> String? {
  match key {
    "metadata-version"
    | "name"
    | "version"
    | "platform"
    | "summary"
    | "description"
    | "keywords"
    | "home-page"
    | "author"
    | "author-email"
    | "license" => Some("1.0")
    "supported-platform"
    | "download-url"
    | "classifier"
    | "requires"
    | "provides"
    | "obsoletes" => Some("1.1")
    "maintainer"
    | "maintainer-email"
    | "requires-dist"
    | "provides-dist"
    | "obsoletes-dist"
    | "requires-python"
    | "requires-external"
    | "project-url" => Some("1.2")
    "description-content-type" | "provides-extra" => Some("2.1")
    "license-expression" | "license-file" | "dynamic" => Some("2.4")
    "import-name" | "import-namespace" => Some("2.5")
    _ => None
  }
}

///|
/// Rule 10: the multi-use fields — `Classifier`, `Requires-Dist`,
/// `Requires-External`, `Project-URL`, `Provides-Extra`, `Provides-Dist`,
/// `Obsoletes-Dist`, `Dynamic`, `Platform`, `License-File`,
/// `Supported-Platform`, `Import-Name`, `Import-Namespace` and the three
/// deprecated 1.1 list fields — and `false` for every single-use field, whose
/// repetition is `DUPLICATE_HEADER`.
fn is_multi_use(key : String) -> Bool {
  key == "classifier" ||
  key == "requires-dist" ||
  key == "requires-external" ||
  key == "project-url" ||
  key == "provides-extra" ||
  key == "provides-dist" ||
  key == "obsoletes-dist" ||
  key == "dynamic" ||
  key == "platform" ||
  key == "license-file" ||
  key == "supported-platform" ||
  key == "import-name" ||
  key == "import-namespace" ||
  key == "requires" ||
  key == "provides" ||
  key == "obsoletes"
}

///|
/// `text` with its first character upper-cased; field names are ASCII.
fn capitalize(text : String) -> String {
  if text.is_empty() {
    text
  } else {
    text[0:1].to_owned().to_upper() + text[1:].to_owned()
  }
}

///|
/// The canonical spelling of a field name, which is what `Metadata::to_string`
/// emits: header names are compared case-insensitively on input, so a field is
/// stored under its lower-case name and capitalised per `-` separated segment on
/// output. The two URL fields are the only places where that rule needs help
/// (`url` is an initialism in `Download-URL` and `Project-URL`).
fn canonical_field_name(key : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for segment in key.split("-") {
    if !first {
      out.write_string("-")
    }
    first = false
    let text = segment.to_owned()
    out.write_string(if text == "url" { "URL" } else { capitalize(text) })
  }
  out.to_string()
}

///|
/// One logical header: the lower-cased field name, the unfolded value and the
/// character offset of the line it starts on.
priv struct Header {
  key : String
  value : String
  offset : Int
}

///|
/// True for the whitespace RFC 5322 uses to fold a header.
fn is_wsp(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// ASCII alphanumeric: the character class the PEP 508 name rule is built from.
fn is_ascii_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
/// True when `c` ends a line. Only CRLF, CR and LF do, which is what the RFC 822
/// reader in `packaging` accepts (`email.feedparser`'s `NLCRE`). The exotic
/// boundaries of Python's `str.splitlines` are deliberately not line endings
/// here, because an RFC 822 header value may legitimately contain them.
fn is_line_break(c : Char) -> Bool {
  c == '\n' || c == '\r'
}

///|
/// True when `c` may appear in a header field name: printable ASCII except space
/// and `:`, the `[\041-\071\073-\176]` class of RFC 5322 §2.2.
fn is_header_name_char(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 33 && code <= 57) || (code >= 59 && code <= 126)
}

///|
/// True when every character of `chars[from:to]` may appear in a field name.
fn is_header_name(chars : Array[Char], from : Int, to : Int) -> Bool {
  for i = from; i < to; i = i + 1 {
    if !is_header_name_char(chars[i]) {
      return false
    }
  }
  true
}

///|
/// The first index of `needle` in `chars[from:to]`, or `-1`.
fn find_char(chars : Array[Char], from : Int, to : Int, needle : Char) -> Int {
  for i = from; i < to; i = i + 1 {
    if chars[i] == needle {
      return i
    }
  }
  -1
}

///|
/// `text` with leading and trailing spaces and tabs removed.
fn trim_wsp(text : String) -> String {
  let chars = text.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && is_wsp(chars[start]) {
    start = start + 1
  }
  while end > start && is_wsp(chars[end - 1]) {
    end = end - 1
  }
  String::from_array(chars[start:end].to_owned())
}

///|
/// Split a metadata document into its headers and its body.
///
/// The header section ends at the first blank line or at the first line that is
/// not a header, whichever comes first; everything after that is the body,
/// returned verbatim so a description carried in the body keeps its exact line
/// endings (CRLF included).
///
/// A line that continues a header starts with a space or a tab and is unfolded
/// into the logical value with a single space (RFC 5322 §2.2.3). A continuation
/// before any header, and a line whose colon starts the line, are dropped, which
/// is what the RFC 822 reader used by `packaging` does with them.
fn split_document(text : String) -> (Array[Header], String) {
  let chars = text.to_array()
  let n = chars.length()
  let headers : Array[Header] = []
  let mut last = -1
  let mut i = 0
  let mut body_start = n
  let mut done = false
  while i < n && !done {
    let line_start = i
    let mut e = i
    while e < n && !is_line_break(chars[e]) {
      e = e + 1
    }
    let next = if e < n && chars[e] == '\r' && e + 1 < n && chars[e + 1] == '\n' {
      e + 2
    } else if e < n {
      e + 1
    } else {
      e
    }
    if e == line_start {
      // The blank line that separates the headers from the body.
      body_start = next
      done = true
    } else if is_wsp(chars[line_start]) {
      if last >= 0 {
        let piece = trim_wsp(String::from_array(chars[line_start:e].to_owned()))
        let previous = headers[last]
        headers[last] = {
          ..previous,
          value: if previous.value.is_empty() {
            piece
          } else {
            previous.value + " " + piece
          },
        }
      }
      i = next
    } else {
      let colon = find_char(chars, line_start, e, ':')
      if colon == line_start {
        i = next
      } else if colon > 0 && is_header_name(chars, line_start, colon) {
        let key = String::from_array(chars[line_start:colon].to_owned()).to_lower()
        let value = trim_wsp(String::from_array(chars[colon + 1:e].to_owned()))
        headers.push({ key, value, offset: line_start, })
        last = headers.length() - 1
        i = next
      } else {
        // Not a header, so the body starts here.
        body_start = line_start
        done = true
      }
    }
  }
  (headers, String::from_array(chars[body_start:].to_owned()))
}

///|
/// The character offset of the first header called `key`, or 0 when it is
/// absent. A value level error is reported at the first occurrence of its field.
fn field_offset(headers : Array[Header], key : String) -> Int {
  for header in headers {
    if header.key == key {
      return header.offset
    }
  }
  0
}

///|
/// Raise `code` at the offset of the field `key`. The result type is generic
/// because an error is raised both as a statement and in a position that wants a
/// value.
fn[T] fail(
  code : String,
  headers : Array[Header],
  key : String,
) -> T raise VersionError {
  raise InvalidMetadata(code, field_offset(headers, key))
}

///|
/// The value of the first header called `key`, or `None`.
fn first_value(headers : Array[Header], key : String) -> String? {
  for header in headers {
    if header.key == key {
      return Some(header.value)
    }
  }
  None
}

///|
/// Collect the values of every field, in document order per field, applying rules
/// 9 and 10: the field must exist in the specification (`UNKNOWN_FIELD`), must
/// have been introduced by a metadata version no later than the declared one
/// (`FIELD_NOT_IN_METADATA_VERSION`), and a single-use field may appear once only
/// (`DUPLICATE_HEADER`).
///
/// The structural check runs before any field value is interpreted, so the
/// reported error does not depend on the order the fields appear in.
fn collect_fields(
  headers : Array[Header],
  rank : Int,
) -> Map[String, Array[String]] raise VersionError {
  let fields : Map[String, Array[String]] = Map([])
  for header in headers {
    let added = match field_added_version(header.key) {
      Some(version) => version_rank(version).unwrap()
      None => raise InvalidMetadata("UNKNOWN_FIELD", header.offset)
    }
    if added > rank {
      raise InvalidMetadata("FIELD_NOT_IN_METADATA_VERSION", header.offset)
    }
    match fields.get(header.key) {
      Some(values) => {
        if !is_multi_use(header.key) {
          raise InvalidMetadata("DUPLICATE_HEADER", header.offset)
        }
        values.push(header.value)
      }
      None => fields[header.key] = [header.value]
    }
  }
  fields
}

///|
/// The single value of a single-use field, or `None` when the field is absent.
/// Presence has already been checked, so a list here holds one element at most.
fn one(fields : Map[String, Array[String]], key : String) -> String? {
  match fields.get(key) {
    Some(values) => if values.is_empty() { None } else { Some(values[0]) }
    None => None
  }
}

///|
/// The values of a multi-use field, in document order; empty when absent.
fn many(fields : Map[String, Array[String]], key : String) -> Array[String] {
  match fields.get(key) {
    Some(values) => values
    None => []
  }
}

///|
/// The PEP 508 / PEP 503 project name rule (rule 3): an alphanumeric start, an
/// alphanumeric or `_` end, and alphanumerics, `.`, `_` or `-` in between.
///
/// `requirements.mbt` applies exactly this rule to requirement names but keeps
/// its predicates private, so the rule is repeated here rather than reaching into
/// that module. Reusing it verbatim is the point: a name that `Requires-Dist`
/// accepts must also be accepted as a `Name`, and vice versa.
fn is_valid_name(text : String) -> Bool {
  let chars = text.to_array()
  let n = chars.length()
  if n == 0 || !is_ascii_alphanumeric(chars[0]) {
    return false
  }
  if !(is_ascii_alphanumeric(chars[n - 1]) || chars[n - 1] == '_') {
    return false
  }
  for i = 1; i < n - 1; i = i + 1 {
    let c = chars[i]
    if !(is_ascii_alphanumeric(c) || c == '.' || c == '_' || c == '-') {
      return false
    }
  }
  true
}

///|
/// True when the value carries one of the line boundaries that make a header
/// value multi-line: CR, LF, VT, FF, FS/GS/RS, NEL, LINE SEPARATOR and PARAGRAPH
/// SEPARATOR, the `_LINE_BOUNDARY_RE` of `packaging`. Only `Summary` is checked
/// in the reference implementation, so only `Summary` is checked here.
fn has_line_boundary(text : String) -> Bool {
  for c in text.to_array() {
    let code = c.to_int()
    if code == 10 ||
      code == 13 ||
      code == 11 ||
      code == 12 ||
      (code >= 28 && code <= 30) ||
      code == 133 ||
      code == 8232 ||
      code == 8233 {
      return true
    }
  }
  false
}

///|
/// A character that may appear in a MIME type token (RFC 2045): printable ASCII
/// that is not a `tspecial` and not a separator.
fn is_mime_token_char(c : Char) -> Bool {
  let code = c.to_int()
  if code < 33 || code > 126 {
    return false
  }
  match c {
    '('
    | ')'
    | '<'
    | '>'
    | '@'
    | ','
    | ';'
    | ':'
    | '\\'
    | '"'
    | '/'
    | '['
    | ']'
    | '?'
    | '=' => false
    _ => true
  }
}

///|
/// `chars` advanced past the run of spaces and tabs that starts at `start`.
fn skip_wsp(chars : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < chars.length() && is_wsp(chars[i]) {
    i = i + 1
  }
  i
}

///|
/// `chars` advanced past the MIME token that starts at `start`, if any.
fn scan_token(chars : Array[Char], start : Int) -> Int {
  let mut i = start
  while i < chars.length() && is_mime_token_char(chars[i]) {
    i = i + 1
  }
  i
}

///|
/// Rule 13: a `Description-Content-Type` value is a MIME type — `type/subtype`
/// with optional `; name=value` parameters (RFC 2045, RFC 6838). Any
/// `type/subtype` shape is accepted, which is deliberately more permissive than
/// `packaging`, whose `_process_description_content_type` allows only
/// `text/plain`, `text/x-rst` and `text/markdown`, only a UTF-8 charset and only
/// the `GFM` and `CommonMark` Markdown variants.
fn is_valid_mime_type(text : String) -> Bool {
  let chars = text.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n && chars[i] != ';' {
    i = i + 1
  }
  // The essence may be padded before the ';' but not inside `type/subtype`, and
  // the second '/' of `a/b/c` is not a token character, so it is rejected below.
  let essence = trim_wsp(String::from_array(chars[0:i].to_owned())).to_array()
  let slash = find_char(essence, 0, essence.length(), '/')
  if slash <= 0 || slash + 1 >= essence.length() {
    return false
  }
  for j = 0; j < essence.length(); j = j + 1 {
    if j != slash && !is_mime_token_char(essence[j]) {
      return false
    }
  }
  while i < n {
    // `chars[i]` is the ';' that starts a parameter.
    i = skip_wsp(chars, i + 1)
    if i == n {
      // A trailing ';' is tolerated rather than read as a named parameter.
      break
    }
    let name_end = scan_token(chars, i)
    let equals = skip_wsp(chars, name_end)
    if name_end == i || equals == n || chars[equals] != '=' {
      return false
    }
    i = skip_wsp(chars, equals + 1)
    if i < n && chars[i] == '"' {
      let close = find_char(chars, i + 1, n, '"')
      if close < 0 {
        return false
      }
      i = close + 1
    } else {
      let value_end = scan_token(chars, i)
      if value_end == i {
        return false
      }
      i = value_end
    }
    i = skip_wsp(chars, i)
    if i < n && chars[i] != ';' {
      return false
    }
  }
  true
}

///|
/// Split a comma separated mailbox list into its entries without splitting inside
/// a quoted display name or inside `<...>` (rule 11). An unbalanced quote or
/// angle bracket raises `code`.
fn split_mailboxes(text : String) -> Array[String] raise VersionError {
  let chars = text.to_array()
  let out : Array[String] = []
  let mut start = 0
  let mut depth = 0
  let mut quoted = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      if c == '\\' {
        i = i + 1
      } else if c == '"' {
        quoted = false
      }
    } else if c == '"' {
      quoted = true
    } else if c == '<' {
      depth = depth + 1
    } else if c == '>' {
      depth = depth - 1
      if depth < 0 {
        raise InvalidMetadata("MAILBOX_INVALID", 0)
      }
    } else if c == ',' && depth == 0 {
      out.push(String::from_array(chars[start:i].to_owned()))
      start = i + 1
    }
    i = i + 1
  }
  if quoted || depth != 0 {
    raise InvalidMetadata("MAILBOX_INVALID", 0)
  }
  out.push(String::from_array(chars[start:].to_owned()))
  out
}

///|
/// A deliberately shallow `addr-spec` check (rule 11): PEP 621 delegates the
/// grammar to RFC 5322, which this library does not implement, so the check is
/// the shape every usable address has — one `@`, a non-empty local part, a
/// non-empty domain, and no whitespace, angle brackets, quotes or commas.
fn is_valid_address(text : String) -> Bool {
  let chars = text.to_array()
  let mut at = -1
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '@' {
      if at >= 0 {
        return false
      }
      at = i
    } else if is_wsp(c) || c == '<' || c == '>' || c == ',' || c == '"' {
      return false
    }
  }
  at > 0 && at + 1 < chars.length()
}

///|
/// `text` without one pair of surrounding double quotes, when it has one.
fn strip_quotes(text : String) -> String {
  let chars = text.to_array()
  let n = chars.length()
  if n >= 2 && chars[0] == '"' && chars[n - 1] == '"' {
    String::from_array(chars[1:n - 1].to_owned())
  } else {
    text
  }
}

///|
/// Rule 11: parse an `Author-email`/`Maintainer-email` value into `(name,
/// address)` pairs, the shape PEP 621 gives the field (`Name <address>` or a bare
/// address, comma separated), raising `code` on anything else. A bare address has
/// an empty name; the raw text stays on the metadata either way.
fn parse_mailboxes(text : String) -> Array[(String, String)] raise VersionError {
  let out : Array[(String, String)] = []
  for entry in split_mailboxes(text) {
    let cleaned = trim_wsp(entry)
    let chars = cleaned.to_array()
    let open = find_char(chars, 0, chars.length(), '<')
    if open < 0 {
      if !is_valid_address(cleaned) {
        raise InvalidMetadata("MAILBOX_INVALID", 0)
      }
      out.push(("", cleaned))
      continue
    }
    if chars[chars.length() - 1] != '>' || find_char(chars, 0, open, '>') >= 0 {
      raise InvalidMetadata("MAILBOX_INVALID", 0)
    }
    let name = strip_quotes(
      trim_wsp(String::from_array(chars[0:open].to_owned())),
    )
    let address = trim_wsp(
      String::from_array(chars[open + 1:chars.length() - 1].to_owned()),
    )
    if name.is_empty() || !is_valid_address(address) {
      raise InvalidMetadata("MAILBOX_INVALID", 0)
    }
    out.push((name, address))
  }
  out
}

///|
/// A value that is present but empty counts as absent: `Author-email: ` and
/// `Author-email` are the same thing, and so are an empty `Name` and no `Name`.
fn present(value : String?) -> String? {
  match value {
    Some(text) => if text.is_empty() { None } else { Some(text) }
    None => None
  }
}

///|
/// The mailboxes an address list holds, or none when the list does not parse.
/// The failure is not an error: see the note at rule 11 in `Metadata::parse`.
fn mailboxes_or_empty(text : String) -> Array[(String, String)] {
  parse_mailboxes(text) catch {
    _ => []
  }
}

///|
/// Whether an address list parses. `diagnostics` re-asks instead of storing a
/// flag, so the struct stays a plain record of the document.
fn mailboxes_parsable(text : String) -> Bool {
  try {
    ignore(parse_mailboxes(text))
    true
  } catch {
    _ => false
  }
}

///|
/// Rule 12: a `Project-URL` value is `label, url`, the label first. A value
/// without a comma is rejected, and a label may not repeat, which is what the
/// reference implementation does with duplicate labels (it drops the field). Both
/// halves are stripped, as `packaging` does, and the URL keeps any further commas.
fn parse_project_urls(
  values : Array[String],
  headers : Array[Header],
) -> Array[(String, String)] raise VersionError {
  let out : Array[(String, String)] = []
  for value in values {
    let chars = value.to_array()
    let comma = find_char(chars, 0, chars.length(), ',')
    if comma < 0 {
      fail("PROJECT_URL_INVALID", headers, "project-url")
    }
    let label = trim_wsp(String::from_array(chars[0:comma].to_owned()))
    let url = trim_wsp(String::from_array(chars[comma + 1:].to_owned()))
    for pair in out {
      if pair.0 == label {
        fail("PROJECT_URL_DUPLICATE_LABEL", headers, "project-url")
      }
    }
    out.push((label, url))
  }
  out
}

///|
/// PEP 566: `Keywords` is a comma separated string, exposed here as the list of
/// stripped parts, which is the shape `packaging` uses too.
fn split_keywords(text : String) -> Array[String] {
  let out : Array[String] = []
  for part in text.split(",") {
    out.push(trim_wsp(part.to_owned()))
  }
  out
}

///|
/// True when a `Requires-Dist` marker mentions `extra` (or the PEP 685
/// `extras`), which is what attaches a dependency to a `Provides-Extra` name. A
/// marker that does not parse cannot mention anything, and it cannot reach here
/// anyway: `Requirement::parse` has already validated it.
fn marker_mentions_extra(text : String) -> Bool {
  try {
    let marker = Marker::parse(text)
    marker.variables().contains(MarkerVar::Extra) ||
    marker.variables().contains(MarkerVar::Extras)
  } catch {
    _ => false
  }
}

///|
/// A parsed and validated core metadata document.
///
/// Everything is stored the way the document spelled it — names, extras and
/// classifiers keep their case, an absent optional field is `None`, and multi-use
/// fields keep their input order — except for the fields the specification gives
/// a canonical form to: `Version` is a parsed PEP 440 version,
/// `License-Expression` holds the canonical SPDX expression, and `Dynamic` is
/// lower-cased because PEP 643 compares it case insensitively.
///
/// `raw` is the text handed to `Metadata::parse`. It is the caller's document,
/// not a canonical form, so it is not part of the `to_string` fixed point.
pub(all) struct Metadata {
  /// `Metadata-Version` (rule 1), one of `1.0 1.1 1.2 2.1 2.2 2.3 2.4`.
  metadata_version : String
  /// `Name` (rule 3), as written; `canonicalize_name` makes spellings comparable.
  name : String
  /// `Version` (rule 4), parsed as PEP 440.
  version : Version
  /// `Summary`.
  summary : String?
  /// `Description`, from the header or from the body after the blank line.
  description : String?
  /// `Description-Content-Type` (rule 13), a MIME type.
  description_content_type : String?
  /// `Keywords`, split on commas and stripped.
  keywords : Array[String]
  /// `Author`.
  author : String?
  /// `Author-email`, the raw value.
  author_email : String?
  /// `Author-email` as `(name, address)` pairs (rule 11).
  author_email_addresses : Array[(String, String)]
  /// `Maintainer`.
  maintainer : String?
  /// `Maintainer-email`, the raw value.
  maintainer_email : String?
  /// `Maintainer-email` as `(name, address)` pairs (rule 11).
  maintainer_email_addresses : Array[(String, String)]
  /// `License`, the free text form; forbidden next to `License-Expression`.
  license : String?
  /// `License-Expression` (rule 8), the canonical SPDX expression.
  license_expression : String?
  /// `Home-page`.
  home_page : String?
  /// `Download-URL`.
  download_url : String?
  /// `Requires-Python`, the raw set; `Metadata::requires_python` parses it.
  requires_python : String?
  /// `Classifier` (PEP 301 trove classifiers).
  classifiers : Array[String]
  /// `Requires-Dist`, the raw PEP 508 lines; `Metadata::requirements` parses them.
  requires_dist : Array[String]
  /// `Requires-External`.
  requires_external : Array[String]
  /// `Project-URL` as `(label, url)` pairs (rule 12).
  project_urls : Array[(String, String)]
  /// `Provides-Extra` as written; `Metadata::extras` canonicalizes.
  provides_extra : Array[String]
  /// `Provides-Dist`.
  provides_dist : Array[String]
  /// `Obsoletes-Dist`.
  obsoletes_dist : Array[String]
  /// `Dynamic` (PEP 643), lower-cased, in input order.
  dynamic : Array[String]
  /// `Platform`.
  platforms : Array[String]
  /// `Supported-Platform`.
  supported_platforms : Array[String]
  /// `License-File` (PEP 639), each path checked by `canonicalize_license_file`.
  license_files : Array[String]
  /// `Import-Name` (metadata 2.5). Always empty: rule 1 rejects such a document.
  import_names : Array[String]
  /// `Import-Namespace` (metadata 2.5). Always empty, for the same reason.
  import_namespaces : Array[String]
  /// `Requires` (deprecated in metadata 1.2).
  requires : Array[String]
  /// `Provides` (deprecated in metadata 1.2).
  provides : Array[String]
  /// `Obsoletes` (deprecated in metadata 1.2).
  obsoletes : Array[String]
  /// The document as handed to `Metadata::parse`.
  raw : String
} derive(Eq, @debug.Debug)

///|
/// Parse and validate a `METADATA`/`PKG-INFO` document (PEP 566).
///
/// The checks run in a fixed order, so the error a broken document reports is
/// deterministic: the version fields first (rules 1 and 2), then the structural
/// pass over every header (rules 9 and 10), then each field's own rule in the
/// canonical order of the specification's field list.
///
/// ```moonbit nocheck
/// let metadata = Metadata::parse(
///   "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n\nHello.\n",
/// )
/// metadata.name                 // "demo"
/// metadata.version.to_string()  // "1.0"
/// metadata.description          // Some("Hello.\n")
/// ```
pub fn Metadata::parse(text : String) -> Metadata raise VersionError {
  let (headers, body) = split_document(text)
  // Rule 1: Metadata-Version is required, and gates every other field.
  let metadata_version = match first_value(headers, "metadata-version") {
    Some(value) => value
    None => raise InvalidMetadata("METADATA_VERSION_REQUIRED", 0)
  }
  let rank = match version_rank(metadata_version) {
    Some(rank) if rank < ACCEPTED_METADATA_VERSION_RANK => rank
    _ => fail("METADATA_VERSION_INVALID", headers, "metadata-version")
  }
  // Rules 9 and 10, in document order, before any value is interpreted.
  let fields = collect_fields(headers, rank)
  // Rule 2: Name and Version are required by every accepted version, and an empty
  // value is a missing value, which is what the reference implementation says too.
  let name = match one(fields, "name") {
    Some(value) if !value.is_empty() => value
    _ => fail("NAME_REQUIRED", headers, "name")
  }
  let version_text = match one(fields, "version") {
    Some(value) if !value.is_empty() => value
    _ => fail("VERSION_REQUIRED", headers, "version")
  }
  // Rule 3.
  if !is_valid_name(name) {
    fail("NAME_INVALID", headers, "name")
  }
  // Rule 4.
  let version = Version::parse(version_text) catch {
    _ => fail("VERSION_INVALID", headers, "version")
  }
  // `Summary` is the one field that must not carry a line break.
  let summary = one(fields, "summary")
  match summary {
    Some(value) =>
      if has_line_boundary(value) {
        fail("SUMMARY_MULTILINE", headers, "summary")
      }
    None => ()
  }
  // Rule 5.
  let requires_python = one(fields, "requires-python")
  match requires_python {
    Some(value) =>
      ignore(SpecifierSet::parse(value)) catch {
        _ => fail("REQUIRES_PYTHON_INVALID", headers, "requires-python")
      }
    None => ()
  }
  // Rule 6, plus the last clause of rule 9: a marker that mentions `extra` is
  // only meaningful from 2.1, where `Provides-Extra` exists.
  let requires_dist = many(fields, "requires-dist")
  for value in requires_dist {
    let requirement = Requirement::parse(value) catch {
      _ => fail("REQUIRES_DIST_INVALID", headers, "requires-dist")
    }
    match requirement.marker_text {
      Some(marker_text) =>
        if rank < EXTRA_SUPPORT_VERSION_RANK &&
          marker_mentions_extra(marker_text) {
          fail("EXTRA_MARKER_NOT_IN_METADATA_VERSION", headers, "requires-dist")
        }
      None => ()
    }
  }
  // Rule 7.
  let provides_extra = many(fields, "provides-extra")
  for value in provides_extra {
    if !is_valid_name(value) {
      fail("PROVIDES_EXTRA_INVALID", headers, "provides-extra")
    }
  }
  // Rule 8: the SPDX expression is canonicalized on the way in, and PEP 639
  // forbids the two legacy license spellings next to it.
  let license = one(fields, "license")
  let classifiers = many(fields, "classifier")
  let license_expression = match one(fields, "license-expression") {
    None => None
    Some(value) => {
      let canonical = canonicalize_license_expression(value) catch {
        _ => fail("LICENSE_EXPRESSION_INVALID", headers, "license-expression")
      }
      match license {
        Some(_) => fail("LICENSE_EXPRESSION_CONFLICT", headers, "license")
        None => ()
      }
      for classifier in classifiers {
        if classifier.has_prefix("License ::") {
          fail("LICENSE_EXPRESSION_CONFLICT", headers, "classifier")
        }
      }
      Some(canonical)
    }
  }
  // Rule 13.
  let description_content_type = one(fields, "description-content-type")
  match description_content_type {
    Some(value) =>
      if !is_valid_mime_type(value) {
        fail(
          "DESCRIPTION_CONTENT_TYPE_INVALID", headers, "description-content-type",
        )
      }
    None => ()
  }
  // PEP 639 license file paths. The code is the one
  // `canonicalize_license_file` reports: PARENT_DIRECTORY, UNRESOLVED_GLOB,
  // ABSOLUTE_PATH or NOT_POSIX_PATH.
  let license_files : Array[String] = []
  for path in many(fields, "license-file") {
    let checked = canonicalize_license_file(path) catch {
      InvalidLicense(code, _) => fail(code, headers, "license-file")
      _ => fail("LICENSE_FILE_INVALID", headers, "license-file")
    }
    license_files.push(checked)
  }
  // PEP 643: `Dynamic` names a field. A field that does not exist cannot be
  // dynamic, and the three fields that define the distribution cannot be either.
  let dynamic : Array[String] = []
  for value in many(fields, "dynamic") {
    let lowered = value.to_lower()
    if field_added_version(lowered) is None ||
      lowered == "name" ||
      lowered == "version" ||
      lowered == "metadata-version" {
      fail("DYNAMIC_INVALID", headers, "dynamic")
    }
    dynamic.push(lowered)
  }
  // Rule 12.
  let project_urls = parse_project_urls(many(fields, "project-url"), headers)
  // Rule 11. An address list is *parsed*, not enforced: the field is optional, a
  // real `METADATA` in the wild carries a placeholder (`Author-email: UNKNOWN`)
  // or an empty value, and refusing the whole document over an optional field
  // would make those documents unreadable. What parses becomes the address list;
  // what does not is reported by `diagnostics`, where a caller can act on it
  // without losing the rest of the document. An empty value counts as absent,
  // the same way an empty `Name` does.
  let author_email = present(one(fields, "author-email"))
  let author_email_addresses = match author_email {
    Some(value) => mailboxes_or_empty(value)
    None => []
  }
  let maintainer_email = present(one(fields, "maintainer-email"))
  let maintainer_email_addresses = match maintainer_email {
    Some(value) => mailboxes_or_empty(value)
    None => []
  }
  let keywords = match one(fields, "keywords") {
    Some(value) => split_keywords(value)
    None => []
  }
  // The `Description` header wins over a body description. An empty body means
  // "no description", which is how the reference implementation reads it too.
  let description = match one(fields, "description") {
    Some(value) => Some(value)
    None => if body.is_empty() { None } else { Some(body) }
  }
  {
    metadata_version,
    name,
    version,
    summary,
    description,
    description_content_type,
    keywords,
    author: one(fields, "author"),
    author_email,
    author_email_addresses,
    maintainer: one(fields, "maintainer"),
    maintainer_email,
    maintainer_email_addresses,
    license,
    license_expression,
    home_page: one(fields, "home-page"),
    download_url: one(fields, "download-url"),
    requires_python,
    classifiers,
    requires_dist,
    requires_external: many(fields, "requires-external"),
    project_urls,
    provides_extra,
    provides_dist: many(fields, "provides-dist"),
    obsoletes_dist: many(fields, "obsoletes-dist"),
    dynamic,
    platforms: many(fields, "platform"),
    supported_platforms: many(fields, "supported-platform"),
    license_files,
    import_names: many(fields, "import-name"),
    import_namespaces: many(fields, "import-namespace"),
    requires: many(fields, "requires"),
    provides: many(fields, "provides"),
    obsoletes: many(fields, "obsoletes"),
    raw: text,
  }
}

///|
/// `Requires-Dist` parsed into PEP 508 requirements, in input order.
///
/// Every value was validated by `Metadata::parse`, so this cannot fail for a value
/// that came from it; a value a caller wrote into the struct by hand and that does
/// not parse is skipped rather than panicking.
pub fn Metadata::requirements(self : Metadata) -> Array[Requirement] {
  let out : Array[Requirement] = []
  for value in self.requires_dist {
    out.push(Requirement::parse(value)) catch {
      _ => ()
    }
  }
  out
}

///|
/// `Requires-Python` parsed as a PEP 440 specifier set, or `None` when the field
/// is absent. As with `requirements`, an unparsable hand-written value becomes
/// `None` instead of a panic.
pub fn Metadata::requires_python(self : Metadata) -> SpecifierSet? {
  match self.requires_python {
    None => None
    Some(value) => Some(SpecifierSet::parse(value)) catch { _ => None }
  }
}

///|
/// `Provides-Extra` in the canonical PEP 685 form, in input order: extras are
/// compared after `canonicalize_name`, so `Foo_Bar` and `foo-bar` are one extra.
/// The field itself keeps the spelling of the document.
pub fn Metadata::extras(self : Metadata) -> Array[String] {
  let out : Array[String] = []
  for value in self.provides_extra {
    out.push(canonicalize_name(value))
  }
  out
}

///|
/// True when this metadata describes `name` at `version` and can be installed on
/// `python`:
///
/// - the names are compared after `canonicalize_name` (PEP 503), so `Foo_Bar`
///   matches `foo-bar`;
/// - the versions are compared with PEP 440 equality, so `1.0` matches `1.0.0`;
/// - the `Requires-Python` set, when there is one and `python` was given, must
///   contain `python`. An unknown side is not a mismatch: no `Requires-Python`
///   means every interpreter, and `python = None` means the caller does not know
///   the interpreter it will install on.
pub fn Metadata::is_compatible(
  self : Metadata,
  name : String,
  version : Version,
  python : Version?,
) -> Bool {
  if canonicalize_name(name) != canonicalize_name(self.name) {
    return false
  }
  if Version::compare(self.version, version) != 0 {
    return false
  }
  match python {
    None => true
    Some(interpreter) =>
      match self.requires_python() {
        None => true
        Some(specifiers) => specifiers.contains(interpreter)
      }
  }
}

///|
/// Warnings about a document that parsed successfully. A warning is never an
/// error: the document is usable, it just says something the current
/// specifications discourage. The list is stable and ordered — the deprecated
/// field first, then one entry per deprecated classifier, then the
/// description-related warning — and the exact strings are:
///
/// - `deprecated: Home-page is superseded by Project-URL` when `Home-page` is
///   present (PEP 753 deprecates it in favour of a `Project-URL`);
/// - `classifier-not-current: <classifier>` for every `Classifier` that starts
///   with `License ::`, because PEP 639 replaces those classifiers with
///   `License-Expression`;
/// - `description-content-type-missing` when a description is present but
///   `Description-Content-Type` is not, which leaves the format of the body to the
///   reader (PEP 566).
pub fn Metadata::diagnostics(self : Metadata) -> Array[String] {
  let out : Array[String] = []
  match self.home_page {
    Some(_) => out.push("deprecated: Home-page is superseded by Project-URL")
    None => ()
  }
  for classifier in self.classifiers {
    if classifier.has_prefix("License ::") {
      out.push("classifier-not-current: " + classifier)
    }
  }
  let has_description = match self.description {
    Some(text) => !text.is_empty()
    None => false
  }
  if has_description && self.description_content_type is None {
    out.push("description-content-type-missing")
  }
  match self.author_email {
    Some(value) if !mailboxes_parsable(value) =>
      out.push("author-email-unparsable")
    _ => ()
  }
  match self.maintainer_email {
    Some(value) if !mailboxes_parsable(value) =>
      out.push("maintainer-email-unparsable")
    _ => ()
  }
  out
}

///|
/// Join `values` with `separator`; the empty list becomes the empty string.
fn join_with(values : Array[String], separator : String) -> String {
  let out = StringBuilder()
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      out.write_string(separator)
    }
    out.write_string(values[i])
  }
  out.to_string()
}

///|
/// Emit one field, spelled the canonical way `canonical_field_name` spells it:
/// header names are case-insensitive on input and canonical on output.
fn write_field(
  out : StringBuilder,
  key : String,
  values : Array[String],
) -> Unit {
  let name = canonical_field_name(key)
  for value in values {
    out.write_string(name + ": " + value + "\n")
  }
}

///|
/// Emit a single-use field when it is present.
fn write_single(out : StringBuilder, key : String, value : String?) -> Unit {
  match value {
    Some(text) => write_field(out, key, [text])
    None => ()
  }
}

///|
/// Emit a `(first, second)` field, which for `Project-URL` is `label, url`.
fn write_pairs(
  out : StringBuilder,
  key : String,
  pairs : Array[(String, String)],
) -> Unit {
  for pair in pairs {
    let (first, second) = pair
    write_field(out, key, [first + ", " + second])
  }
}

///|
/// Render the metadata as a `METADATA`/`PKG-INFO` document.
///
/// The rendering is canonical, so it re-parses to the same metadata; the unit
/// tests assert both the fixed point
/// `to_string(parse(to_string(m))) == to_string(m)` and that every field survives
/// a round trip:
///
/// - the headers come in the field order of the specification rather than the
///   order of the input document, and multi-use fields keep their input order;
/// - every value sits on a single line, because an unfolded logical value has no
///   line breaks;
/// - `Version` is the normalized PEP 440 spelling and `License-Expression` is the
///   canonical SPDX expression, the two fields whose value is normalized on the
///   way in;
/// - a non-empty `Description` is rendered as the body after the blank line,
///   which is the canonical 2.x location (PEP 566). An *empty* `Description` is
///   rendered as a header instead, because an empty body means "no description"
///   and would not survive the round trip.
pub fn Metadata::to_string(self : Metadata) -> String {
  let out = StringBuilder()
  write_field(out, "metadata-version", [self.metadata_version])
  write_field(out, "name", [self.name])
  write_field(out, "version", [self.version.to_string()])
  write_single(out, "summary", self.summary)
  write_single(out, "description-content-type", self.description_content_type)
  if !self.keywords.is_empty() {
    write_field(out, "keywords", [join_with(self.keywords, ", ")])
  }
  write_single(out, "author", self.author)
  write_single(out, "author-email", self.author_email)
  write_single(out, "maintainer", self.maintainer)
  write_single(out, "maintainer-email", self.maintainer_email)
  write_single(out, "license", self.license)
  write_single(out, "license-expression", self.license_expression)
  write_single(out, "home-page", self.home_page)
  write_single(out, "download-url", self.download_url)
  write_single(out, "requires-python", self.requires_python)
  write_field(out, "requires", self.requires)
  write_field(out, "provides", self.provides)
  write_field(out, "obsoletes", self.obsoletes)
  write_field(out, "classifier", self.classifiers)
  write_field(out, "requires-dist", self.requires_dist)
  write_field(out, "requires-external", self.requires_external)
  write_pairs(out, "project-url", self.project_urls)
  write_field(out, "provides-extra", self.provides_extra)
  write_field(out, "provides-dist", self.provides_dist)
  write_field(out, "obsoletes-dist", self.obsoletes_dist)
  write_field(out, "dynamic", self.dynamic)
  write_field(out, "platform", self.platforms)
  write_field(out, "supported-platform", self.supported_platforms)
  write_field(out, "license-file", self.license_files)
  write_field(out, "import-name", self.import_names)
  write_field(out, "import-namespace", self.import_namespaces)
  match self.description {
    Some(text) =>
      if text.is_empty() {
        // An empty body is indistinguishable from no body, so the header form is
        // the only one that round trips.
        write_field(out, "description", [text])
      } else {
        out.write_string("\n" + text)
      }
    None => ()
  }
  out.to_string()
}

///|
pub impl Show for Metadata with fn to_string(self : Metadata) -> String {
  Metadata::to_string(self)
}
