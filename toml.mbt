///|
/// A parsed TOML value.
///
/// `TDatetime` carries the exact source spelling of an offset date-time, a
/// local date-time, a local date or a local time. No date arithmetic and no
/// timezone normalization is performed, so `1979-05-27 07:32:00Z` keeps both
/// its separator and its `Z`.
pub(all) enum TomlValue {
  TString(String)
  TInt(Int64)
  TFloat(Double)
  TBool(Bool)
  TDatetime(String)
  TArray(Array[TomlValue])
  TTable(Toml)
} derive(Eq, @debug.Debug)

///|
/// An ordered TOML table.
///
/// Entries are kept as an association list in document order. Nothing is ever
/// re-sorted, so `Toml::to_string` is deterministic; lookups are a linear
/// scan, which is fine for the small tables found in `pyproject.toml` and
/// `pylock.toml`.
pub(all) struct Toml {
  entries : Array[(String, TomlValue)]
} derive(Eq, @debug.Debug)

///|
/// Mutable table used while parsing. `Array` is a shared reference, so the
/// same `MTable` value can be extended from several places.
priv struct MTable {
  entries : Array[(String, MEntry)]
}

///|
/// One slot of a mutable table. `explicit` holds the TOML 1.0 "explicitly
/// defined" flag: the name came from a `[table]` header or from a dotted key,
/// so it may not be declared a second time.
priv struct MEntry {
  node : MNode
  mut explicit : Bool
}

///|
/// A slot either holds a finished value, a structural sub-table, or the list
/// of tables built by `[[name]]` headers.
priv enum MNode {
  MValue(TomlValue)
  MSub(MTable)
  MTables(Array[MTable])
}

///|
fn new_table() -> MTable {
  { entries: [] }
}

///|
fn new_entry(node : MNode) -> MEntry {
  { node, explicit: false }
}

///|
fn MTable::find(self : MTable, key : String) -> MEntry? {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].0 == key {
      return Some(self.entries[i].1)
    }
  }
  None
}

///|
/// Copy of a path with the first `count` components of `key` appended.
fn concat_path(
  prefix : Array[String],
  key : Array[String],
  count : Int,
) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < prefix.length(); i = i + 1 {
    out.push(prefix[i])
  }
  for i = 0; i < count; i = i + 1 {
    out.push(key[i])
  }
  out
}

///|
fn push_path(path : Array[String], key : String) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < path.length(); i = i + 1 {
    out.push(path[i])
  }
  out.push(key)
  out
}

///|
fn is_ws(c : Int) -> Bool {
  c == 32 || c == 9
}

