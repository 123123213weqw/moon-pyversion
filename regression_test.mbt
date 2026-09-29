///|
test "compound suffixes stay with their parent release" {
  let ordered = [
    "1.0.dev1", "1.0a1", "1.0a2.dev1", "1.0a2", "1.0a2.post1.dev1", "1.0a2.post1",
    "1.0b1.dev1", "1.0rc1", "1.0", "1.0+abc", "1.0.post1.dev1", "1.0.post1", "1.0.post2.dev1",
  ]
  for i = 0; i < ordered.length(); i = i + 1 {
    for j = i + 1; j < ordered.length(); j = j + 1 {
      assert_true(
        @moon_pyversion.Version::parse(ordered[i]) <
        @moon_pyversion.Version::parse(ordered[j]),
      )
    }
  }
}

///|
test "wildcard pads missing release digits and preserves epoch" {
  assert_true(
    @moon_pyversion.SpecifierSet::parse("==1.0.*").contains(
      @moon_pyversion.Version::parse("1"),
    ),
  )
  assert_false(
    @moon_pyversion.SpecifierSet::parse("!=1.0.*").contains(
      @moon_pyversion.Version::parse("1"),
    ),
  )
  assert_false(
    @moon_pyversion.SpecifierSet::parse("==1.0.*").contains(
      @moon_pyversion.Version::parse("1!1"),
    ),
  )
}

///|
test "ordered constraints ignore local labels but reject local boundaries" {
  assert_false(
    @moon_pyversion.SpecifierSet::parse("<1.0.post1").contains(
      @moon_pyversion.Version::parse("1.0.post1.dev1"),
    ),
  )
  assert_true(
    @moon_pyversion.SpecifierSet::parse("<1.0.post1").contains(
      @moon_pyversion.Version::parse("1.0.post0.dev1"),
    ),
  )
  assert_true(
    @moon_pyversion.SpecifierSet::parse("<=1.0").contains(
      @moon_pyversion.Version::parse("1.0+abc"),
    ),
  )
  assert_false(
    @moon_pyversion.SpecifierSet::parse(">1.0").contains(
      @moon_pyversion.Version::parse("1.0+abc"),
    ),
  )
  assert_false(
    @moon_pyversion.SpecifierSet::parse(">1.0").contains(
      @moon_pyversion.Version::parse("1.0.post1"),
    ),
  )
  assert_true(
    @moon_pyversion.SpecifierSet::parse(">1.0.post1").contains(
      @moon_pyversion.Version::parse("1.0.post2"),
    ),
  )
  for s in ["<1.0+abc", "<=1.0+abc", ">1.0+abc", ">=1.0+abc", "~=1.0+abc"] {
    let rejected = try {
      ignore(@moon_pyversion.SpecifierSet::parse(s))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "filter prefers finals and falls back only when policy is automatic" {
  let spec = @moon_pyversion.SpecifierSet::parse(">=1.0")
  let pre = @moon_pyversion.Version::parse("1.1a1")
  let stable = @moon_pyversion.Version::parse("1.0")
  assert_eq(@moon_pyversion.SpecifierSet::filter([pre, stable], spec), [stable])
  assert_eq(@moon_pyversion.SpecifierSet::filter([pre], spec), [pre])
  assert_eq(
    @moon_pyversion.SpecifierSet::filter([pre], spec, prereleases=Some(false)),
    [],
  )
  assert_eq(
    @moon_pyversion.SpecifierSet::filter(
      [pre, stable],
      spec,
      prereleases=Some(true),
    ),
    [pre, stable],
  )
  assert_true(
    @moon_pyversion.SpecifierSet::parse("===1.0+ABC").contains(
      @moon_pyversion.Version::parse("1.0+abc"),
    ),
  )
}
