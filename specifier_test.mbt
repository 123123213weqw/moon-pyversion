///|
fn specifier_accepted(input : String) -> Bool {
  try {
    ignore(SpecifierSet::parse(input))
    true
  } catch {
    _ => false
  }
}

///|
fn specifier_rejected(input : String) -> Bool {
  try {
    ignore(SpecifierSet::parse(input))
    false
  } catch {
    _ => true
  }
}

///|
test "specifier set applies every clause" {
  let spec = SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  assert_true(spec.contains(Version::parse("1.0")))
  assert_true(spec.contains(Version::parse("1.5")))
  assert_true(spec.contains(Version::parse("1.9.7")))
  assert_false(spec.contains(Version::parse("0.9")))
  assert_false(spec.contains(Version::parse("1.4")))
  assert_false(spec.contains(Version::parse("1.4.1")))
  assert_false(spec.contains(Version::parse("2.0")))
}

///|
test "wildcard equality and exclusion match release prefixes" {
  let eq = SpecifierSet::parse("==1.1.*")
  assert_true(eq.contains(Version::parse("1.1")))
  assert_true(eq.contains(Version::parse("1.1.5")))
  assert_true(eq.contains(Version::parse("1.1a1")))
  assert_true(eq.contains(Version::parse("1.1a1"), prereleases=Some(true)))
  assert_false(eq.contains(Version::parse("1.2")))

  let ne = SpecifierSet::parse("!=1.1.*")
  assert_false(ne.contains(Version::parse("1.1")))
  assert_false(ne.contains(Version::parse("1.1.5")))
  assert_true(ne.contains(Version::parse("1.2")))
}

///|
test "compatible release has inclusive lower and exclusive upper bound" {
  let spec = SpecifierSet::parse("~=1.4.5")
  assert_true(spec.contains(Version::parse("1.4.5")))
  assert_true(spec.contains(Version::parse("1.4.9")))
  assert_false(spec.contains(Version::parse("1.4")))
  assert_false(spec.contains(Version::parse("1.5")))

  let two = SpecifierSet::parse("~=1.4")
  assert_true(two.contains(Version::parse("1.4")))
  assert_true(two.contains(Version::parse("1.5")))
  assert_false(two.contains(Version::parse("2.0")))
}

///|
test "arbitrary equality compares normalized version spelling case insensitively" {
  let exact = SpecifierSet::parse("===1.0")
  assert_true(exact.contains(Version::parse("1.0")))
  assert_false(exact.contains(Version::parse("1.0.0")))
  let legacy = SpecifierSet::parse("===foobar")
  assert_false(legacy.contains(Version::parse("1.0")))
}

///|
test "pre-release boundary behavior for ordered and equality specifiers" {
  let ge = SpecifierSet::parse(">=1.0")
  assert_false(ge.contains(Version::parse("1.0a1")))
  assert_true(ge.contains(Version::parse("1.1a1")))
  assert_true(ge.contains(Version::parse("1.1a1"), prereleases=Some(true)))

  let eq = SpecifierSet::parse("==1.0")
  assert_false(eq.contains(Version::parse("1.0a1")))

  let explicit = SpecifierSet::parse(">=1.0a1")
  assert_true(explicit.contains(Version::parse("1.0a1")))

  let ne = SpecifierSet::parse("!=1.0")
  assert_true(ne.contains(Version::parse("1.0a1")))
}

///|
test "strict upper bound excludes the boundary prerelease" {
  let lt = SpecifierSet::parse("<2.0")
  assert_false(lt.contains(Version::parse("2.0a1")))
  assert_true(lt.contains(Version::parse("1.9a1"), prereleases=Some(true)))
  let le = SpecifierSet::parse("<=2.0")
  assert_true(le.contains(Version::parse("2.0a1"), prereleases=Some(true)))
}

///|
test "filter returns only versions accepted by the set" {
  let versions = [
    Version::parse("1.0"),
    Version::parse("1.4"),
    Version::parse("1.4.9"),
    Version::parse("1.5"),
    Version::parse("2.0"),
  ]
  let spec = SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  let filtered = SpecifierSet::filter(versions, spec)
  assert_eq(filtered.length(), 2)
  assert_eq(Version::to_string(filtered[0]), "1.0")
  assert_eq(Version::to_string(filtered[1]), "1.5")
}

///|
test "empty specifier contains uses single-candidate prerelease fallback" {
  let spec = SpecifierSet::parse("")
  assert_true(spec.contains(Version::parse("0")))
  assert_true(spec.contains(Version::parse("1.0a1")))
  assert_false(spec.contains(Version::parse("1.0a1"), prereleases=Some(false)))
}

///|
test "invalid specifier strings are rejected" {
  let bad : Array[String] = [
    "==*", "~=1", ">", "==1.0.*.*", "==1.0a1.*", ">1.0.*", "===foobar, ~=1",
  ]
  for i = 0; i < bad.length(); i = i + 1 {
    assert_true(specifier_rejected(bad[i]))
  }
}

///|
/// packaging anchors its operand patterns with `\\s*` around the whole
/// specifier but never inside the version operand, so whitespace between the
/// operator and the version is fine while whitespace inside it is an error.
test "whitespace is allowed around a specifier but not inside the operand" {
  assert_true(specifier_accepted("  ==  1.0  "))
  assert_true(specifier_accepted(">= 1.0, <= 2.0"))
  for raw in ["!=2.0 .*", ">=1.0 <=2.0", "==1.0 2.0", ">1 .0", "<1.0. 0"] {
    assert_true(specifier_rejected(raw))
  }
}

///|
/// The arbitrary equality operator is a verbatim string match, but packaging
/// still refuses whitespace, `;` and `)` in its operand.
test "arbitrary equality keeps packaging's operand restrictions" {
  assert_true(specifier_accepted("===1.0+ABC"))
  assert_true(specifier_accepted("===1.0"))
  for raw in ["===V012.2.3P OST_5", "===_ 10_r-0 ", "===1.0;x", "===1.0)"] {
    assert_true(specifier_rejected(raw))
  }
}
