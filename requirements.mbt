///|
/// PEP 508 requirement lines: `name[extras] specifier ; marker` and
/// `name[extras] @ url ; marker`.
///
/// This is the piece that makes the dependency-inspection scenario work
/// end-to-end: a real `Requires-Dist` line from `METADATA` can be handed
/// straight to `Requirement::parse` instead of the caller having to extract the
/// constraint text by hand.
///
/// Semantics are aligned with PyPA `packaging` 26.3 and verified by the
/// differential corpus (`req` records). Two behaviours are worth calling out
/// because they are easy to get backwards:
///
/// - the *name* and the *extras* keep the spelling the caller used
///   (`Requests[Security]` stays as written), while
/// - the *specifier* is normalized: operands keep their spelling but the
///   clauses are deduplicated and sorted, so `>=2.0,<3.0` renders as
///   `<3.0,>=2.0`.
///
/// The marker is handed to `markers.mbt`, so an unknown marker key or a broken
/// `and`/`or` chain is rejected here exactly where the oracle rejects it. The
/// marker text is also kept verbatim on the parsed value, because re-rendering
/// it canonically belongs to the marker module.

///|
/// A parsed PEP 508 requirement.
#derive(@debug.Debug)
pub(all) struct Requirement {
  /// The project name exactly as written; call `canonicalize_name` to compare.
  name : String
  /// Extras exactly as written, deduplicated and sorted.
  extras : Array[String]
  /// The normalized constraint set.
  specifier : SpecifierSet
  /// Present for the `name @ url` form.
  url : String?
  /// The marker text after `;`, verbatim, if there is one.
  marker_text : String?
  /// The caller's original string.
  raw : String
}

///|
pub extend Requirement with @debug.Debug::{to_repr}

///|
pub extend Requirement with Show::{output}

///|
fn is_name_alnum(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
fn is_requirement_name_start(c : Char) -> Bool {
  is_name_alnum(c)
}

///|
fn is_requirement_name_char(c : Char) -> Bool {
  is_name_alnum(c) || c == '.' || c == '_' || c == '-'
}

///|
fn is_requirement_name_end(c : Char) -> Bool {
  is_name_alnum(c) || c == '_'
}

///|
/// PEP 508 names, as `packaging` actually accepts them: the first character is
/// alphanumeric, the last is alphanumeric or `_`, and the middle may also hold
/// `.`, `_` and `-`. This is why `foo_` and `foo._` are accepted while `foo-`,
/// `foo.` and `-foo` are not.
fn is_valid_requirement_name(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    return false
  }
  if !is_requirement_name_start(chars[0]) {
    return false
  }
  if !is_requirement_name_end(chars[chars.length() - 1]) {
    return false
  }
  for i = 1; i < chars.length() - 1; i = i + 1 {
    if !is_requirement_name_char(chars[i]) {
      return false
    }
  }
  true
}

///|
fn is_requirement_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// Sort and deduplicate strings by code point, which is the order
/// `packaging` uses when it renders a set.
fn sorted_unique(items : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for item in items {
    if !out.contains(item) {
      out.push(item)
    }
  }
  out.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  out
}

///|
/// Skip ASCII spaces and tabs starting at `pos`.
fn skip_space(chars : Array[Char], pos : Int32) -> Int32 {
  let mut i = pos
  while i < chars.length() && is_requirement_space(chars[i]) {
    i = i + 1
  }
  i
}

///|
fn slice(chars : Array[Char], start : Int32, stop : Int32) -> String {
  String::from_array(chars[start:stop].to_owned())
}

