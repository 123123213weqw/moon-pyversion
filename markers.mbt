///|
/// PEP 508 environment markers: `python_version < "3.10"`,
/// `extra == "test" and sys_platform == "win32"`.
///
/// A marker is a boolean expression over a small, closed vocabulary of
/// environment keys. It is the second half of a PEP 508 dependency line, the
/// part after the `;`. `requirements.mbt` splits the line and hands the tail to
/// `Marker::parse`, so the two modules together accept or reject a
/// `Requires-Dist` line exactly where PyPA `packaging` does.
///
/// Semantics are aligned with `packaging` 26.3 and verified by the differential
/// corpus (`marker` and `marker_eval` records). Three details are easy to get
/// wrong, so they are called out here:
///
/// - the *vocabulary is closed*: `ex0tra == "x"` is a syntax error, not an
///   unknown-name lookup failure, which is what makes a typo in a `Requires-Dist`
///   line detectable without evaluating anything.
/// - *rendering is not the input*: every value is re-quoted with `"`, the dotted
///   spellings (`os.name`) collapse to their canonical key, and parentheses are
///   emitted only where the `and`/`or` nesting needs them, because the same
///   structure also decides precedence.
/// - *`and`/`or` need no surrounding whitespace*, while `not in` does.
///
/// One documented boundary: when a version-like key holds a value that is not a
/// PEP 440 version, `packaging` lets the underlying `InvalidVersion` escape,
/// while this module falls back to string comparison.
pub(all) suberror MarkerError {
  /// The environment passed to `Marker::evaluate` has no value for this key.
  UndefinedEnvironmentName(String)
  /// The operator is not defined for this key and operand.
  UndefinedComparison(String)
  /// A set-valued key (`extras`, `dependency_groups`) appeared on the left.
  SetValuedOnLeft(String, String)
}

///|
pub impl Show for MarkerError with fn to_string(self) {
  match self {
    UndefinedEnvironmentName(key) => "no value for environment key \{key}"
    UndefinedComparison(detail) => detail
    SetValuedOnLeft(key, op) =>
      "set-valued marker \{key} can only be used with a membership test, not \{op}"
  }
}

///|
/// The complete marker vocabulary. Modelling it as a payload-free enum means a
/// misspelling cannot survive parsing.
pub(all) enum MarkerVar {
  PythonVersion
  PythonFullVersion
  OsName
  SysPlatform
  PlatformRelease
  PlatformSystem
  PlatformVersion
  PlatformMachine
  PlatformPythonImplementation
  ImplementationName
  ImplementationVersion
  Extra
  Extras
  DependencyGroups
} derive(Eq, @debug.Debug)

///|
/// The canonical environment key: what `Marker::to_string` prints and what a
/// `MarkerEnvironment` is keyed by.
pub fn MarkerVar::key(self : MarkerVar) -> String {
  match self {
    PythonVersion => "python_version"
    PythonFullVersion => "python_full_version"
    OsName => "os_name"
    SysPlatform => "sys_platform"
    PlatformRelease => "platform_release"
    PlatformSystem => "platform_system"
    PlatformVersion => "platform_version"
    PlatformMachine => "platform_machine"
    PlatformPythonImplementation => "platform_python_implementation"
    ImplementationName => "implementation_name"
    ImplementationVersion => "implementation_version"
    Extra => "extra"
    Extras => "extras"
    DependencyGroups => "dependency_groups"
  }
}

///|
/// True for the two keys whose environment value is a set of names rather than
/// a string (PEP 685 for `extras`, PEP 735 for `dependency_groups`).
pub fn MarkerVar::is_set_valued(self : MarkerVar) -> Bool {
  match self {
    Extras | DependencyGroups => true
    _ => false
  }
}

///|
/// True for the keys that are compared as versions, where `<` and `>` carry
/// their numeric meaning instead of being undefined.
pub fn MarkerVar::is_version_like(self : MarkerVar) -> Bool {
  match self {
    PythonVersion
    | PythonFullVersion
    | ImplementationVersion
    | PlatformRelease => true
    _ => false
  }
}

