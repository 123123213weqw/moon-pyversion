///|
#derive(Eq, @debug.Debug)
pub(all) enum SpecifierOp {
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  Compatible
  ArbitraryEqual
}

///|
pub extend SpecifierOp with Eq::{equal, not_equal}

///|
pub extend SpecifierOp with @debug.Debug::{to_repr}

///|
#derive(@debug.Debug)
pub(all) struct Specifier {
  op : SpecifierOp
  raw_version : String
  version : Version?
  wildcard : Bool
}

///|
pub extend Specifier with @debug.Debug::{to_repr}

///|
#derive(@debug.Debug)
pub(all) struct SpecifierSet {
  specs : Array[Specifier]
  original : String
}

///|
pub extend SpecifierSet with @debug.Debug::{to_repr}

///|
pub extend SpecifierSet with Show::{output}

///|
fn split_specifier_list(input : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  for i = 0; i < input.length(); i = i + 1 {
    if input[i].to_int() == 44 {
      let part = input[start:i].to_owned().trim().to_owned()
      if !part.is_empty() {
        out.push(part)
      }
      start = i + 1
    }
  }
  let part = input[start:input.length()].to_owned().trim().to_owned()
  if !part.is_empty() {
    out.push(part)
  }
  out
}

///|
fn parse_operator(text : String) -> (SpecifierOp, Int32) raise VersionError {
  if text.has_prefix("===") {
    (ArbitraryEqual, 3)
  } else if text.has_prefix("~=") {
    (Compatible, 2)
  } else if text.has_prefix("==") {
    (Equal, 2)
  } else if text.has_prefix("!=") {
    (NotEqual, 2)
  } else if text.has_prefix("<=") {
    (LessEqual, 2)
  } else if text.has_prefix(">=") {
    (GreaterEqual, 2)
  } else if text.has_prefix("<") {
    (Less, 1)
  } else if text.has_prefix(">") {
    (Greater, 1)
  } else {
    raise VersionError::InvalidSpecifier("INVALID_OPERATOR", 0)
  }
}

///|
/// PEP 440 allows whitespace around a specifier and, in practice, right after
/// the operator, but never inside the version operand: packaging parses the
/// operand with a whitespace free pattern.
fn has_ascii_whitespace(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 32 || c == 9 || c == 10 || c == 11 || c == 12 || c == 13 {
      return true
    }
  }
  false
}

///|
/// The arbitrary equality operator keeps the operand verbatim, so the
/// characters packaging forbids there (`\s`, `;` and `)`) are rejected here.
fn has_arbitrary_separator(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 59 || c == 41 {
      return true
    }
  }
  false
}

///|
fn parse_specifier(text : String) -> Specifier raise VersionError {
  let s = text.trim().to_owned()
  if s.is_empty() {
    raise VersionError::InvalidSpecifier("EMPTY_SPECIFIER", 0)
  }
  let (op, start) = parse_operator(s)
  let mut version_part = s[start:s.length()].to_owned().trim().to_owned()
  if op == ArbitraryEqual {
    if has_ascii_whitespace(version_part) ||
      has_arbitrary_separator(version_part) {
      raise VersionError::InvalidSpecifier("INVALID_ARBITRARY_VERSION", start)
    }
    return { op, raw_version: version_part, version: None, wildcard: false, }
  }
  if version_part.is_empty() {
    raise VersionError::InvalidSpecifier("EMPTY_VERSION", start)
  }
  if has_ascii_whitespace(version_part) {
    raise VersionError::InvalidSpecifier("INVALID_VERSION_CHAR", start)
  }
  let mut wildcard = false
  if version_part.has_suffix(".*") {
    if op != Equal && op != NotEqual {
      raise VersionError::InvalidSpecifier("WILDCARD_REQUIRES_EQ", start)
    }
    if version_part.length() < 2 {
      raise VersionError::InvalidSpecifier("INVALID_WILDCARD", start)
    }
    version_part = version_part[0:version_part.length() - 2].to_owned()
    wildcard = true
  }
  let v = Version::parse(version_part)
  if v.local_segments.length() > 0 && op != Equal && op != NotEqual {
    raise VersionError::InvalidSpecifier("LOCAL_REQUIRES_EQ", start)
  }
  if wildcard {
    if v.has_pre || v.has_post || v.has_dev || v.local_segments.length() > 0 {
      raise VersionError::InvalidSpecifier("INVALID_WILDCARD_PREFIX", start)
    }
  }
  if op == Compatible && v.release.length() < 2 {
    raise VersionError::InvalidSpecifier(
      "COMPATIBLE_RELEASE_NEEDS_TWO_SEGMENTS", start,
    )
  }
  { op, raw_version: version_part, version: Some(v), wildcard, }
}