///|
/// Read an extras list at `pos`, where `chars[pos]` is the opening bracket.
/// Returns the extras and the position just past the closing bracket.
///
/// `name[]` and `name[  ]` are accepted and contribute no extras, but a list
/// that has started must be closed, and a comma may not be followed by the
/// bracket: `name[a,]` is not a requirement.
fn parse_extras(
  chars : Array[Char],
  pos : Int32,
) -> (Array[String], Int32) raise VersionError {
  let extras : Array[String] = []
  let mut cursor = pos + 1
  cursor = skip_space(chars, cursor)
  if cursor < chars.length() && chars[cursor] != ']' {
    let mut done = false
    while !done {
      cursor = skip_space(chars, cursor)
      let start = cursor
      while cursor < chars.length() && is_requirement_name_char(chars[cursor]) {
        cursor = cursor + 1
      }
      let extra = slice(chars, start, cursor)
      if !is_valid_requirement_name(extra) {
        raise VersionError::InvalidRequirement("INVALID_EXTRA", start)
      }
      extras.push(extra)
      cursor = skip_space(chars, cursor)
      if cursor < chars.length() && chars[cursor] == ',' {
        cursor = cursor + 1
      } else if cursor < chars.length() && chars[cursor] == ']' {
        done = true
      } else {
        raise VersionError::InvalidRequirement("EXPECTED_EXTRAS_END", cursor)
      }
    }
  }
  if cursor < chars.length() && chars[cursor] == ']' {
    (extras, cursor + 1)
  } else {
    raise VersionError::InvalidRequirement("UNCLOSED_EXTRAS", cursor)
  }
}

///|
/// Read the marker that follows a `;`: everything up to the end of the line,
/// trimmed, then validated by the marker parser.
fn parse_marker_text(
  chars : Array[Char],
  pos : Int32,
) -> String raise VersionError {
  let text = slice(chars, pos, chars.length()).trim().to_owned()
  if text.is_empty() {
    raise VersionError::InvalidRequirement("EMPTY_MARKER", pos)
  }
  validate_marker_text(text)
  text
}

///|
/// True for the characters a version specifier can start with. Characters that
/// cannot (a comma, say) mean the line had no specifier at all, which the
/// grammar reports differently from a malformed one.
fn is_specifier_start(c : Char) -> Bool {
  c == '(' || c == '=' || c == '<' || c == '>' || c == '!' || c == '~'
}

///|
/// Split a specifier body on commas, keeping empty segments.
fn split_keeping_empty(body : String) -> Array[String] {
  let chars = body.to_array()
  let out : Array[String] = []
  let mut start = 0
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ',' {
      out.push(slice(chars, start, i))
      start = i + 1
    }
  }
  out.push(slice(chars, start, chars.length()))
  out
}

///|
/// The requirement grammar allows a trailing comma but no empty clause, so
/// `>=1.0,` is a requirement while `>=1.0,,` and `>=1.0, ,<2` are not, even
/// though the bare specifier parser tolerates all three. Returns the offset of
/// the offending comma, or nothing when the layout is fine.
fn specifier_layout_error(body : String) -> Int32? {
  let segments = split_keeping_empty(body)
  if segments[0].trim().is_empty() {
    return Some(0)
  }
  let mut offset = 0
  for i = 0; i < segments.length(); i = i + 1 {
    if i > 0 && segments[i].trim().is_empty() && i != segments.length() - 1 {
      return Some(offset - 1)
    }
    offset = offset + segments[i].length() + 1
  }
  None
}

///|
/// Index of the first `;` that ends a version specifier.
///
/// The specifier may be wrapped in parentheses, which is a spelling PEP 508
/// dropped but the oracle still accepts; a `;` inside those parentheses does
/// not separate a marker.
fn specifier_end(chars : Array[Char], pos : Int32) -> Int32 {
  let mut cursor = pos
  let mut depth = 0
  while cursor < chars.length() {
    let c = chars[cursor]
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      if depth > 0 {
        depth = depth - 1
      } else {
        return cursor
      }
    } else if c == ';' && depth == 0 {
      return cursor
    }
    cursor = cursor + 1
  }
  chars.length()
}