///|
/// Resolve a source spelling to a vocabulary entry. Several keys have a dotted
/// alias that `packaging` normalizes away, and `python_implementation` is an
/// alias for `platform_python_implementation`.
pub fn MarkerVar::parse(text : String) -> MarkerVar? {
  match text {
    "python_version" => Some(PythonVersion)
    "python_full_version" => Some(PythonFullVersion)
    "os_name" | "os.name" => Some(OsName)
    "sys_platform" | "sys.platform" => Some(SysPlatform)
    "platform_release" => Some(PlatformRelease)
    "platform_system" => Some(PlatformSystem)
    "platform_version" | "platform.version" => Some(PlatformVersion)
    "platform_machine" | "platform.machine" => Some(PlatformMachine)
    "platform_python_implementation" | "platform.python_implementation" =>
      Some(PlatformPythonImplementation)
    "python_implementation" => Some(PlatformPythonImplementation)
    "implementation_name" => Some(ImplementationName)
    "implementation_version" => Some(ImplementationVersion)
    "extra" => Some(Extra)
    "extras" => Some(Extras)
    "dependency_groups" => Some(DependencyGroups)
    _ => None
  }
}

///|
/// Every vocabulary spelling, longest first. The order matters: a plain `extra`
/// must not be allowed to shadow `extras`.
fn marker_var_spellings() -> Array[String] {
  [
    "platform_python_implementation", "platform.python_implementation", "implementation_version",
    "python_implementation", "python_full_version", "implementation_name", "dependency_groups",
    "platform_release", "platform_machine", "platform.machine", "platform_version",
    "platform.version", "platform_system", "python_version", "sys_platform", "sys.platform",
    "os_name", "os.name", "extras", "extra",
  ]
}

///|
/// The comparison operators of a marker clause.
pub(all) enum MarkerOp {
  Less
  LessEqual
  NotEqual
  Equal
  GreaterEqual
  Greater
  Compatible
  ArbitraryEqual
  In
  NotIn
} derive(Eq, @debug.Debug)

///|
pub fn MarkerOp::symbol(self : MarkerOp) -> String {
  match self {
    Less => "<"
    LessEqual => "<="
    NotEqual => "!="
    Equal => "=="
    GreaterEqual => ">="
    Greater => ">"
    Compatible => "~="
    ArbitraryEqual => "==="
    In => "in"
    NotIn => "not in"
  }
}

///|
/// Parse the symbolic operators. `in` and `not in` are word operators with
/// their own whitespace rules and are handled by the parser directly.
pub fn MarkerOp::parse(text : String) -> MarkerOp? {
  match text {
    "===" => Some(ArbitraryEqual)
    "==" => Some(Equal)
    "~=" => Some(Compatible)
    "!=" => Some(NotEqual)
    "<=" => Some(LessEqual)
    ">=" => Some(GreaterEqual)
    "<" => Some(Less)
    ">" => Some(Greater)
    _ => None
  }
}

///|
/// The symbolic operator spellings, longest first so `==` is never read as two
/// `<`-free single characters.
fn marker_op_symbols() -> Array[String] {
  ["===", "==", "~=", "!=", "<=", ">=", "<", ">"]
}

///|
/// One side of a comparison: either an environment key or a quoted string.
pub(all) enum MarkerOperand {
  Variable(MarkerVar)
  Value(String)
} derive(Eq, @debug.Debug)

///|
/// Render one operand the way `packaging` does: a key by its canonical name, a
/// string re-quoted with `"` unless it already contains one, in which case `'`
/// is used. A value containing both quote characters cannot be rendered, which
/// `packaging` reports as an error.
fn MarkerOperand::render(self : MarkerOperand) -> String raise VersionError {
  match self {
    Variable(variable) => variable.key()
    Value(value) =>
      if !value.contains("\"") {
        "\"" + value + "\""
      } else if !value.contains("'") {
        "'" + value + "'"
      } else {
        raise VersionError::InvalidMarker("UNREPRESENTABLE_VALUE", 0)
      }
  }
}

///|
/// One `lhs op rhs` clause.
pub(all) struct MarkerClause {
  lhs : MarkerOperand
  op : MarkerOp
  rhs : MarkerOperand
} derive(Eq, @debug.Debug)

///|
pub fn MarkerClause::render(self : MarkerClause) -> String raise VersionError {
  self.lhs.render() + " " + self.op.symbol() + " " + self.rhs.render()
}