///|
fn is_digit_int(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
fn is_hex_int(c : Int) -> Bool {
  (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

///|
fn is_base_digit(c : Int, base : Int) -> Bool {
  if base == 16 {
    is_hex_int(c)
  } else if base == 8 {
    c >= 48 && c <= 55
  } else {
    c == 48 || c == 49
  }
}

///|
fn is_bare_key_int(c : Int) -> Bool {
  (c >= 48 && c <= 57) ||
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  c == 95 ||
  c == 45
}

///|
/// TOML 1.0 forbids raw control characters in strings; tabs are always fine
/// and newlines are fine inside multi-line strings. A lone `\r` never reaches
/// this check because `\r\n` is normalized away before parsing starts.
fn is_illegal_str_char(c : Int, multiline : Bool) -> Bool {
  if c == 9 {
    false
  } else if multiline && c == 10 {
    false
  } else {
    c < 32 || c == 127
  }
}

///|
/// Recursive-descent TOML 1.0 reader over one CRLF-normalized document. The
/// parser walks the source code unit by code unit and closes containers as it
/// meets their terminator, which keeps multi-line strings and multi-line
/// arrays uniform.
priv struct Parser {
  src : String
  mut pos : Int
  root : MTable
  mut current_path : Array[String]
  mut pending : Array[Array[String]]
}

///|
fn new_parser(src : String) -> Parser {
  let root = new_table()
  { src, pos: 0, root, current_path: [], pending: [] }
}

///|
/// The `Int` carried by `VersionError::InvalidToml` is a UTF-16 offset into
/// the CRLF-normalized source, matching the offsets used elsewhere in this
/// module.
fn toml_error(code : String, pos : Int) -> VersionError {
  VersionError::InvalidToml(code, pos)
}

///|
fn[T] Parser::fail(self : Parser, code : String) -> T raise VersionError {
  raise toml_error(code, self.pos)
}

///|
/// Code unit at the cursor, or `-1` at end of input.
fn Parser::peek(self : Parser) -> Int {
  if self.pos >= self.src.length() {
    -1
  } else {
    self.src[self.pos].to_int()
  }
}

///|
fn Parser::peek_at(self : Parser, offset : Int) -> Int {
  let i = self.pos + offset
  if i < 0 || i >= self.src.length() {
    -1
  } else {
    self.src[i].to_int()
  }
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.src.length()
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.pos = self.pos + 1
}

///|
fn Parser::starts_with(self : Parser, text : String) -> Bool {
  let n = text.length()
  if self.pos + n > self.src.length() {
    false
  } else {
    self.src[self.pos:self.pos + n].to_owned() == text
  }
}

///|
fn Parser::skip_ws(self : Parser) -> Unit {
  while is_ws(self.peek()) {
    self.advance()
  }
}

///|
/// Skip spaces, tabs, newlines and `#` comments. Inside arrays all four are
/// allowed between elements.
fn Parser::skip_array_ws(self : Parser) -> Unit {
  while true {
    let before = self.pos
    while is_ws(self.peek()) || self.peek() == 10 {
      self.advance()
    }
    self.skip_comment()
    if self.pos == before {
      return
    }
  }
}

///|
fn Parser::skip_comment(self : Parser) -> Unit {
  if self.peek() == 35 {
    while !self.eof() && self.peek() != 10 {
      self.advance()
    }
  }
}

///|
/// Slot at `path`, relative to `start`; `None` when it does not exist.
/// Walking *through* a finished value is an error, which is how TOML forbids
/// extending a namespace that already holds a value (an inline table or an
/// array, for instance).
fn Parser::entry_at_from(
  self : Parser,
  start : MTable,
  path : Array[String],
) -> MEntry? raise VersionError {
  if path.length() == 0 {
    return None
  }
  let mut table = start
  for i = 0; i < path.length() - 1; i = i + 1 {
    match table.find(path[i]) {
      Some(entry) =>
        match entry.node {
          MSub(sub) => table = sub
          MTables(tables) => table = tables[tables.length() - 1]
          MValue(_) => self.fail("CANNOT_OVERWRITE_VALUE")
        }
      None => return None
    }
  }
  table.find(path[path.length() - 1])
}

///|
/// Table at `path`, creating empty sub-tables as needed.
fn Parser::ensure_table_from(
  self : Parser,
  start : MTable,
  path : Array[String],
) -> MTable raise VersionError {
  let mut table = start
  for i = 0; i < path.length(); i = i + 1 {
    let key = path[i]
    match table.find(key) {
      Some(entry) =>
        match entry.node {
          MSub(sub) => table = sub
          MTables(tables) => table = tables[tables.length() - 1]
          MValue(_) => self.fail("CANNOT_OVERWRITE_VALUE")
        }
      None => {
        let sub = new_table()
        table.entries.push((key, new_entry(MSub(sub))))
        table = sub
      }
    }
  }
  table
}

///|
/// Turn pending dotted-key namespaces into explicit ones. Dotted keys only
/// lock a name once a later `[header]` is seen; that is what makes
/// `a.b = 1` followed by `a.c = 2` legal while a following `[a.b]` is not.
fn Parser::finalize_pending(self : Parser) -> Unit raise VersionError {
  for i = 0; i < self.pending.length(); i = i + 1 {
    let path = self.pending[i]
    match self.entry_at_from(self.root, path) {
      Some(entry) => entry.explicit = true
      None => ()
    }
  }
  self.pending = []
}

///|
fn Parser::clear_explicit_table(self : Parser, table : MTable) -> Unit {
  for i = 0; i < table.entries.length(); i = i + 1 {
    self.clear_explicit_entry(table.entries[i].1)
  }
}

///|
/// `[[a]]` re-opens `a`, so every declaration flag below it is dropped. This
/// mirrors the reference implementation, where a second `[[a]]` resets the
/// flags of everything nested under `a`.
fn Parser::clear_explicit_entry(self : Parser, entry : MEntry) -> Unit {
  entry.explicit = false
  match entry.node {
    MValue(_) => ()
    MSub(sub) => self.clear_explicit_table(sub)
    MTables(tables) =>
      for i = 0; i < tables.length(); i = i + 1 {
        self.clear_explicit_table(tables[i])
      }
  }
}

///|
fn Parser::is_explicit(
  self : Parser,
  path : Array[String],
) -> Bool raise VersionError {
  match self.entry_at_from(self.root, path) {
    Some(entry) => entry.explicit
    None => false
  }
}

///|
/// `key = value`, relative to the enclosing table header.
fn Parser::parse_key_value(self : Parser) -> Unit raise VersionError {
  let key = self.parse_key()
  self.skip_ws()
  if self.peek() != 61 {
    self.fail("EXPECTED_EQUALS_AFTER_KEY")
  }
  self.advance()
  self.skip_ws()
  let value = self.parse_value(0)
  let count = key.length()
  for i = 1; i < count; i = i + 1 {
    let container = concat_path(self.current_path, key, i)
    if self.is_explicit(container) {
      self.fail("CANNOT_REDEFINE_NAMESPACE")
    }
    self.pending.push(container)
  }
  let parent = self.ensure_table_from(
    self.root,
    concat_path(self.current_path, key, count - 1),
  )
  let stem = key[count - 1]
  match parent.find(stem) {
    Some(_) => self.fail("DUPLICATE_KEY")
    None => ()
  }
  parent.entries.push((stem, new_entry(MValue(value))))
}

///|
/// `[a.b]`.
fn Parser::parse_table_header(self : Parser) -> Unit raise VersionError {
  self.advance()
  self.skip_ws()
  let key = self.parse_key()
  self.skip_ws()
  if self.peek() != 93 {
    self.fail("EXPECTED_CLOSE_BRACKET")
  }
  self.advance()
  if self.is_explicit(key) {
    self.fail("TABLE_ALREADY_DEFINED")
  }
  let _ = self.ensure_table_from(self.root, key)
  match self.entry_at_from(self.root, key) {
    Some(entry) => entry.explicit = true
    None => ()
  }
  self.current_path = key
}

///|
/// `[[a.b]]`, which appends a fresh table to the array behind the name.
fn Parser::parse_array_table_header(self : Parser) -> Unit raise VersionError {
  self.advance()
  self.advance()
  self.skip_ws()
  let key = self.parse_key()
  self.skip_ws()
  if self.peek() != 93 || self.peek_at(1) != 93 {
    self.fail("EXPECTED_DOUBLE_CLOSE_BRACKET")
  }
  self.advance()
  self.advance()
  let count = key.length()
  let parent = self.ensure_table_from(
    self.root,
    concat_path([], key, count - 1),
  )
  let stem = key[count - 1]
  match parent.find(stem) {
    Some(entry) =>
      match entry.node {
        MTables(tables) => {
          self.clear_explicit_entry(entry)
          entry.explicit = true
          let fresh = new_table()
          tables.push(fresh)
          self.current_path = key
        }
        _ => self.fail("CANNOT_OVERWRITE_VALUE")
      }
    None => {
      let fresh = new_table()
      let tables : Array[MTable] = [fresh]
      let entry = new_entry(MTables(tables))
      entry.explicit = true
      parent.entries.push((stem, entry))
      self.current_path = key
    }
  }
}

///|
/// Whole document: table headers, key/value pairs, comments and blank lines.
fn Parser::parse_document(self : Parser) -> MTable raise VersionError {
  while true {
    self.skip_ws()
    if self.eof() {
      break
    }
    let c = self.peek()
    if c == 10 {
      self.advance()
      continue
    }
    if c == 35 {
      self.skip_comment()
    } else if c == 91 {
      self.finalize_pending()
      if self.peek_at(1) == 91 {
        self.parse_array_table_header()
      } else {
        self.parse_table_header()
      }
      self.skip_ws()
    } else if is_bare_key_int(c) || c == 34 || c == 39 {
      self.parse_key_value()
      self.skip_ws()
    } else {
      self.fail("INVALID_STATEMENT")
    }
    self.skip_comment()
    if self.eof() {
      break
    }
    if self.peek() != 10 {
      self.fail("EXPECTED_NEWLINE_OR_EOF")
    }
    self.advance()
  }
  self.root
}

///|
fn Parser::parse_key(self : Parser) -> Array[String] raise VersionError {
  let out : Array[String] = []
  while true {
    out.push(self.parse_key_part())
    self.skip_ws()
    if self.peek() == 46 {
      self.advance()
      self.skip_ws()
      continue
    }
    break
  }
  out
}

///|
fn Parser::parse_key_part(self : Parser) -> String raise VersionError {
  let c = self.peek()
  if c == 34 {
    self.parse_basic_string(false, false)
  } else if c == 39 {
    self.parse_literal_string()
  } else if is_bare_key_int(c) {
    let start = self.pos
    while is_bare_key_int(self.peek()) {
      self.advance()
    }
    self.src[start:self.pos].to_owned()
  } else {
    self.fail("INVALID_KEY")
  }
}

///|
/// Basic strings, single line and multi-line. Literal runs are copied straight
/// out of the source and escapes are appended as they are decoded.
fn Parser::parse_basic_string(
  self : Parser,
  multiline : Bool,
  opener_consumed : Bool,
) -> String raise VersionError {
  let out = StringBuilder()
  if !opener_consumed {
    self.advance()
  }
  let mut run = self.pos
  while true {
    if self.eof() {
      self.fail("UNTERMINATED_STRING")
    }
    let c = self.peek()
    if c == 34 {
      if !multiline {
        out.write_view(self.src[run:self.pos])
        self.advance()
        return out.to_string()
      }
      if self.starts_with("\"\"\"") {
        out.write_view(self.src[run:self.pos])
        self.pos = self.pos + 3
        return out.to_string()
      }
    } else if c == 92 {
      out.write_view(self.src[run:self.pos])
      self.advance()
      self.parse_escape(out, multiline)
      run = self.pos
      continue
    } else if is_illegal_str_char(c, multiline) {
      self.fail("ILLEGAL_CHARACTER_IN_STRING")
    }
    self.advance()
  }
  self.fail("UNTERMINATED_STRING")
}

///|
/// The cursor sits just after a backslash.
fn Parser::parse_escape(
  self : Parser,
  out : StringBuilder,
  multiline : Bool,
) -> Unit raise VersionError {
  if self.eof() {
    self.fail("INVALID_ESCAPE")
  }
  let c = self.peek()
  if multiline && (c == 32 || c == 9 || c == 10) {
    // A backslash at the end of a line swallows the line break and every
    // following whitespace-only line.
    if c != 10 {
      self.skip_ws()
      if self.peek() != 10 {
        self.fail("INVALID_ESCAPE")
      }
      self.advance()
    } else {
      self.advance()
    }
    while is_ws(self.peek()) || self.peek() == 10 {
      self.advance()
    }
    return
  }
  if c == 34 {
    self.advance()
    out.write_string("\"")
  } else if c == 92 {
    self.advance()
    out.write_string("\\")
  } else if c == 98 {
    self.advance()
    out.write_string("\u{08}")
  } else if c == 102 {
    self.advance()
    out.write_string("\u{0C}")
  } else if c == 110 {
    self.advance()
    out.write_string("\n")
  } else if c == 114 {
    self.advance()
    out.write_string("\r")
  } else if c == 116 {
    self.advance()
    out.write_string("\t")
  } else if c == 117 {
    self.advance()
    self.parse_hex_escape(out, 4)
  } else if c == 85 {
    self.advance()
    self.parse_hex_escape(out, 8)
  } else {
    self.fail("INVALID_ESCAPE")
  }
}

///|
fn Parser::parse_hex_escape(
  self : Parser,
  out : StringBuilder,
  digits : Int,
) -> Unit raise VersionError {
  let mut value = 0
  for i = 0; i < digits; i = i + 1 {
    let c = self.peek()
    if !is_hex_int(c) {
      self.fail("INVALID_ESCAPE")
    }
    value = value * 16 + toml_hex_value(c)
    self.advance()
  }
  if value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
    self.fail("INVALID_ESCAPE")
  }
  match value.to_char() {
    Some(ch) => out.write_char(ch)
    None => self.fail("INVALID_ESCAPE")
  }
}

///|
fn toml_hex_value(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 70 {
    c - 55
  } else {
    c - 87
  }
}

///|
/// `"""..."""`: a newline immediately after the opener is dropped, and one or
/// two extra quotes may belong to the content.
fn Parser::parse_multiline_basic(self : Parser) -> String raise VersionError {
  // Consume the three opening quotes and a single immediately following
  // newline, which TOML trims. The cursor is then already inside the string, so
  // `parse_basic_string` must not skip a character of its own.
  self.pos = self.pos + 3
  if self.peek() == 10 {
    self.advance()
  }
  let mut text = self.parse_basic_string(true, true)
  if self.peek() == 34 {
    self.advance()
    text = text + "\""
    if self.peek() == 34 {
      self.advance()
      text = text + "\""
    }
  }
  text
}

///|
/// `'''...'''`. No escape processing at all.
fn Parser::parse_multiline_literal(self : Parser) -> String raise VersionError {
  self.pos = self.pos + 3
  if self.peek() == 10 {
    self.advance()
  }
  let start = self.pos
  let mut text = ""
  let mut closed = false
  while !closed {
    if self.eof() {
      self.fail("UNTERMINATED_STRING")
    }
    let c = self.peek()
    if c == 39 && self.starts_with("'''") {
      text = self.src[start:self.pos].to_owned()
      self.pos = self.pos + 3
      closed = true
    } else if is_illegal_str_char(c, true) {
      self.fail("ILLEGAL_CHARACTER_IN_STRING")
    } else {
      self.advance()
    }
  }
  if self.peek() == 39 {
    self.advance()
    text = text + "'"
    if self.peek() == 39 {
      self.advance()
      text = text + "'"
    }
  }
  text
}

///|
/// `'...'`, single line.
fn Parser::parse_literal_string(self : Parser) -> String raise VersionError {
  self.advance()
  let start = self.pos
  while true {
    if self.eof() {
      self.fail("UNTERMINATED_STRING")
    }
    let c = self.peek()
    if c == 39 {
      let text = self.src[start:self.pos].to_owned()
      self.advance()
      return text
    }
    if is_illegal_str_char(c, false) {
      self.fail("ILLEGAL_CHARACTER_IN_STRING")
    }
    self.advance()
  }
  self.fail("UNTERMINATED_STRING")
}

///|
/// Offset date-time, local date-time, local date or local time. Returns `None`
/// when the text is not shaped like a date or a time at all, so that the
/// caller can fall through to number parsing.
fn Parser::parse_datetime(self : Parser) -> TomlValue? raise VersionError {
  if self.looks_like_date() {
    let start = self.pos
    let year = self.read_int(4)
    self.advance()
    let month = self.read_int(2)
    self.advance()
    let day = self.read_int(2)
    if month < 1 || month > 12 || day < 1 || day > days_in_month(year, month) {
      self.fail("INVALID_DATETIME")
    }
    if self.is_time_delimiter() && is_digit_int(self.peek_at(1)) {
      self.advance()
      let _ = self.read_time_text()
      self.parse_offset()
    }
    Some(TDatetime(self.src[start:self.pos].to_owned()))
  } else if self.looks_like_time() {
    Some(TDatetime(self.read_time_text()))
  } else {
    None
  }
}

///|
fn Parser::looks_like_date(self : Parser) -> Bool {
  is_digit_int(self.peek()) &&
  is_digit_int(self.peek_at(1)) &&
  is_digit_int(self.peek_at(2)) &&
  is_digit_int(self.peek_at(3)) &&
  self.peek_at(4) == 45 &&
  is_digit_int(self.peek_at(5)) &&
  is_digit_int(self.peek_at(6)) &&
  self.peek_at(7) == 45 &&
  is_digit_int(self.peek_at(8)) &&
  is_digit_int(self.peek_at(9))
}

///|
fn Parser::looks_like_time(self : Parser) -> Bool {
  is_digit_int(self.peek()) &&
  is_digit_int(self.peek_at(1)) &&
  self.peek_at(2) == 58 &&
  is_digit_int(self.peek_at(3)) &&
  is_digit_int(self.peek_at(4)) &&
  self.peek_at(5) == 58 &&
  is_digit_int(self.peek_at(6)) &&
  is_digit_int(self.peek_at(7))
}

///|
fn Parser::is_time_delimiter(self : Parser) -> Bool {
  let c = self.peek()
  c == 84 || c == 116 || c == 32
}

///|
fn Parser::read_int(self : Parser, digits : Int) -> Int {
  let mut value = 0
  for i = 0; i < digits; i = i + 1 {
    value = value * 10 + (self.peek() - 48)
    self.advance()
  }
  value
}

///|
/// `HH:MM:SS[.fraction]` starting at the cursor.
///
/// The fraction is capped at six digits, the precision a microsecond-based
/// implementation can represent; the specification leaves extra precision to
/// the implementation.
fn Parser::read_time_text(self : Parser) -> String raise VersionError {
  if !self.looks_like_time() {
    self.fail("INVALID_DATETIME")
  }
  let start = self.pos
  let hour = self.read_int(2)
  self.advance()
  let minute = self.read_int(2)
  self.advance()
  let second = self.read_int(2)
  if hour > 23 || minute > 59 || second > 59 {
    self.fail("INVALID_DATETIME")
  }
  if self.peek() == 46 {
    self.advance()
    let mut seen = 0
    while seen < 6 && is_digit_int(self.peek()) {
      self.advance()
      seen = seen + 1
    }
    if seen == 0 {
      self.fail("INVALID_DATETIME")
    }
  }
  self.src[start:self.pos].to_owned()
}

///|
/// Optional `Z`/`z` or `+HH:MM`/`-HH:MM` right after a time.
fn Parser::parse_offset(self : Parser) -> Unit raise VersionError {
  let c = self.peek()
  if c == 90 || c == 122 {
    self.advance()
  } else if c == 43 || c == 45 {
    if !is_digit_int(self.peek_at(1)) ||
      !is_digit_int(self.peek_at(2)) ||
      self.peek_at(3) != 58 ||
      !is_digit_int(self.peek_at(4)) ||
      !is_digit_int(self.peek_at(5)) {
      self.fail("INVALID_DATETIME")
    }
    self.advance()
    let hour = self.read_int(2)
    self.advance()
    let minute = self.read_int(2)
    if hour > 23 || minute > 59 {
      self.fail("INVALID_DATETIME")
    }
  }
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  if month == 2 {
    if is_leap_year(year) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Integers and floats follow the TOML 1.0 grammar: no sign on `0x`/`0o`/`0b`,
/// no leading zeros on decimals, and `_` only between digits. Returns `None`
/// when the text does not start a number.
fn Parser::parse_number(self : Parser) -> TomlValue? raise VersionError {
  let start = self.pos
  let first = self.peek()
  if first == 48 {
    let marker = self.peek_at(1)
    if marker == 120 || marker == 111 || marker == 98 {
      let base = if marker == 120 { 16 } else if marker == 111 { 8 } else { 2 }
      self.advance()
      self.advance()
      if !is_base_digit(self.peek(), base) {
        // Nothing was consumed beyond the cursor, so the caller can still try
        // another production at the original position.
        self.pos = start
        return None
      }
      self.advance()
      while true {
        if self.peek() == 95 && is_base_digit(self.peek_at(1), base) {
          self.advance()
        }
        if is_base_digit(self.peek(), base) {
          self.advance()
        } else {
          break
        }
      }
      let digits = strip_underscores(self.src[start + 2:self.pos].to_owned())
      return Some(self.make_int_in_base(digits, base))
    }
  }
  if first == 43 || first == 45 {
    self.advance()
  }
  let head = self.peek()
  if head == 48 {
    self.advance()
  } else if head >= 49 && head <= 57 {
    self.advance()
    while true {
      if self.peek() == 95 && is_digit_int(self.peek_at(1)) {
        self.advance()
      }
      if is_digit_int(self.peek()) {
        self.advance()
      } else {
        break
      }
    }
  } else {
    // Restore the sign, if one had been consumed: `-inf` is not a number, and
    // the caller must still see the `-`.
    self.pos = start
    return None
  }
  let mut is_float = false
  if self.peek() == 46 && is_digit_int(self.peek_at(1)) {
    is_float = true
    self.advance()
    self.advance()
    while true {
      if self.peek() == 95 && is_digit_int(self.peek_at(1)) {
        self.advance()
      }
      if is_digit_int(self.peek()) {
        self.advance()
      } else {
        break
      }
    }
  }
  if self.peek() == 101 || self.peek() == 69 {
    let mark = self.pos
    self.advance()
    if self.peek() == 43 || self.peek() == 45 {
      self.advance()
    }
    if is_digit_int(self.peek()) {
      is_float = true
      self.advance()
      while true {
        if self.peek() == 95 && is_digit_int(self.peek_at(1)) {
          self.advance()
        }
        if is_digit_int(self.peek()) {
          self.advance()
        } else {
          break
        }
      }
    } else {
      self.pos = mark
    }
  }
  let text = strip_underscores(self.src[start:self.pos].to_owned())
  if is_float {
    Some(self.make_float(text))
  } else {
    Some(self.make_int_decimal(text))
  }
}

///|
fn Parser::make_int_in_base(
  self : Parser,
  digits : String,
  base : Int,
) -> TomlValue raise VersionError {
  // TOML integers are 64-bit signed values, so they are parsed as `Int64`; a
  // 32-bit `Int` would reject `0xDEADBEEF` on a wasm32 target.
  let value = @string.parse_int64(digits, base~) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }
  TInt(value)
}

///|
fn Parser::make_int_decimal(
  self : Parser,
  text : String,
) -> TomlValue raise VersionError {
  let digits = if text.has_prefix("+") {
    text[1:text.length()].to_owned()
  } else {
    text
  }
  let value = @string.parse_int64(digits) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }
  TInt(value)
}

///|
fn Parser::make_float(
  self : Parser,
  text : String,
) -> TomlValue raise VersionError {
  let digits = if text.has_prefix("+") {
    text[1:text.length()].to_owned()
  } else {
    text
  }
  let value = @string.parse_double(digits) catch {
    _ => self.fail("INVALID_NUMBER")
  }
  TFloat(value)
}

///|
fn strip_underscores(text : String) -> String {
  if !text.contains_char('_') {
    return text
  }
  let out = StringBuilder()
  for c in text {
    if c != '_' {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn Parser::parse_value(
  self : Parser,
  depth : Int,
) -> TomlValue raise VersionError {
  if depth > 256 {
    self.fail("NESTING_TOO_DEEP")
  }
  self.skip_ws()
  let c = self.peek()
  if c == 34 {
    if self.starts_with("\"\"\"") {
      return TString(self.parse_multiline_basic())
    }
    return TString(self.parse_basic_string(false, false))
  }
  if c == 39 {
    if self.starts_with("'''") {
      return TString(self.parse_multiline_literal())
    }
    return TString(self.parse_literal_string())
  }
  if c == 116 && self.starts_with("true") {
    self.pos = self.pos + 4
    return TBool(true)
  }
  if c == 102 && self.starts_with("false") {
    self.pos = self.pos + 5
    return TBool(false)
  }
  if c == 91 {
    return self.parse_array(depth)
  }
  if c == 123 {
    return self.parse_inline_table(depth)
  }
  match self.parse_datetime() {
    Some(value) => return value
    None => ()
  }
  match self.parse_number() {
    Some(value) => return value
    None => ()
  }
  if self.starts_with("inf") {
    self.pos = self.pos + 3
    return TFloat(1.0 / 0.0)
  }
  if self.starts_with("nan") {
    self.pos = self.pos + 3
    return TFloat(0.0 / 0.0)
  }
  if self.starts_with("-inf") || self.starts_with("+inf") {
    let negative = self.peek() == 45
    self.pos = self.pos + 4
    return TFloat(if negative { -1.0 / 0.0 } else { 1.0 / 0.0 })
  }
  if self.starts_with("-nan") || self.starts_with("+nan") {
    self.pos = self.pos + 4
    return TFloat(0.0 / 0.0)
  }
  self.fail("INVALID_VALUE")
}

///|
fn Parser::parse_array(
  self : Parser,
  depth : Int,
) -> TomlValue raise VersionError {
  self.advance()
  let items : Array[TomlValue] = []
  self.skip_array_ws()
  if self.peek() == 93 {
    self.advance()
    return TArray(items)
  }
  while true {
    items.push(self.parse_value(depth + 1))
    self.skip_array_ws()
    let c = self.peek()
    if c == 93 {
      self.advance()
      return TArray(items)
    }
    if c != 44 {
      self.fail("UNCLOSED_ARRAY")
    }
    self.advance()
    self.skip_array_ws()
    if self.peek() == 93 {
      self.advance()
      return TArray(items)
    }
  }
  self.fail("UNCLOSED_ARRAY")
}

///|
/// Inline tables are single-line in TOML 1.0: no newline between the braces
/// and no trailing comma. A value may of course span lines on its own, through
/// a multi-line string or an array.
fn Parser::parse_inline_table(
  self : Parser,
  depth : Int,
) -> TomlValue raise VersionError {
  self.advance()
  let table = new_table()
  self.skip_ws()
  self.reject_newline_in_inline_table()
  if self.peek() == 125 {
    self.advance()
    return TTable(mtable_to_toml(table))
  }
  while true {
    let key = self.parse_key()
    self.skip_ws()
    if self.peek() != 61 {
      self.fail("EXPECTED_EQUALS_AFTER_KEY")
    }
    self.advance()
    self.skip_ws()
    let value = self.parse_value(depth + 1)
    let count = key.length()
    let parent = self.ensure_table_from(table, concat_path([], key, count - 1))
    let stem = key[count - 1]
    match parent.find(stem) {
      Some(_) => self.fail("DUPLICATE_KEY")
      None => ()
    }
    parent.entries.push((stem, new_entry(MValue(value))))
    self.skip_ws()
    let c = self.peek()
    if c == 125 {
      self.advance()
      return TTable(mtable_to_toml(table))
    }
    if c != 44 {
      self.fail("UNCLOSED_INLINE_TABLE")
    }
    self.advance()
    self.skip_ws()
    self.reject_newline_in_inline_table()
    if self.peek() == 125 {
      self.fail("TRAILING_COMMA_IN_INLINE_TABLE")
    }
  }
  self.fail("UNCLOSED_INLINE_TABLE")
}

///|
/// TOML 1.0 keeps an inline table on one line, so a newline where another key
/// could start is a syntax error rather than an unterminated table. The two
/// cases are reported separately because the fixes differ: an unclosed table
/// needs a `}`, a wrapped table needs to become a `[table]`.
fn Parser::reject_newline_in_inline_table(
  self : Parser,
) -> Unit raise VersionError {
  if self.peek() == 10 {
    self.fail("NEWLINE_IN_INLINE_TABLE")
  }
}

///|
fn mtable_to_toml(table : MTable) -> Toml {
  let entries : Array[(String, TomlValue)] = []
  for i = 0; i < table.entries.length(); i = i + 1 {
    entries.push((table.entries[i].0, mnode_to_value(table.entries[i].1.node)))
  }
  { entries, }
}

///|
fn mnode_to_value(node : MNode) -> TomlValue {
  match node {
    MValue(value) => value
    MSub(sub) => TTable(mtable_to_toml(sub))
    MTables(tables) => {
      let items : Array[TomlValue] = []
      for i = 0; i < tables.length(); i = i + 1 {
        items.push(TTable(mtable_to_toml(tables[i])))
      }
      TArray(items)
    }
  }
}

///|
/// Parse a TOML 1.0 document.
///
/// `\r\n` is normalized to `\n` first, which the specification allows even
/// inside string literals. A lone `\r` and a leading byte-order mark are
/// rejected.
pub fn Toml::parse(input : String) -> Toml raise VersionError {
  let src = input.replace_all(old="\r\n", new="\n")
  let parser = new_parser(src)
  let root = parser.parse_document()
  mtable_to_toml(root)
}

///|
fn split_dotted(key : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  for i = 0; i < key.length(); i = i + 1 {
    if key[i].to_int() == 46 {
      out.push(key[start:i].to_owned())
      start = i + 1
    }
  }
  out.push(key[start:key.length()].to_owned())
  out
}

///|
fn Toml::find(self : Toml, key : String) -> TomlValue? {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].0 == key {
      return Some(self.entries[i].1)
    }
  }
  None
}

///|
/// Look up a key, optionally as a dotted path such as `"tool.poetry.name"`.
///
/// A dotted path descends through tables only; it stops at arrays. A key that
/// literally contains a `.` therefore has to be fetched through its parent
/// table.
pub fn Toml::get(self : Toml, key : String) -> TomlValue? {
  let parts = split_dotted(key)
  let mut table = self
  for i = 0; i < parts.length() - 1; i = i + 1 {
    match table.find(parts[i]) {
      Some(TTable(sub)) => table = sub
      _ => return None
    }
  }
  table.find(parts[parts.length() - 1])
}

///|
pub fn Toml::get_string(self : Toml, key : String) -> String? {
  match self.get(key) {
    Some(TString(value)) => Some(value)
    _ => None
  }
}

///|

///|
/// An integer value, widened to `Int64` because that is TOML's own width. A
/// caller that knows the value fits can narrow it with `Int64::to_int`.
pub fn Toml::get_int(self : Toml, key : String) -> Int64? {
  match self.get(key) {
    Some(TInt(value)) => Some(value)
    _ => None
  }
}

///|
pub fn Toml::get_bool(self : Toml, key : String) -> Bool? {
  match self.get(key) {
    Some(TBool(value)) => Some(value)
    _ => None
  }
}

///|
pub fn Toml::get_array(self : Toml, key : String) -> Array[TomlValue]? {
  match self.get(key) {
    Some(TArray(value)) => Some(value)
    _ => None
  }
}

///|
pub fn Toml::get_table(self : Toml, key : String) -> Toml? {
  match self.get(key) {
    Some(TTable(value)) => Some(value)
    _ => None
  }
}

///|
fn is_bare_key_text(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  for i = 0; i < text.length(); i = i + 1 {
    if !is_bare_key_int(text[i].to_int()) {
      return false
    }
  }
  true
}

///|
fn render_key(text : String) -> String {
  if is_bare_key_text(text) {
    text
  } else {
    "\"" + escape_basic(text) + "\""
  }
}

///|
fn escape_basic(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    let code = c.to_int()
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if code == 8 {
      out.write_string("\\b")
    } else if code == 9 {
      out.write_string("\\t")
    } else if code == 10 {
      out.write_string("\\n")
    } else if code == 12 {
      out.write_string("\\f")
    } else if code == 13 {
      out.write_string("\\r")
    } else if code < 32 || code == 127 {
      out.write_string("\\u")
      out.write_string(hex4(code))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn hex4(value : Int) -> String {
  let digits = "0123456789ABCDEF"
  let out = StringBuilder()
  for shift = 12; shift >= 0; shift = shift - 4 {
    let index = (value >> shift) & 15
    out.write_view(digits[index:index + 1])
  }
  out.to_string()
}

///|
fn render_float(value : Double) -> String {
  if value.is_nan() {
    "nan"
  } else if value.is_pos_inf() {
    "inf"
  } else if value.is_neg_inf() {
    "-inf"
  } else if value == 0.0 && 1.0 / value < 0.0 {
    "-0.0"
  } else {
    let text = value.to_string()
    if text.contains_char('.') ||
      text.contains_char('e') ||
      text.contains_char('E') {
      text
    } else {
      text + ".0"
    }
  }
}

///|
fn render_value(value : TomlValue) -> String {
  match value {
    TString(text) => "\"" + escape_basic(text) + "\""
    TInt(number) => number.to_string()
    TFloat(number) => render_float(number)
    TBool(flag) => if flag { "true" } else { "false" }
    TDatetime(text) => text
    TArray(items) => {
      let out = StringBuilder()
      out.write_string("[")
      for i = 0; i < items.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(render_value(items[i]))
      }
      out.write_string("]")
      out.to_string()
    }
    TTable(table) => {
      let out = StringBuilder()
      if table.entries.length() == 0 {
        out.write_string("{}")
      } else {
        out.write_string("{")
        for i = 0; i < table.entries.length(); i = i + 1 {
          if i > 0 {
            out.write_string(",")
          }
          out.write_string(" ")
          out.write_string(render_key(table.entries[i].0))
          out.write_string(" = ")
          out.write_string(render_value(table.entries[i].1))
        }
        out.write_string(" }")
      }
      out.to_string()
    }
  }
}

///|
/// True for a non-empty array whose elements are all tables, the shape written
/// with `[[name]]` headers.
fn is_array_of_tables(value : TomlValue) -> Bool {
  match value {
    TArray(items) =>
      if items.length() == 0 {
        false
      } else {
        let mut all_tables = true
        for i = 0; i < items.length(); i = i + 1 {
          match items[i] {
            TTable(_) => ()
            _ => all_tables = false
          }
        }
        all_tables
      }
    _ => false
  }
}

///|
fn render_header_path(path : Array[String]) -> String {
  let out = StringBuilder()
  for i = 0; i < path.length(); i = i + 1 {
    if i > 0 {
      out.write_string(".")
    }
    out.write_string(render_key(path[i]))
  }
  out.to_string()
}

///|
fn write_pair(out : StringBuilder, key : String, value : TomlValue) -> Unit {
  out.write_string(render_key(key))
  out.write_string(" = ")
  out.write_string(render_value(value))
  out.write_string("\n")
}

///|
/// Plain values are written before sub-tables at every level, so that a
/// `[a.b]` header can never capture a later sibling key.
fn write_table(out : StringBuilder, table : Toml, path : Array[String]) -> Unit {
  for i = 0; i < table.entries.length(); i = i + 1 {
    let key = table.entries[i].0
    let value = table.entries[i].1
    let is_nested = match value {
      TTable(_) => true
      _ => is_array_of_tables(value)
    }
    if !is_nested {
      write_pair(out, key, value)
    }
  }
  for i = 0; i < table.entries.length(); i = i + 1 {
    let key = table.entries[i].0
    let value = table.entries[i].1
    let child = push_path(path, key)
    match value {
      TTable(sub) => {
        // The blank line separates a header from whatever came before it; at
        // the very start of the document there is nothing to separate.
        write_separator(out)
        out.write_string("[")
        out.write_string(render_header_path(child))
        out.write_string("]\n")
        write_table(out, sub, child)
      }
      TArray(items) =>
        if is_array_of_tables(value) {
          for j = 0; j < items.length(); j = j + 1 {
            write_separator(out)
            out.write_string("[[")
            out.write_string(render_header_path(child))
            out.write_string("]]\n")
            match items[j] {
              TTable(sub) => write_table(out, sub, child)
              _ => ()
            }
          }
        }
      _ => ()
    }
  }
}

///|
/// Write the blank line that precedes a table header, unless the document is
/// still empty.
fn write_separator(out : StringBuilder) -> Unit {
  if !out.is_empty() {
    out.write_string("\n")
  }
}

///|
/// Canonical re-serialization.
///
/// The result re-parses to an equal `Toml`. Within a table, plain values are
/// written before sub-tables so that TOML's header scoping cannot move a key
/// into the wrong table; sub-tables and arrays of tables keep their relative
/// order.
pub fn Toml::to_string(self : Toml) -> String {
  let out = StringBuilder()
  write_table(out, self, [])
  out.to_string()
}