///|
/// Parse a PEP 508 requirement line.
///
/// ```moonbit nocheck
/// let r = try! Requirement::parse("Requests[Security]>=2.0,<3.0 ; python_version >= \"3.8\"")
/// r.name                      // "Requests"
/// r.extras                    // ["Security"]
/// r.specifier.to_string()     // "<3.0,>=2.0"
/// r.marker_text               // Some("python_version >= \"3.8\"")
/// ```
///
/// The two operand forms have different whitespace rules, which is why the URL
/// form is parsed before any `;` is looked for: the URL runs to the next space,
/// so a `;` can be part of it.
pub fn Requirement::parse(input : String) -> Requirement raise VersionError {
  let chars = input.to_array()
  let end = chars.length()
  let mut pos = skip_space(chars, 0)
  if pos >= end {
    raise VersionError::InvalidRequirement("EMPTY_REQUIREMENT", pos)
  }
  // name: the first run of name characters, validated as a whole
  let name_start = pos
  while pos < end && is_requirement_name_char(chars[pos]) {
    pos = pos + 1
  }
  let name = slice(chars, name_start, pos)
  if !is_valid_requirement_name(name) {
    raise VersionError::InvalidRequirement("INVALID_NAME", name_start)
  }
  // extras
  pos = skip_space(chars, pos)
  let mut extras : Array[String] = []
  if pos < end && chars[pos] == '[' {
    let (parsed, next) = parse_extras(chars, pos)
    extras = parsed
    pos = next
  }
  pos = skip_space(chars, pos)
  let mut url : String? = None
  let mut marker_text : String? = None
  let mut specifier = SpecifierSet::parse("")
  if pos < end && chars[pos] == '@' {
    // `name @ url (whitespace requirement_marker?)?`
    pos = pos + 1
    pos = skip_space(chars, pos)
    let start = pos
    while pos < end && !is_requirement_space(chars[pos]) {
      pos = pos + 1
    }
    if pos == start {
      raise VersionError::InvalidRequirement("EMPTY_URL", start)
    }
    url = Some(slice(chars, start, pos))
    if pos < end {
      let before = pos
      pos = skip_space(chars, pos)
      if pos == before {
        raise VersionError::InvalidRequirement(
          "EXPECTED_WHITESPACE_AFTER_URL", pos,
        )
      }
      if pos < end {
        if chars[pos] != ';' {
          raise VersionError::InvalidRequirement(
            "EXPECTED_SEMICOLON_AFTER_URL", pos,
          )
        }
        pos = pos + 1
        marker_text = Some(parse_marker_text(chars, pos))
      }
    }
  } else if pos < end && chars[pos] == ';' {
    // `name ; marker`: the specifier is empty, and the separator follows the
    // name directly, as in `BeautifulSoup4; extra == "htmlsoup"`.
    pos = pos + 1
    marker_text = Some(parse_marker_text(chars, pos))
  } else if pos < end {
    // `specifier (whitespace requirement_marker)?`
    if !is_specifier_start(chars[pos]) {
      raise VersionError::InvalidRequirement("EXPECTED_SPECIFIER", pos)
    }
    let paren = chars[pos] == '('
    let stop = if paren {
      let mut cursor = pos + 1
      while cursor < end && chars[cursor] != ')' {
        cursor = cursor + 1
      }
      if cursor >= end {
        raise VersionError::InvalidRequirement("UNCLOSED_VERSION_SPEC", pos)
      }
      cursor
    } else {
      specifier_end(chars, pos)
    }
    let body = if paren {
      slice(chars, pos + 1, stop)
    } else {
      slice(chars, pos, stop)
    }
    let body_start = if paren { pos + 1 } else { pos }
    match specifier_layout_error(body) {
      Some(offset) =>
        raise VersionError::InvalidRequirement(
          "EXPECTED_SPECIFIER",
          body_start + offset,
        )
      None => ()
    }
    specifier = SpecifierSet::parse(body.trim().to_owned())
    pos = if paren { stop + 1 } else { stop }
    pos = skip_space(chars, pos)
    if pos < end {
      if chars[pos] != ';' {
        raise VersionError::InvalidRequirement("TRAILING_INPUT", pos)
      }
      pos = pos + 1
      marker_text = Some(parse_marker_text(chars, pos))
    }
  }
  {
    name,
    extras: sorted_unique(extras),
    specifier,
    url,
    marker_text,
    raw: input,
  }
}