///|
/// A member of the flat list a marker expression parses into. `and`/`or` are
/// members rather than tree nodes because that single choice decides both the
/// rendering and the `any(all(...))` evaluation order.
pub(all) enum MarkerAtom {
  Clause(MarkerClause)
  Group(Marker)
} derive(Eq, @debug.Debug)

///|
pub(all) enum MarkerItem {
  Atom(MarkerAtom)
  And
  Or
} derive(Eq, @debug.Debug)

///|
/// A parsed marker expression: a flat sequence of clauses, parenthesised groups
/// and `and`/`or` operators.
pub(all) struct Marker {
  items : Array[MarkerItem]
} derive(Eq, @debug.Debug)

///|
fn marker_is_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// A cursor over the characters of a marker expression.
priv struct MarkerParser {
  chars : Array[Char]
  mut pos : Int
}

///|
fn MarkerParser::peek(self : MarkerParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn MarkerParser::at_end(self : MarkerParser) -> Bool {
  self.pos >= self.chars.length()
}

///|
fn MarkerParser::skip_space(self : MarkerParser) -> Unit {
  while self.pos < self.chars.length() && marker_is_space(self.chars[self.pos]) {
    self.pos = self.pos + 1
  }
}

///|
fn MarkerParser::slice(self : MarkerParser, start : Int, stop : Int) -> String {
  String::from_array(self.chars[start:stop].to_owned())
}

///|
/// A word boundary in the sense of the Python `\b` anchor: exactly one of the
/// characters on either side of `index` is a word character. `index` may equal
/// the length, meaning end of input.
fn marker_boundary(chars : Array[Char], index : Int) -> Bool {
  let left_word = index > 0 && is_word_char(chars[index - 1])
  let right_word = index < chars.length() && is_word_char(chars[index])
  left_word != right_word
}

///|
/// Test whether `word` starts at the cursor, with a word boundary on both
/// sides, without consuming it. The trailing boundary is why `extra` does not
/// match inside `extras`.
fn MarkerParser::match_word(self : MarkerParser, word : String) -> Bool {
  let target = word.to_array()
  let length = target.length()
  if self.pos + length > self.chars.length() {
    return false
  }
  if !marker_boundary(self.chars, self.pos) {
    return false
  }
  for i = 0; i < length; i = i + 1 {
    if self.chars[self.pos + i] != target[i] {
      return false
    }
  }
  marker_boundary(self.chars, self.pos + length)
}

///|
/// Consume a vocabulary word if one starts here. Spellings are tried longest
/// first, so `extras` is never read as `extra` followed by junk.
fn MarkerParser::read_variable(self : MarkerParser) -> MarkerVar? {
  for spelling in marker_var_spellings() {
    if self.match_word(spelling) {
      match MarkerVar::parse(spelling) {
        Some(variable) => {
          self.pos = self.pos + spelling.length()
          return Some(variable)
        }
        None => ()
      }
    }
  }
  None
}

///|
/// Consume a quoted string if one starts here. The literal ends at the first
/// occurrence of its own quote character, which is how `packaging` tokenizes it;
/// the body is then decoded with Python string-literal rules, because that is
/// what `packaging` renders back out. A body the Python parser would reject (a
/// truncated `\\x` escape, a lone trailing backslash) is therefore a marker
/// syntax error here too.
fn MarkerParser::read_quoted(self : MarkerParser) -> String? raise VersionError {
  let quote = match self.peek() {
    Some(c) => c
    None => return None
  }
  if quote != '\'' && quote != '"' {
    return None
  }
  let start = self.pos + 1
  let mut stop = start
  while stop < self.chars.length() && self.chars[stop] != quote {
    stop = stop + 1
  }
  if stop >= self.chars.length() {
    return None
  }
  let raw = self.slice(start, stop)
  self.pos = stop + 1
  Some(decode_python_string(raw, start))
}

///|
/// Decode the body of a Python string literal.
///
/// The recognised escapes are the ones Python's own literal parser understands.
/// An unrecognised escape keeps its backslash, which is what Python does (it
/// only warns). The escapes that must have a fixed shape (`\\x`, `\\u`) are
/// errors when truncated, because Python raises `SyntaxError` for those and
/// `packaging` turns that into `InvalidMarker`. So is a lone trailing
/// backslash, which would have escaped the closing quote. `\\N{...}` is the
/// one documented gap: it is reported as unrepresentable rather than decoded.
fn decode_python_string(
  raw : String,
  offset : Int,
) -> String raise VersionError {
  if !raw.contains("\\") {
    return raw
  }
  let chars = raw.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '\\' {
      out.write_char(c)
      i = i + 1
      continue
    }
    if i + 1 >= chars.length() {
      raise VersionError::InvalidMarker("TRUNCATED_ESCAPE", offset + i)
    }
    let next = chars[i + 1]
    if next == 'n' {
      out.write_char('\n')
      i = i + 2
    } else if next == 'r' {
      out.write_char('\r')
      i = i + 2
    } else if next == 't' {
      out.write_char('\t')
      i = i + 2
    } else if next == 'b' {
      out.write_char(Int::unsafe_to_char(8))
      i = i + 2
    } else if next == 'f' {
      out.write_char(Int::unsafe_to_char(12))
      i = i + 2
    } else if next == 'v' {
      out.write_char(Int::unsafe_to_char(11))
      i = i + 2
    } else if next == 'a' {
      out.write_char(Int::unsafe_to_char(7))
      i = i + 2
    } else if next == '\\' || next == '\'' || next == '"' {
      out.write_char(next)
      i = i + 2
    } else if next == 'x' {
      match read_hex(chars, i + 2, 2) {
        Some(value) => {
          out.write_char(Int::unsafe_to_char(value))
          i = i + 4
        }
        None =>
          raise VersionError::InvalidMarker("TRUNCATED_HEX_ESCAPE", offset + i)
      }
    } else if next == 'u' {
      match read_hex(chars, i + 2, 4) {
        Some(value) => {
          out.write_char(Int::unsafe_to_char(value))
          i = i + 6
        }
        None =>
          raise VersionError::InvalidMarker(
            "TRUNCATED_UNICODE_ESCAPE",
            offset + i,
          )
      }
    } else if next == 'N' {
      raise VersionError::InvalidMarker("UNSUPPORTED_NAMED_ESCAPE", offset + i)
    } else if is_octal_digit(next) {
      let mut value = 0
      let mut used = 0
      while used < 3 &&
            i + 1 + used < chars.length() &&
            is_octal_digit(chars[i + 1 + used]) {
        value = value * 8 + (chars[i + 1 + used].to_int() - '0'.to_int())
        used = used + 1
      }
      out.write_char(Int::unsafe_to_char(value))
      i = i + 1 + used
    } else {
      // An unrecognised escape keeps its backslash, as Python does.
      out.write_char('\\')
      i = i + 1
    }
  }
  out.to_string()
}