///|
/// The operator as written, used when re-rendering a specifier.
fn SpecifierOp::symbol(self : SpecifierOp) -> String {
  match self {
    Equal => "=="
    NotEqual => "!="
    Less => "<"
    LessEqual => "<="
    Greater => ">"
    GreaterEqual => ">="
    Compatible => "~="
    ArbitraryEqual => "==="
  }
}

///|
/// Render a specifier back to text. The operand keeps the caller's spelling
/// (`==V1.0` stays `==V1.0`) and only surrounding whitespace is dropped, which
/// is what `packaging` does.
pub fn Specifier::to_string(self : Specifier) -> String {
  let operand = if self.wildcard {
    self.raw_version + ".*"
  } else {
    self.raw_version
  }
  self.op.symbol() + operand
}

///|
/// Render a constraint set in its canonical form: clauses are deduplicated and
/// sorted by code point, then joined with commas. `>=2.0,<3.0` therefore
/// renders as `<3.0,>=2.0`.
pub fn SpecifierSet::to_string(self : SpecifierSet) -> String {
  let rendered : Array[String] = []
  for spec in self.specs {
    let text = spec.to_string()
    if !rendered.contains(text) {
      rendered.push(text)
    }
  }
  rendered.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  rendered.join(",")
}

///|
pub impl Show for SpecifierSet with fn to_string(self) {
  self.to_string()
}

///|
pub fn SpecifierSet::parse(input : String) -> SpecifierSet raise VersionError {
  let specs : Array[Specifier] = []
  let parts = split_specifier_list(input)
  for i = 0; i < parts.length(); i = i + 1 {
    specs.push(parse_specifier(parts[i]))
  }
  { specs, original: input, }
}

///|
fn version_is_prerelease(v : Version) -> Bool {
  v.has_pre || v.has_dev
}

///|
fn compatible_upper(v : Version) -> Version {
  let release : Array[@bigint.BigInt] = []
  for i = 0; i < v.release.length(); i = i + 1 {
    release.push(v.release[i])
  }
  let idx = release.length() - 2
  release[idx] = release[idx].add(@bigint.BigInt::from_int(1))
  release[release.length() - 1] = @bigint.BigInt::from_int(0)
  {
    raw: "",
    epoch: v.epoch,
    release,
    has_pre: false,
    pre_kind: 0,
    pre_num: @bigint.BigInt::from_int(0),
    has_post: false,
    post_num: @bigint.BigInt::from_int(0),
    has_dev: false,
    dev_num: @bigint.BigInt::from_int(0),
    local_segments: [],
  }
}

///|
fn matches_wildcard_prefix(v : Version, prefix : Version) -> Bool {
  if v.epoch.compare(prefix.epoch) != 0 {
    return false
  }
  for i = 0; i < prefix.release.length(); i = i + 1 {
    let segment = if i < v.release.length() {
      v.release[i]
    } else {
      @bigint.BigInt::from_int(0)
    }
    if segment.compare(prefix.release[i]) != 0 {
      return false
    }
  }
  true
}

///|
fn compatible_contains(v : Version, spec_v : Version) -> Bool {
  let lower_ok = compare_without_local(v, spec_v) >= 0
  if !lower_ok {
    return false
  }
  let upper = compatible_upper(spec_v)
  let upper_ok = compare_without_local(v, upper) < 0
  if !upper_ok {
    return false
  }
  if version_is_prerelease(v) &&
    compare_bigint_arrays(v.release, upper.release) == 0 {
    return false
  }
  true
}

///|
fn compare_without_local(left : Version, right : Version) -> Int32 {
  let l = { ..left, local_segments: [], }
  let r = { ..right, local_segments: [], }
  l.compare(r)
}

