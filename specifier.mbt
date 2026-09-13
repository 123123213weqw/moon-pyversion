///|
pub(all) enum SpecifierOp {
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  Compatible
  ArbitraryEqual
} derive(Eq, @debug.Debug)

///|
pub(all) struct Specifier {
  op : SpecifierOp
  raw_version : String
  version : Version?
  wildcard : Bool
} derive(@debug.Debug)

///|
pub(all) struct SpecifierSet {
  specs : Array[Specifier]
  original : String
} derive(@debug.Debug)

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
fn parse_operator(text : String) -> (SpecifierOp, Int) raise VersionError {
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
    return { op, raw_version: version_part, version: None, wildcard: false }
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
  { op, raw_version: version_part, version: Some(v), wildcard }
}

///|
pub fn SpecifierSet::parse(input : String) -> SpecifierSet raise VersionError {
  let specs : Array[Specifier] = []
  let parts = split_specifier_list(input)
  for i = 0; i < parts.length(); i = i + 1 {
    specs.push(parse_specifier(parts[i]))
  }
  { specs, original: input }
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
fn compare_without_local(left : Version, right : Version) -> Int {
  let l = { ..left, local_segments: [] }
  let r = { ..right, local_segments: [] }
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
pub fn SpecifierSet::contains(
  self : SpecifierSet,
  version : Version,
  prereleases? : Bool? = None,
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
pub fn SpecifierSet::filter(
  versions : Array[Version],
  spec : SpecifierSet,
  prereleases? : Bool? = None,
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