///|
fn is_octal_digit(c : Char) -> Bool {
  c >= '0' && c <= '7'
}

///|
/// Read exactly `width` hexadecimal digits, or nothing.
fn read_hex(chars : Array[Char], start : Int, width : Int) -> Int? {
  if start + width > chars.length() {
    return None
  }
  let mut value = 0
  for offset = 0; offset < width; offset = offset + 1 {
    match hex_value(chars[start + offset]) {
      Some(digit) => value = value * 16 + digit
      None => return None
    }
  }
  Some(value)
}

///|
fn hex_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn MarkerParser::expect_space(
  self : MarkerParser,
  code : String,
) -> Unit raise VersionError {
  let before = self.pos
  self.skip_space()
  if self.pos == before {
    raise VersionError::InvalidMarker(code, self.pos)
  }
}

///|
/// Consume an operator: one of the symbolic spellings, or the word operators
/// `in` / `not in`. `not in` requires whitespace between its two words and
/// `and`/`or` never do.
fn MarkerParser::read_op(self : MarkerParser) -> MarkerOp raise VersionError {
  if self.match_word("not") {
    self.pos = self.pos + 3
    self.expect_space("EXPECTED_WHITESPACE_AFTER_NOT")
    if !self.match_word("in") {
      raise VersionError::InvalidMarker("EXPECTED_IN_AFTER_NOT", self.pos)
    }
    self.pos = self.pos + 2
    return NotIn
  }
  if self.match_word("in") {
    self.pos = self.pos + 2
    return In
  }
  for symbol in marker_op_symbols() {
    if self.starts_with(symbol) {
      match MarkerOp::parse(symbol) {
        Some(op) => {
          self.pos = self.pos + symbol.length()
          return op
        }
        None => ()
      }
    }
  }
  raise VersionError::InvalidMarker("EXPECTED_MARKER_OPERATOR", self.pos)
}