///|
fn specifier_contains(spec : Specifier, version : Version) -> Bool {
  if spec.op == ArbitraryEqual {
    return version.to_string().to_lower() == spec.raw_version.to_lower()
  }
  let spec_v = match spec.version {
    Some(v) => v
    None => return false
  }
  if spec.wildcard {
    let matched = matches_wildcard_prefix(version, spec_v)
    return if spec.op == Equal { matched } else { !matched }
  }
  let equal_cmp = if spec_v.local_segments.length() == 0 {
    compare_without_local(version, spec_v) == 0
  } else {
    version.compare(spec_v) == 0
  }
  let basic = match spec.op {
    Equal => equal_cmp
    NotEqual => !equal_cmp
    Less => compare_without_local(version, spec_v) < 0
    LessEqual => compare_without_local(version, spec_v) <= 0
    Greater => compare_without_local(version, spec_v) > 0
    GreaterEqual => compare_without_local(version, spec_v) >= 0
    Compatible => compatible_contains(version, spec_v)
    ArbitraryEqual => false
  }
  if !basic {
    return false
  }
  if spec.op == Less &&
    version_is_prerelease(version) &&
    !version_is_prerelease(spec_v) {
    let earliest = {
      ..spec_v,
      has_dev: true,
      dev_num: @bigint.BigInt::from_int(0),
      local_segments: [],
    }
    if compare_without_local(version, earliest) >= 0 {
      return false
    }
  }
  if spec.op == Greater && !spec_v.has_post && version.has_post {
    let without_post = {
      ..version,
      has_post: false,
      has_dev: false,
      local_segments: [],
    }
    if compare_without_local(without_post, spec_v) == 0 {
      return false
    }
  }
  true
}

///|
fn SpecifierSet::allows_prereleases(self : SpecifierSet) -> Bool {
  for spec in self.specs {
    if spec.op != NotEqual {
      let candidate = match spec.version {
        Some(v) => Some(v)
        None => Some(Version::parse(spec.raw_version)) catch { _ => None }
      }
      if candidate is Some(v) && version_is_prerelease(v) {
        return true
      }
    }
  }
  false
}

///|

///|
/// Parse one constraint term (e.g. ">=1.4" or "!=1.4.*") without the
/// surrounding set syntax; mirrors pypa/packaging's Specifier constructor.
pub fn Specifier::parse(input : String) -> Self raise VersionError {
  parse_specifier(input)
}

///|
/// ```mbt check
/// test {
///   let spec = @moon_pyversion.Specifier::parse(">=1.4")
///   let hit = @moon_pyversion.Version::parse("1.5")
///   inspect(@moon_pyversion.Specifier::contains(spec, hit), content="true")
/// }
/// ```
pub fn Specifier::contains(
  self : Specifier,
  version : Version,
  prereleases~ : Bool? = None,
) -> Bool {
  if version_is_prerelease(version) && prereleases == Some(false) {
    return false
  }
  specifier_contains(self, version)
}

///|
pub fn SpecifierSet::contains(
  self : SpecifierSet,
  version : Version,
  prereleases~ : Bool? = None,
) -> Bool {
  // packaging >=26: a single candidate has no stable alternative, so the
  // automatic policy permits prereleases. filter has the full candidate set.
  let allow_pre = prereleases.unwrap_or(true)
  if version_is_prerelease(version) && !allow_pre {
    return false
  }
  for i = 0; i < self.specs.length(); i = i + 1 {
    if !specifier_contains(self.specs[i], version) {
      return false
    }
  }
  true
}

///|
/// ```mbt check
/// test {
///   let spec = @moon_pyversion.SpecifierSet::parse(">=1.0, <2.0")
///   let candidates = [
///     @moon_pyversion.Version::parse("0.9"),
///     @moon_pyversion.Version::parse("1.5"),
///   ]
///   inspect(
///     @moon_pyversion.SpecifierSet::filter(candidates, spec).length(),
///     content="1",
///   )
/// }
/// ```
pub fn SpecifierSet::filter(
  versions : Array[Version],
  spec : SpecifierSet,
  prereleases~ : Bool? = None,
) -> Array[Version] {
  let out : Array[Version] = []
  let pre : Array[Version] = []
  let explicit = prereleases.unwrap_or(spec.allows_prereleases())
  for i = 0; i < versions.length(); i = i + 1 {
    if spec.contains(versions[i], prereleases=Some(true)) {
      if version_is_prerelease(versions[i]) && !explicit {
        pre.push(versions[i])
      } else {
        out.push(versions[i])
      }
    }
  }
  if out.is_empty() && prereleases is None {
    pre
  } else {
    out
  }
}