///|
/// The normalized rendering: name, sorted extras, normalized specifier, URL and
/// marker, in that order.
pub fn Requirement::to_string(self : Requirement) -> String {
  let b = StringBuilder()
  b.write_string(self.name)
  if self.extras.length() > 0 {
    b.write_string("[")
    b.write_string(self.extras.join(","))
    b.write_string("]")
  }
  b.write_string(self.specifier.to_string())
  match self.url {
    Some(u) => b.write_string(" @ \{u}")
    None => ()
  }
  match self.marker_text {
    Some(m) =>
      if self.url is Some(_) {
        b.write_string(" ; \{m}")
      } else {
        b.write_string("; \{m}")
      }
    None => ()
  }
  b.to_string()
}

///|
pub impl Show for Requirement with fn to_string(self) {
  self.to_string()
}

///|
/// The outcome of checking one requirement against one candidate: the
/// PEP 508 judgment in a single answer, with the reason spelled out so a
/// caller can report why a candidate fell out.
#derive(@debug.Debug)
pub(all) enum Satisfaction {
  /// The version matches the constraints, and the marker (if any) is true
  /// in the given environment.
  Satisfied
  /// The version does not match the constraint set.
  VersionRejected(String)
  /// The version matches, but the marker is false in this environment.
  MarkerRejected(String)
  /// The marker could not be evaluated - an unknown variable or a set
  /// membership test against an unset variable, per PEP 508's rules.
  EvalError(String)
}

///|
pub extend Satisfaction with @debug.Debug::{to_repr}

///|
/// Check this requirement against one candidate version in one environment.
/// This is the PEP 508 core operation a resolver performs per candidate:
/// name-side extras are the *provider's* concern (the caller decides what
/// to request), so this checks the specifier and the marker only - the
/// extras list says which optional features the requirement *declares*,
/// not what the installed distribution must carry.
///
/// A requirement without a marker is satisfied by any version the
/// constraints accept. Marker evaluation follows PEP 508: unknown
/// variables and membership tests on unset variables are errors, not
/// silently false - surfaced as `MarkerError` with the reason.
pub fn Requirement::satisfied_by(
  self : Requirement,
  version : Version,
  environment : MarkerEnvironment,
  prereleases~ : Bool? = None,
) -> Satisfaction {
  if !self.specifier.contains(version, prereleases~) {
    return VersionRejected(self.specifier.to_string())
  }
  match self.marker_text {
    None => return Satisfied
    Some(text) => {
      let marker = Some(Marker::parse(text)) catch { _ => None }
      let marker = match marker {
        None => return EvalError("unparseable marker: " + text)
        Some(m) => m
      }
      let verdict = Some(marker.evaluate(environment)) catch {
        UndefinedEnvironmentName(message) => return EvalError(message)
        UndefinedComparison(message) => return EvalError(message)
        SetValuedOnLeft(a, b) => return EvalError(a + ":" + b)
      }
      let verdict = match verdict {
        None => false
        Some(b) => b
      }
      if verdict {
        Satisfied
      } else {
        MarkerRejected(text)
      }
    }
  }
}

///|
/// The same judgment for the common no-marker case, without building an
/// environment: satisfies when the version matches the constraints.
pub fn Requirement::satisfied_by_version(
  self : Requirement,
  version : Version,
  prereleases~ : Bool? = None,
) -> Bool {
  self.specifier.contains(version, prereleases~)
}

///|
/// One candidate that fell out of a batch check, with the reason the
/// single-requirement judgment already knows how to spell.
#derive(@debug.Debug)
pub(all) struct RequirementFailure {
  /// The requirement's normalized rendering.
  requirement : String
  /// Why it failed - the same branch names satisfied_by reports.
  reason : String
}

///|
pub extend RequirementFailure with @debug.Debug::{to_repr}

