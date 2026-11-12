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