///|
/// A minimal "0" version, for the unreachable branches below.
fn zero_version() -> Version {
  {
    raw: "",
    epoch: @bigint.BigInt::from_int(0),
    release: [@bigint.BigInt::from_int(0)],
    has_pre: false,
    pre_kind: 0,
    pre_num: @bigint.BigInt::from_int(0),
    has_post: false,
    post_num: @bigint.BigInt::from_int(0),
    has_dev: false,
    dev_num: @bigint.BigInt::from_int(0),
    local_segments: [],
  }
}

///|
/// The operand of an ordered clause (`>`, `<`, `>=`, `<=`, `~=`), all of
/// which always carry a parsed version.
fn spec_operand(s : Specifier) -> Version {
  match s.version {
    Some(v) => v
    None => zero_version()
  }
}

///|
/// True when both operands share an epoch and release digits. This is where
/// packaging's carve-outs live - a `>` clause does not admit the
/// post-releases of its operand, a `<` clause does not admit the
/// pre-releases sitting at its operand - so it is exactly where an
/// "implied" clause could stop being implied: inside one family the ordered
/// clauses are not pure intervals.
fn same_release_family(a : Version, b : Version) -> Bool {
  a.epoch.compare(b.epoch) == 0 &&
  compare_bigint_arrays(a.release, b.release) == 0
}

///|
/// A version with one extra textual local segment, used to probe whether a
/// clause treats every local variant of a pin alike: a clause that admits
/// both the pin and this probe is local-agnostic over the pin's family.
fn with_probe_local(v : Version) -> Version {
  let segments : Array[LocalPart] = []
  for segment in v.local_segments {
    segments.push(segment)
  }
  segments.push({ text: "zz", numeric: false, })
  { ..v, local_segments: segments, }
}

///|
/// Whether an `==pin` clause (non-wildcard) already decides `clause`: the
/// clause must admit the whole family the pin admits, not just the pin's
/// own spelling. A pin that carries local segments admits exactly one
/// version, so admitting the pin is admitting the family; a local-less pin
/// admits the local family of its release, so the clause must also admit a
/// probed local variant. A verbatim `===` compares spellings, and a `!=`
/// with local in its operand can still split a local family, so both are
/// conservatively kept.
fn pin_admits_clause(pin : Specifier, clause : Specifier) -> Bool {
  let pinned = match pin.version {
    Some(v) => v
    None => return false
  }
  if pinned.local_segments.length() > 0 {
    return specifier_contains(clause, pinned)
  }
  if clause.op == ArbitraryEqual {
    return false
  }
  if clause.op == NotEqual {
    match clause.version {
      Some(v) => if v.local_segments.length() > 0 { return false }
      None => ()
    }
  }
  specifier_contains(clause, pinned) &&
  specifier_contains(clause, with_probe_local(pinned))
}

///|
/// Collapse the lower (or upper) ordered bounds to the single strongest
/// clause, dropping a bound only when the survivor provably implies it. A
/// dropped `>=`/`<=` is implied by anything beyond it, but a dropped `>` is
/// implied only outside the survivor's release family (the post-release
/// carve-out), and a dropped `<` only outside it or when its own operand is
/// a pre or dev release (the pre-release carve-out). Both guards err toward
/// keeping a clause, so the merged set never admits a version the original
/// rejected.
fn merge_bounds(specs : Array[Specifier], lower : Bool) -> Array[Specifier] {
  let mut best : Int32 = -1
  for i = 0; i < specs.length(); i = i + 1 {
    let op = specs[i].op
    let is_bound = if lower {
      op == Greater || op == GreaterEqual
    } else {
      op == Less || op == LessEqual
    }
    if is_bound {
      if best < 0 {
        best = i
      } else {
        let order = compare_without_local(
          spec_operand(specs[i]),
          spec_operand(specs[best]),
        )
        // Lower bounds want the greatest operand, upper bounds the smallest;
        // at equal operands the strict operator is the stronger claim.
        let takes = if lower {
          order > 0 ||
          (order == 0 && op == Greater && specs[best].op == GreaterEqual)
        } else {
          order < 0 || (order == 0 && op == Less && specs[best].op == LessEqual)
        }
        if takes {
          best = i
        }
      }
    }
  }
  if best < 0 {
    return specs
  }
  let winner = spec_operand(specs[best])
  let out : Array[Specifier] = []
  for i = 0; i < specs.length(); i = i + 1 {
    let op = specs[i].op
    let is_bound = if lower {
      op == Greater || op == GreaterEqual
    } else {
      op == Less || op == LessEqual
    }
    if is_bound && i != best {
      let operand = spec_operand(specs[i])
      // Dropping `>b` (or `<b`) is unsound inside one release family:
      // the family's post-releases sit above b yet are carved out of `>b`,
      // and the pre-releases sitting at a final b are carved out of `<b`.
      // Elsewhere, a `>=`/`<=` is implied by anything beyond it and a
      // same-strictness `>`/`<` by a strictly stronger operand.
      let droppable = if lower {
        op == GreaterEqual ||
        operand.has_post ||
        !same_release_family(winner, operand)
      } else {
        op == LessEqual ||
        version_is_prerelease(operand) ||
        !same_release_family(winner, operand)
      }
      if !droppable {
        out.push(specs[i])
      }
    } else {
      out.push(specs[i])
    }
  }
  out
}

