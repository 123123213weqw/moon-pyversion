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
test "arbitrary equality compares the raw string" {
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
  assert_true(lt.contains(Version::parse("1.9a1")))
  let le = SpecifierSet::parse("<=2.0")
  assert_true(le.contains(Version::parse("2.0a1")))
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
test "empty specifier set accepts every version" {
  let spec = SpecifierSet::parse("")
  assert_true(spec.contains(Version::parse("0")))
  assert_true(spec.contains(Version::parse("1.0a1")))
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