///|
/// Check a whole requirement list against the candidates the caller
/// holds, one version per project: the resolver's outer loop done
/// right. Each requirement looks up its own project by canonical name
/// via `lookup`; a requirement whose project has no candidate fails
/// with its own reason, and so does every branch satisfied_by reports.
/// The answer is None when every requirement is satisfied - or the
/// list of failures, each naming the requirement and why it blocked.
///
/// This shape exists because a single version cannot serve a list of
/// requirements about *different* projects: the batch judgment is per
/// project, and the lookup function is where the caller's candidate
/// set (an index slice, a lock file, a resolve plan) plugs in.
pub fn all_satisfied_by(
  requirements : Array[Requirement],
  lookup : (String) -> Version?,
  environment : MarkerEnvironment,
  prereleases~ : Bool? = None,
) -> Array[RequirementFailure]? {
  let failures : Array[RequirementFailure] = []
  for requirement in requirements {
    match lookup(requirement.name) {
      None =>
        failures.push({
          requirement: requirement.to_string(),
          reason: "no candidate for " + requirement.name,
        })
      Some(version) => {
        let verdict = requirement.satisfied_by(
          version,
          environment,
          prereleases~,
        )
        match verdict {
          Satisfied => ()
          VersionRejected(spec) =>
            failures.push({
              requirement: requirement.to_string(),
              reason: "version not in " + spec,
            })
          MarkerRejected(marker) =>
            failures.push({
              requirement: requirement.to_string(),
              reason: "marker false: " + marker,
            })
          EvalError(message) =>
            failures.push({
              requirement: requirement.to_string(),
              reason: "marker error: " + message,
            })
        }
      }
    }
  }
  if failures.is_empty() {
    None
  } else {
    Some(failures)
  }
}

///|
/// One side of a version-typed marker comparison, as an interval edge, an
/// exact value, or a value the comparison rules out.
priv enum MarkerSide {
  SideLower(Version, Bool)
  SideUpper(Version, Bool)
  SideExact(Version)
  SideExcluded(Version)
}

///|
/// The interval sides a version-typed marker comparison contributes. An
/// empty list means the operator is not reasoned about here: `===`
/// compares spellings, and a `~=` whose value does not carry two release
/// digits has no compatible-release bound to expand.
fn marker_op_sides(op : MarkerOp, text : String) -> Array[MarkerSide] {
  let parsed = Some(Version::parse(text)) catch { _ => None }
  match parsed {
    None => []
    Some(version) =>
      match op {
        Equal => [SideExact(version)]
        NotEqual => [SideExcluded(version)]
        Greater => [SideLower(version, true)]
        GreaterEqual => [SideLower(version, false)]
        Less => [SideUpper(version, true)]
        LessEqual => [SideUpper(version, false)]
        Compatible =>
          if version.release.length() >= 2 {
            [
              SideLower(version, false),
              SideUpper(compatible_upper(version), true),
            ]
          } else {
            []
          }
        ArbitraryEqual => []
        In => []
        NotIn => []
      }
  }
}

///|
/// Whether any side of one version constraint contradicts any side of the
/// other: the sides of one comparison hold conjunctively, so a single
/// crossing pair leaves no version (hence no environment value) for both.
fn marker_sides_conflict(
  sides_a : Array[MarkerSide],
  sides_b : Array[MarkerSide],
) -> Bool {
  for sa in sides_a {
    for sb in sides_b {
      let hit = match (sa, sb) {
        (SideLower(x, sx), SideUpper(y, sy)) =>
          edges_order_disjoint(x, sx, y, sy)
        (SideUpper(y, sy), SideLower(x, sx)) =>
          edges_order_disjoint(x, sx, y, sy)
        (SideExact(x), SideExact(y)) => compare_without_local(x, y) != 0
        (SideExact(x), SideExcluded(y)) => compare_without_local(x, y) == 0
        (SideExcluded(y), SideExact(x)) => compare_without_local(x, y) == 0
        (SideExact(x), SideLower(y, _)) => compare_without_local(x, y) < 0
        (SideLower(y, _), SideExact(x)) => compare_without_local(x, y) < 0
        (SideExact(x), SideUpper(y, _)) => compare_without_local(x, y) > 0
        (SideUpper(y, _), SideExact(x)) => compare_without_local(x, y) > 0
        (SideLower(_, _), SideLower(_, _)) => false
        (SideUpper(_, _), SideUpper(_, _)) => false
        (SideExcluded(_), _) => false
        (_, SideExcluded(_)) => false
      }
      if hit {
        return true
      }
    }
  }
  false
}