///|
/// Merge redundant clauses into an equivalent set with fewer clauses. A
/// clause is dropped only when a kept clause provably implies it, so the
/// simplified set admits exactly the versions the original admitted:
///
/// - duplicate renderings collapse to one;
/// - the ordered lower bounds (`>`, `>=`) reduce to the single strongest
///   clause, and the upper bounds (`<`, `<=`) likewise;
/// - when the set pins exact versions (`==v`, non-wildcard), every clause
///   that admits all the pins is dropped - the pins already decide those.
///
/// `===`, `~=` and wildcard clauses keep their shape in all cases (their
/// pre/post-release carve-outs make pure interval merging unsound), and a
/// bound is kept rather than dropped when it shares a release family with
/// the surviving bound - `<2.0` excludes `2.0.dev*`, so `<=2.0.dev3,<2.0`
/// does not reduce, and neither does `>=1.0.post1,>1.0`.
///
/// ```mbt check
/// test {
///   let spec = @moon_pyversion.SpecifierSet::parse(">=1.0,>=1.5,<3")
///   inspect(
///     @moon_pyversion.SpecifierSet::simplify(spec).to_string(),
///     content="<3,>=1.5",
///   )
/// }
/// ```
pub fn SpecifierSet::simplify(self : SpecifierSet) -> SpecifierSet {
  // Duplicates collapse; the rendering is the identity packaging uses.
  let mut kept : Array[Specifier] = []
  for spec in self.specs {
    let mut seen = false
    for existing in kept {
      if existing.to_string() == spec.to_string() {
        seen = true
        break
      }
    }
    if !seen {
      kept.push(spec)
    }
  }
  // Exact pins first: with at least one `==v`, a clause that admits every
  // pin cannot reject anything the pins keep, so it goes; the pins stay.
  let pins : Array[Specifier] = []
  for spec in kept {
    if spec.op == Equal && !spec.wildcard {
      pins.push(spec)
    }
  }
  if pins.length() > 0 {
    let reduced : Array[Specifier] = []
    for spec in kept {
      let mut is_pin = false
      for pin in pins {
        if pin.to_string() == spec.to_string() {
          is_pin = true
          break
        }
      }
      let mut implied = true
      if !is_pin {
        for pin in pins {
          if !pin_admits_clause(pin, spec) {
            implied = false
            break
          }
        }
      }
      if is_pin || !implied {
        reduced.push(spec)
      }
    }
    kept = reduced
  } else {
    // No pin: collapse the ordered bounds on each side.
    kept = merge_bounds(kept, true)
    kept = merge_bounds(kept, false)
  }
  // Canonical order, and the rendering becomes the new original.
  kept.sort_by(fn(a, b) {
    String::lexical_compare(a.to_string(), b.to_string())
  })
  let rendered : Array[String] = []
  for spec in kept {
    rendered.push(spec.to_string())
  }
  { specs: kept, original: rendered.join(","), }
}

///|
/// True for the operators that order versions rather than pin or exclude.
fn is_ordered_op(op : SpecifierOp) -> Bool {
  op == Less ||
  op == LessEqual ||
  op == Greater ||
  op == GreaterEqual ||
  op == Compatible
}

///|
/// The exact version a clause pins, when it does: a non-wildcard `==v`, or
/// a `===x` whose operand happens to parse as a version.
fn pinned_version(spec : Specifier) -> Version? {
  if spec.op == Equal && !spec.wildcard {
    return spec.version
  }
  if spec.op == ArbitraryEqual {
    return Some(Version::parse(spec.raw_version)) catch { _ => None }
  }
  None
}