///|
fn MarkerParser::starts_with(self : MarkerParser, text : String) -> Bool {
  let target = text.to_array()
  if self.pos + target.length() > self.chars.length() {
    return false
  }
  for i = 0; i < target.length(); i = i + 1 {
    if self.chars[self.pos + i] != target[i] {
      return false
    }
  }
  true
}

///|
/// Consume one operand: a vocabulary word or a quoted string.
fn MarkerParser::read_operand(
  self : MarkerParser,
) -> MarkerOperand raise VersionError {
  match self.read_variable() {
    Some(variable) => Variable(variable)
    None =>
      match self.read_quoted() {
        Some(value) => Value(value)
        None =>
          raise VersionError::InvalidMarker(
            "EXPECTED_MARKER_VARIABLE",
            self.pos,
          )
      }
  }
}

///|
/// `marker_item = WS? marker_var WS? marker_op WS? marker_var WS?`
fn MarkerParser::parse_clause(
  self : MarkerParser,
) -> MarkerClause raise VersionError {
  self.skip_space()
  let lhs = self.read_operand()
  self.skip_space()
  let op = self.read_op()
  self.skip_space()
  let rhs = self.read_operand()
  self.skip_space()
  { lhs, op, rhs }
}

///|
/// `marker_atom = WS? '(' WS? marker WS? ')' WS? | WS? marker_item WS?`
fn MarkerParser::parse_atom(
  self : MarkerParser,
) -> MarkerAtom raise VersionError {
  self.skip_space()
  if self.peek() is Some('(') {
    let open = self.pos
    self.pos = self.pos + 1
    self.skip_space()
    let inner = self.parse_marker()
    self.skip_space()
    match self.peek() {
      Some(')') => self.pos = self.pos + 1
      _ => raise VersionError::InvalidMarker("UNCLOSED_GROUP", open)
    }
    self.skip_space()
    return Group(inner)
  }
  Clause(self.parse_clause())
}

///|
/// `marker = marker_atom (BOOLOP marker_atom)+`, built as one flat list.
fn MarkerParser::parse_marker(self : MarkerParser) -> Marker raise VersionError {
  let items : Array[MarkerItem] = [Atom(self.parse_atom())]
  while true {
    if self.match_word("and") {
      self.pos = self.pos + 3
      items.push(And)
    } else if self.match_word("or") {
      self.pos = self.pos + 2
      items.push(Or)
    } else {
      break
    }
    items.push(Atom(self.parse_atom()))
  }
  { items, }
}

///|
/// Parse a complete marker expression. Trailing input is an error, so
/// `python_version == "3.8" extra` does not parse.
pub fn Marker::parse(input : String) -> Marker raise VersionError {
  let parser : MarkerParser = { chars: input.to_array(), pos: 0 }
  let marker = parser.parse_marker()
  parser.skip_space()
  if !parser.at_end() {
    raise VersionError::InvalidMarker("TRAILING_INPUT", parser.pos)
  }
  marker.normalized()
}

///|
/// Render a marker expression back to text.
///
/// The structure is rendered with the minimum parentheses that preserve it: a
/// parenthesised group keeps its parentheses only when it is nested inside
/// another group, while a group that wraps a single clause loses them entirely
/// because the clause renders on its own.
pub fn Marker::to_string(self : Marker) -> String raise VersionError {
  self.render(true)
}

///|
fn Marker::render(self : Marker, first : Bool) -> String raise VersionError {
  if self.items.length() == 1 {
    match self.items[0] {
      Atom(atom) => return render_atom(atom, first)
      _ => ()
    }
  }
  let parts : Array[String] = []
  for item in self.items {
    match item {
      Atom(atom) => parts.push(render_atom(atom, false))
      And => parts.push("and")
      Or => parts.push("or")
    }
  }
  let joined = parts.join(" ")
  if first {
    joined
  } else {
    "(" + joined + ")"
  }
}

///|
fn render_atom(atom : MarkerAtom, first : Bool) -> String raise VersionError {
  match atom {
    Clause(clause) => clause.render()
    Group(inner) => inner.render(first)
  }
}

