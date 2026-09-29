///|
fn specifier_accepted(input : String) -> Bool {
  try {
    ignore(@moon_pyversion.SpecifierSet::parse(input))
    true
  } catch {
    _ => false
  }
}

///|
fn specifier_rejected(input : String) -> Bool {
  try {
    ignore(@moon_pyversion.SpecifierSet::parse(input))
    false
  } catch {
    _ => true
  }
}

///|
test "specifier set applies every clause" {
  let spec = @moon_pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.0")))
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.5")))
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.9.7")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("0.9")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("1.4")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("1.4.1")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("2.0")))
}

///|
test "wildcard equality and exclusion match release prefixes" {
  let eq = @moon_pyversion.SpecifierSet::parse("==1.1.*")
  assert_true(eq.contains(@moon_pyversion.Version::parse("1.1")))
  assert_true(eq.contains(@moon_pyversion.Version::parse("1.1.5")))
  assert_true(eq.contains(@moon_pyversion.Version::parse("1.1a1")))
  assert_true(
    eq.contains(@moon_pyversion.Version::parse("1.1a1"), prereleases=Some(true)),
  )
  assert_false(eq.contains(@moon_pyversion.Version::parse("1.2")))

  let ne = @moon_pyversion.SpecifierSet::parse("!=1.1.*")
  assert_false(ne.contains(@moon_pyversion.Version::parse("1.1")))
  assert_false(ne.contains(@moon_pyversion.Version::parse("1.1.5")))
  assert_true(ne.contains(@moon_pyversion.Version::parse("1.2")))
}

///|
test "compatible release has inclusive lower and exclusive upper bound" {
  let spec = @moon_pyversion.SpecifierSet::parse("~=1.4.5")
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.4.5")))
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.4.9")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("1.4")))
  assert_false(spec.contains(@moon_pyversion.Version::parse("1.5")))

  let two = @moon_pyversion.SpecifierSet::parse("~=1.4")
  assert_true(two.contains(@moon_pyversion.Version::parse("1.4")))
  assert_true(two.contains(@moon_pyversion.Version::parse("1.5")))
  assert_false(two.contains(@moon_pyversion.Version::parse("2.0")))
}

///|
test "arbitrary equality compares normalized version spelling case insensitively" {
  let exact = @moon_pyversion.SpecifierSet::parse("===1.0")
  assert_true(exact.contains(@moon_pyversion.Version::parse("1.0")))
  assert_false(exact.contains(@moon_pyversion.Version::parse("1.0.0")))
  let legacy = @moon_pyversion.SpecifierSet::parse("===foobar")
  assert_false(legacy.contains(@moon_pyversion.Version::parse("1.0")))
}

///|
test "pre-release boundary behavior for ordered and equality specifiers" {
  let ge = @moon_pyversion.SpecifierSet::parse(">=1.0")
  assert_false(ge.contains(@moon_pyversion.Version::parse("1.0a1")))
  assert_true(ge.contains(@moon_pyversion.Version::parse("1.1a1")))
  assert_true(
    ge.contains(@moon_pyversion.Version::parse("1.1a1"), prereleases=Some(true)),
  )

  let eq = @moon_pyversion.SpecifierSet::parse("==1.0")
  assert_false(eq.contains(@moon_pyversion.Version::parse("1.0a1")))

  let explicit = @moon_pyversion.SpecifierSet::parse(">=1.0a1")
  assert_true(explicit.contains(@moon_pyversion.Version::parse("1.0a1")))

  let ne = @moon_pyversion.SpecifierSet::parse("!=1.0")
  assert_true(ne.contains(@moon_pyversion.Version::parse("1.0a1")))
}

///|
test "strict upper bound excludes the boundary prerelease" {
  let lt = @moon_pyversion.SpecifierSet::parse("<2.0")
  assert_false(lt.contains(@moon_pyversion.Version::parse("2.0a1")))
  assert_true(
    lt.contains(@moon_pyversion.Version::parse("1.9a1"), prereleases=Some(true)),
  )
  let le = @moon_pyversion.SpecifierSet::parse("<=2.0")
  assert_true(
    le.contains(@moon_pyversion.Version::parse("2.0a1"), prereleases=Some(true)),
  )
}

///|
test "filter returns only versions accepted by the set" {
  let versions = [
    @moon_pyversion.Version::parse("1.0"),
    @moon_pyversion.Version::parse("1.4"),
    @moon_pyversion.Version::parse("1.4.9"),
    @moon_pyversion.Version::parse("1.5"),
    @moon_pyversion.Version::parse("2.0"),
  ]
  let spec = @moon_pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  let filtered = @moon_pyversion.SpecifierSet::filter(versions, spec)
  assert_eq(filtered.length(), 2)
  assert_eq(@moon_pyversion.Version::to_string(filtered[0]), "1.0")
  assert_eq(@moon_pyversion.Version::to_string(filtered[1]), "1.5")
}

///|
test "empty specifier contains uses single-candidate prerelease fallback" {
  let spec = @moon_pyversion.SpecifierSet::parse("")
  assert_true(spec.contains(@moon_pyversion.Version::parse("0")))
  assert_true(spec.contains(@moon_pyversion.Version::parse("1.0a1")))
  assert_false(
    spec.contains(
      @moon_pyversion.Version::parse("1.0a1"),
      prereleases=Some(false),
    ),
  )
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