///|
/// The lower interval edge of an ordered clause: `>v` strict, `>=v`
/// closed, `~=v` closed at its own operand.
fn lower_edge(spec : Specifier) -> (Version, Bool)? {
  match spec.op {
    Greater => Some((spec_operand(spec), true))
    GreaterEqual => Some((spec_operand(spec), false))
    Compatible => Some((spec_operand(spec), false))
    _ => None
  }
}

///|
/// The upper interval edge of an ordered clause: `<v` strict, `<=v`
/// closed, `~=v` strict below its compatible-release bound.
fn upper_edge(spec : Specifier) -> (Version, Bool)? {
  match spec.op {
    Less => Some((spec_operand(spec), true))
    LessEqual => Some((spec_operand(spec), false))
    Compatible => Some((compatible_upper(spec_operand(spec)), true))
    _ => None
  }
}

///|
/// Whether a lower edge and an upper edge leave nothing between them: the
/// operands cross, or meet with at least one strict side.
fn edges_order_disjoint(
  x : Version,
  strict_lower : Bool,
  y : Version,
  strict_upper : Bool,
) -> Bool {
  let order = compare_without_local(x, y)
  order > 0 || (order == 0 && (strict_lower || strict_upper))
}

///|
/// The first release above a wildcard prefix's family: the prefix with its
/// last digit incremented (`1.4` -> `1.5`).
fn wildcard_ceiling(prefix : Version) -> Version {
  let release : Array[@bigint.BigInt] = []
  for i = 0; i < prefix.release.length(); i = i + 1 {
    release.push(prefix.release[i])
  }
  let last = release.length() - 1
  release[last] = release[last].add(@bigint.BigInt::from_int(1))
  {
    raw: "",
    epoch: prefix.epoch,
    release,
    has_pre: false,
    pre_kind: 0,
    pre_num: @bigint.BigInt::from_int(0),
    has_post: false,
    post_num: @bigint.BigInt::from_int(0),
    has_dev: false,
    dev_num: @bigint.BigInt::from_int(0),
    local_segments: [],
  }
}

///|
/// The smallest version sharing the wildcard prefix's release: the prefix
/// with a `.dev0` appended (`1.4` -> `1.4.dev0`). A wildcard parse never
/// carries pre/post/dev parts, so the spread is exactly this one field.
fn wildcard_floor(prefix : Version) -> Version {
  { ..prefix, has_dev: true, dev_num: @bigint.BigInt::from_int(0), }
}

///|
/// Whether two wildcard prefixes can match one release: same epoch and no
/// differing digit within the shorter prefix.
fn wildcard_prefix_agrees(p : Version, q : Version) -> Bool {
  if p.epoch.compare(q.epoch) != 0 {
    return false
  }
  let shared = Int32::min(p.release.length(), q.release.length())
  for i = 0; i < shared; i = i + 1 {
    if p.release[i].compare(q.release[i]) != 0 {
      return false
    }
  }
  true
}

///|
/// Whether everything matching the `eq` prefix also matches the `ne`
/// prefix - the family `!=ne` removes wholesale.
fn wildcard_prefix_within(eq : Version, ne : Version) -> Bool {
  ne.release.length() <= eq.release.length() && wildcard_prefix_agrees(eq, ne)
}

///|
/// Whether a wildcard family and an ordered clause can share no version:
/// the family lives between its floor and its ceiling, so the check is the
/// same edge logic with the family's own bounds.
fn wildcard_bound_disjoint(prefix : Version, spec : Specifier) -> Bool {
  match lower_edge(spec) {
    Some((x, _)) =>
      if compare_without_local(wildcard_ceiling(prefix), x) <= 0 {
        return true
      }
    None => ()
  }
  match upper_edge(spec) {
    Some((y, strict)) => {
      // The floor is the family's smallest member: `<y` finds nothing when
      // y sits at or under the floor, `<=y` when y sits strictly under.
      let order = compare_without_local(wildcard_floor(prefix), y)
      if strict {
        if order >= 0 {
          return true
        }
      } else if order > 0 {
        return true
      }
    }
    None => ()
  }
  false
}