///|
pub impl Show for Marker with fn to_string(self) {
  self.render(true) catch {
    _ => "<unrepresentable marker>"
  }
}

///|
/// PEP 685 / PEP 735 name normalization at parse time: a name compared against
/// `extra`, `extras` or `dependency_groups` is stored canonicalized so that
/// rendering and evaluation cannot disagree.
fn Marker::normalized(self : Marker) -> Marker {
  let items : Array[MarkerItem] = []
  for item in self.items {
    match item {
      Atom(atom) => items.push(Atom(normalize_atom(atom)))
      And => items.push(And)
      Or => items.push(Or)
    }
  }
  { items, }
}

///|
fn normalize_atom(atom : MarkerAtom) -> MarkerAtom {
  match atom {
    Group(inner) => Group(inner.normalized())
    Clause(clause) =>
      match (clause.lhs, clause.rhs) {
        (Variable(Extra), Value(text)) =>
          Clause({
            lhs: clause.lhs,
            op: clause.op,
            rhs: Value(canonicalize_name(text)),
          })
        (Value(text), Variable(Extra)) =>
          Clause({
            lhs: Value(canonicalize_name(text)),
            op: clause.op,
            rhs: clause.rhs,
          })
        (Value(text), Variable(other)) =>
          if other.is_set_valued() {
            Clause({
              lhs: Value(canonicalize_name(text)),
              op: clause.op,
              rhs: clause.rhs,
            })
          } else {
            Clause(clause)
          }
        _ => Clause(clause)
      }
  }
}

///|
/// The value of a marker key at evaluation time. Most keys hold plain strings;
/// `extras` and `dependency_groups` hold sets of names.
pub(all) enum MarkerValue {
  Text(String)
  Names(Array[String])
} derive(Eq, @debug.Debug)

///|
/// The environment a marker is evaluated against. There is no ambient default:
/// the caller supplies every value, which keeps evaluation deterministic and
/// makes the differential corpus reproducible.
///
/// A caller must therefore provide a value for every key its markers mention,
/// or `evaluate` reports `UndefinedEnvironmentName`. PyPA `packaging` differs
/// here: it starts from the *host process's* real environment and overlays the
/// mapping it is given, so a key the caller omitted silently takes the value of
/// the machine the comparison runs on. That fallback is not reproducible, so
/// this library refuses it instead of reproducing it.
pub(all) struct MarkerEnvironment {
  values : Map[String, String]
  names : Map[String, Array[String]]
}

///|
pub fn MarkerEnvironment::new() -> MarkerEnvironment {
  { values: Map([]), names: Map([]) }
}

///|
pub fn MarkerEnvironment::set(
  self : MarkerEnvironment,
  key : String,
  value : String,
) -> Unit {
  self.values[key] = value
}

///|
pub fn MarkerEnvironment::set_names(
  self : MarkerEnvironment,
  key : String,
  value : Array[String],
) -> Unit {
  self.names[key] = value
}

///|
/// Look up a key, preferring the set-valued table so `set_names` wins for the
/// keys that can be either.
pub fn MarkerEnvironment::lookup(
  self : MarkerEnvironment,
  variable : MarkerVar,
) -> MarkerValue raise MarkerError {
  let key = variable.key()
  match self.names.get(key) {
    Some(list) => Names(list)
    None =>
      match self.values.get(key) {
        Some(text) => Text(text)
        None => raise MarkerError::UndefinedEnvironmentName(key)
      }
  }
}

///|
/// Evaluate a marker.
///
/// The flat `items` list is folded the way `packaging` folds it: every `or`
/// starts a new group, everything inside a group is an `and`, and the result is
/// true when any group is entirely true.
pub fn Marker::evaluate(
  self : Marker,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  evaluate_items(self.items, environment)
}

///|
fn evaluate_items(
  items : Array[MarkerItem],
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  let groups : Array[Array[Bool]] = [[]]
  for item in items {
    match item {
      Atom(Clause(clause)) =>
        groups[groups.length() - 1].push(evaluate_clause(clause, environment))
      Atom(Group(inner)) =>
        groups[groups.length() - 1].push(
          evaluate_items(inner.items, environment),
        )
      And => ()
      Or => groups.push([])
    }
  }
  for group in groups {
    let mut all_true = true
    for value in group {
      if !value {
        all_true = false
      }
    }
    if all_true {
      return true
    }
  }
  false
}