///|
/// The words of a set-membership literal: `"nt posix"` is the two-element
/// set {nt, posix}, split on ASCII whitespace.
fn marker_set_words(text : String) -> Array[String] {
  let chars = text.to_array()
  let out : Array[String] = []
  let current : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == ' ' || c == '\t' {
      if current.length() > 0 {
        out.push(String::from_array(current[0:current.length()].to_owned()))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    out.push(String::from_array(current[0:current.length()].to_owned()))
  }
  out
}

///|
/// Whether two string-typed marker comparisons on the same variable can
/// never hold together. Only the operators with literal answers are
/// reasoned about; everything else conservatively co-applies.
fn marker_string_conflict(
  op_a : MarkerOp,
  value_a : String,
  op_b : MarkerOp,
  value_b : String,
) -> Bool {
  match (op_a, op_b) {
    (Equal, Equal) => value_a != value_b
    (Equal, NotEqual) => value_a == value_b
    (NotEqual, Equal) => value_a == value_b
    (Equal, In) => marker_set_words(value_b).contains(value_a) == false
    (In, Equal) => marker_set_words(value_a).contains(value_b) == false
    (In, In) => {
      let words_a = marker_set_words(value_a)
      let words_b = marker_set_words(value_b)
      let mut shared = false
      for word in words_a {
        if words_b.contains(word) {
          shared = true
          break
        }
      }
      shared == false
    }
    _ => false
  }
}

///|
/// Whether two must-hold marker clauses on the same variable contradict
/// each other. Set-valued keys hold several names at once, so two
/// membership tests on them can always hold together.
fn marker_clause_pair_exclusive(ca : MarkerClause, cb : MarkerClause) -> Bool {
  match (ca.lhs, cb.lhs) {
    (Variable(va), Variable(vb)) => {
      if va != vb {
        return false
      }
      if va.is_set_valued() {
        return false
      }
      match (ca.rhs, cb.rhs) {
        (Value(ta), Value(tb)) => {
          // PEP 508 evaluates `in`/`not in` as string membership even on
          // version-like keys, so a membership operator routes through the
          // string comparison regardless of the variable.
          let membership = ca.op == In ||
            ca.op == NotIn ||
            cb.op == In ||
            cb.op == NotIn
          if va.is_version_like() && !membership {
            marker_sides_conflict(
              marker_op_sides(ca.op, ta),
              marker_op_sides(cb.op, tb),
            )
          } else {
            marker_string_conflict(ca.op, ta, cb.op, tb)
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
/// Whether two must-hold clause lists cannot be true in the same
/// environment - proven from one contradicting pair.
fn must_clauses_exclusive(
  a : Array[MarkerClause],
  b : Array[MarkerClause],
) -> Bool {
  for ca in a {
    for cb in b {
      if marker_clause_pair_exclusive(ca, cb) {
        return true
      }
    }
  }
  false
}

///|
/// The mirror image of a comparison operator, for normalizing
/// `"3.8" <= python_version` to the variable-on-the-left form. Membership
/// and compatible-release operators have no single mirror, so they stay
/// unnormalized (and are then not reasoned about).
fn flipped_marker_op(op : MarkerOp) -> MarkerOp? {
  match op {
    Less => Some(Greater)
    Greater => Some(Less)
    LessEqual => Some(GreaterEqual)
    GreaterEqual => Some(LessEqual)
    Equal => Some(Equal)
    NotEqual => Some(NotEqual)
    _ => None
  }
}

///|
/// The comparison clauses that must ALL hold for the marker to be true,
/// with the variable normalized to the left side. None when the marker
/// contains an `or`, at top level or inside a group: a disjunction has no
/// must-hold clause to contradict, so nothing about it can be proven.
fn must_hold_clauses(marker : Marker) -> Array[MarkerClause]? {
  let out : Array[MarkerClause] = []
  for item in marker.items {
    let mut ok = true
    match item {
      Or => ok = false
      And => ()
      Atom(Clause(clause)) =>
        match (clause.lhs, clause.rhs) {
          (Variable(_), Value(_)) => out.push(clause)
          (Value(_), Variable(_)) =>
            match flipped_marker_op(clause.op) {
              Some(op) => out.push({ lhs: clause.rhs, op, rhs: clause.lhs, })
              None => ()
            }
          _ => ()
        }
      Atom(Group(inner)) =>
        match must_hold_clauses(inner) {
          Some(more) =>
            for clause in more {
              out.push(clause)
            }
          None => ok = false
        }
    }
    if !ok {
      return None
    }
  }
  Some(out)
}

///|
/// Whether a marker can be true in some environment. A marker whose
/// must-hold clauses contradict themselves is unsatisfiable - never true,
/// never co-true with anything, even with a missing marker. Disjunctions,
/// unparseable values and unmodelled variables conservatively stay
/// possibly-true.
fn marker_may_be_true(text : String?) -> Bool {
  match text {
    None => true
    Some(t) => {
      let parsed = Some(Marker::parse(t)) catch { _ => None }
      match parsed {
        None => true
        Some(marker) =>
          match must_hold_clauses(marker) {
            None => true
            Some(clauses) => !must_clauses_exclusive(clauses, clauses)
          }
      }
    }
  }
}

///|
/// Whether some environment can make both markers true at once.
/// Exclusivity (the false answer) is proven only from must-hold
/// comparisons on a shared variable - including a marker contradicting
/// itself, which makes it unsatisfiable and therefore never co-true with
/// anything. Everything else - a disjunction, an unparseable value, a
/// variable this reasoning does not model - conservatively co-applies.
fn markers_may_coapply(left : String?, right : String?) -> Bool {
  if !marker_may_be_true(left) || !marker_may_be_true(right) {
    return false
  }
  match (left, right) {
    (Some(ta), Some(tb)) => {
      let ma = Some(Marker::parse(ta)) catch { _ => None }
      let mb = Some(Marker::parse(tb)) catch { _ => None }
      match (ma, mb) {
        (Some(parsed_a), Some(parsed_b)) =>
          match (must_hold_clauses(parsed_a), must_hold_clauses(parsed_b)) {
            (Some(clauses_a), Some(clauses_b)) =>
              !must_clauses_exclusive(clauses_a, clauses_b)
            _ => true
          }
        _ => true
      }
    }
    _ => true
  }
}

///|
/// Whether two requirements about the same project can never be satisfied
/// together - the question an upgrade tool asks before offering two pins
/// that cannot coexist.
///
/// True means the constraint sets provably share no version AND no
/// environment marker provably keeps the two requirements from ever
/// applying in the same environment. False means "no conflict found",
/// which is never a proof of compatibility: the specifier reasoning uses
/// sufficient conditions only (prerelease and post-release carve-outs are
/// not modelled, two `!=` clauses never collide), and the marker reasoning
/// gives up on disjunctions.
///
/// The surrounding rules:
///
/// - requirements about different projects (by canonical name) never
///   conflict through versions;
/// - two direct URLs for one project are pip's "double requirement": the
///   same URL is the same artifact (no conflict), a different URL is a
///   conflict no version can reconcile. One URL against a specifier cannot
///   be decided here, so it does not conflict;
/// - a requirement whose own constraint set is unsatisfiable
///   (`foo==1.0,==2.0`) admits nothing and therefore conflicts with every
///   requirement on the same project.
///
/// ```mbt check
/// test {
///   let a = @moon_pyversion.Requirement::parse("demo>=2.0")
///   let b = @moon_pyversion.Requirement::parse("Demo<2.0")
///   inspect(@moon_pyversion.Requirement::conflicts_with(a, b), content="true")
/// }
/// ```
pub fn Requirement::conflicts_with(
  self : Requirement,
  other : Requirement,
) -> Bool {
  if canonicalize_name(self.name) != canonicalize_name(other.name) {
    return false
  }
  match (self.url, other.url) {
    (Some(a), Some(b)) => return a != b
    (Some(_), None) => return false
    (None, Some(_)) => return false
    (None, None) => ()
  }
  if !markers_may_coapply(self.marker_text, other.marker_text) {
    return false
  }
  specifier_sets_disjoint(self.specifier, other.specifier)
}