///|
/// Whether two clauses of a constraint set provably admit no common
/// version - sufficient conditions only. Anything subtler (the prerelease
/// and post-release carve-outs, two exclusions, a `!=` against a range)
/// answers false, so a false here never means "compatible", only "not
/// proven disjoint".
fn clauses_disjoint(a : Specifier, b : Specifier) -> Bool {
  // A pinned version on either side decides: the other clause must admit
  // that exact version, or the two share nothing.
  match pinned_version(a) {
    Some(v) => if !specifier_contains(b, v) { return true }
    None => ()
  }
  match pinned_version(b) {
    Some(v) => if !specifier_contains(a, v) { return true }
    None => ()
  }
  let a_eq_wild = a.op == Equal && a.wildcard
  let b_eq_wild = b.op == Equal && b.wildcard
  let a_ne_wild = a.op == NotEqual && a.wildcard
  let b_ne_wild = b.op == NotEqual && b.wildcard
  if a_eq_wild && b_eq_wild {
    return !wildcard_prefix_agrees(spec_operand(a), spec_operand(b))
  }
  if a_eq_wild && b_ne_wild {
    return wildcard_prefix_within(spec_operand(a), spec_operand(b))
  }
  if a_ne_wild && b_eq_wild {
    return wildcard_prefix_within(spec_operand(b), spec_operand(a))
  }
  if a_eq_wild && is_ordered_op(b.op) {
    return wildcard_bound_disjoint(spec_operand(a), b)
  }
  if b_eq_wild && is_ordered_op(a.op) {
    return wildcard_bound_disjoint(spec_operand(b), a)
  }
  // Two ordered clauses: disjoint when either lower edge passes either
  // upper edge.
  match (lower_edge(a), upper_edge(b)) {
    (Some(la), Some(ub)) =>
      if edges_order_disjoint(la.0, la.1, ub.0, ub.1) {
        return true
      }
    _ => ()
  }
  match (upper_edge(a), lower_edge(b)) {
    (Some(ua), Some(lb)) =>
      if edges_order_disjoint(lb.0, lb.1, ua.0, ua.1) {
        return true
      }
    _ => ()
  }
  false
}

///|
/// Whether two constraint sets can share no version: any clause of one
/// excluding any clause of the other, or either set contradicting itself -
/// a set that admits nothing conflicts with every set, which is what an
/// upgrade tool needs to hear about `foo==1.0,==2.0`.
fn specifier_sets_disjoint(a : SpecifierSet, b : SpecifierSet) -> Bool {
  for i = 0; i < a.specs.length(); i = i + 1 {
    for j = 0; j < b.specs.length(); j = j + 1 {
      if clauses_disjoint(a.specs[i], b.specs[j]) {
        return true
      }
    }
  }
  for i = 0; i < a.specs.length(); i = i + 1 {
    for j = i + 1; j < a.specs.length(); j = j + 1 {
      if clauses_disjoint(a.specs[i], a.specs[j]) {
        return true
      }
    }
  }
  for i = 0; i < b.specs.length(); i = i + 1 {
    for j = i + 1; j < b.specs.length(); j = j + 1 {
      if clauses_disjoint(b.specs[i], b.specs[j]) {
        return true
      }
    }
  }
  false
}

///|
/// Whether two constraint sets can admit at least one common version - the
/// batch form of the question `Requirement::conflicts_with` asks about two
/// requirements, without the name and marker layers. This is the operation
/// a dependency-graph pass runs over every pair of pins at once.
///
/// True means "no disjointness proven": the underlying reasoning proves
/// emptiness from sufficient conditions only (pins against anything,
/// wildcard families against each other and against interval edges, `~=`
/// expanded to its compatible-release range, ordered bounds that cross),
/// so a subtler emptiness - two `!=` clauses, the prerelease and
/// post-release carve-outs - answers true. False is a proof: the two sets
/// provably share no version. A set that contradicts itself
/// (`foo==1.0,==2.0`) admits nothing and therefore intersects nothing,
/// not even an empty set.
///
/// ```mbt check
/// test {
///   let range = @moon_pyversion.SpecifierSet::parse(">=2.0")
///   let below = @moon_pyversion.SpecifierSet::parse("<2.0")
///   inspect(
///     @moon_pyversion.SpecifierSet::intersects(range, below),
///     content="false",
///   )
///   let pin = @moon_pyversion.SpecifierSet::parse("==2.0")
///   inspect(@moon_pyversion.SpecifierSet::intersects(range, pin), content="true")
/// }
/// ```
pub fn SpecifierSet::intersects(
  self : SpecifierSet,
  other : SpecifierSet,
) -> Bool {
  !specifier_sets_disjoint(self, other)
}