///|
/// Evaluate one clause. The key is normally the left operand, but
/// `"3.8" == python_version` is legal, so either side may be the variable.
fn evaluate_clause(
  clause : MarkerClause,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  match clause.lhs {
    Variable(variable) => {
      let lhs = match environment.lookup(variable) {
        Text(text) => text
        Names(_) =>
          raise MarkerError::SetValuedOnLeft(variable.key(), clause.op.symbol())
      }
      let rhs = operand_value(clause.rhs, environment)
      compare_marker(lhs, clause.op, rhs, Some(variable))
    }
    Value(left) =>
      match clause.rhs {
        Variable(variable) => {
          let rhs = environment.lookup(variable)
          compare_marker(left, clause.op, rhs, Some(variable))
        }
        Value(right) =>
          // Two literals: `packaging` still looks the right hand side up as an
          // environment key, so this is an undefined name rather than a plain
          // string comparison.
          raise MarkerError::UndefinedEnvironmentName(right)
      }
  }
}

///|
fn operand_value(
  operand : MarkerOperand,
  environment : MarkerEnvironment,
) -> MarkerValue raise MarkerError {
  match operand {
    Value(text) => Text(text)
    Variable(variable) => environment.lookup(variable)
  }
}

///|
/// Compare a left-hand string against the evaluated right-hand side. Version-like
/// keys go through the PEP 440 machinery, so `python_version > "3.7"` compares
/// numerically; everything else uses plain string semantics, where `<` and `>`
/// are defined to be false.
fn compare_marker(
  lhs : String,
  op : MarkerOp,
  rhs : MarkerValue,
  variable : MarkerVar?,
) -> Bool raise MarkerError {
  if variable is Some(key) && key.is_version_like() {
    match rhs {
      Text(text) => {
        let specifier : SpecifierSet? = Some(
          SpecifierSet::parse(op.symbol() + text),
        ) catch {
          _ => None
        }
        match (specifier, parse_version_opt(lhs)) {
          (Some(found), Some(version)) => return found.contains(version)
          _ => ()
        }
      }
      Names(_) => ()
    }
  }
  match rhs {
    Names(members) => {
      let canonical = canonicalize_name(lhs)
      let matched = members.contains(canonical)
      match op {
        In => matched
        NotIn => !matched
        _ => false
      }
    }
    Text(text) =>
      // `lhs in rhs` tests whether the left operand occurs inside the right
      // one, so the containment is asked of `text`, not of `lhs`.
      match op {
        In => text.contains(lhs)
        NotIn => !text.contains(lhs)
        Equal | LessEqual | GreaterEqual => lhs == text
        NotEqual => lhs != text
        Less | Greater => false
        Compatible | ArbitraryEqual =>
          raise MarkerError::UndefinedComparison(
            "undefined \{op.symbol()} on \{lhs} and \{text}",
          )
      }
  }
}

///|
/// The clauses a marker contains, in source order, including the clauses inside
/// parenthesised groups.
pub fn Marker::clauses(self : Marker) -> Array[MarkerClause] {
  let out : Array[MarkerClause] = []
  collect_clauses(self.items, out)
  out
}

///|
fn collect_clauses(
  items : Array[MarkerItem],
  out : Array[MarkerClause],
) -> Unit {
  for item in items {
    match item {
      Atom(Clause(clause)) => out.push(clause)
      Atom(Group(inner)) => collect_clauses(inner.items, out)
      And => ()
      Or => ()
    }
  }
}

///|
/// The keys a marker mentions, in first-appearance order. Useful for deciding
/// whether a marker can be evaluated in a given context at all.
pub fn Marker::variables(self : Marker) -> Array[MarkerVar] {
  let out : Array[MarkerVar] = []
  for clause in self.clauses() {
    for operand in [clause.lhs, clause.rhs] {
      match operand {
        Variable(variable) => if !out.contains(variable) { out.push(variable) }
        Value(_) => ()
      }
    }
  }
  out
}

///|
/// Validate a marker's text, for callers that only need the yes/no answer.
/// `requirements.mbt` uses this to decide whether a dependency line is well
/// formed.
pub fn validate_marker_text(text : String) -> Unit raise VersionError {
  ignore(Marker::parse(text))
}
