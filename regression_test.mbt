///|
test "compound suffixes stay with their parent release" {
  let ordered = [
    "1.0.dev1", "1.0a1", "1.0a2.dev1", "1.0a2", "1.0a2.post1.dev1", "1.0a2.post1",
    "1.0b1.dev1", "1.0rc1", "1.0", "1.0+abc", "1.0.post1.dev1", "1.0.post1", "1.0.post2.dev1",
  ]
  for i = 0; i < ordered.length(); i = i + 1 {
    for j = i + 1; j < ordered.length(); j = j + 1 {
      assert_true(Version::parse(ordered[i]) < Version::parse(ordered[j]))
    }
  }
}

///|
test "wildcard pads missing release digits and preserves epoch" {
  assert_true(SpecifierSet::parse("==1.0.*").contains(Version::parse("1")))
  assert_false(SpecifierSet::parse("!=1.0.*").contains(Version::parse("1")))
  assert_false(SpecifierSet::parse("==1.0.*").contains(Version::parse("1!1")))
}

///|
test "ordered constraints ignore local labels but reject local boundaries" {
  assert_false(
    SpecifierSet::parse("<1.0.post1").contains(Version::parse("1.0.post1.dev1")),
  )
  assert_true(
    SpecifierSet::parse("<1.0.post1").contains(Version::parse("1.0.post0.dev1")),
  )
  assert_true(SpecifierSet::parse("<=1.0").contains(Version::parse("1.0+abc")))
  assert_false(SpecifierSet::parse(">1.0").contains(Version::parse("1.0+abc")))
  assert_false(
    SpecifierSet::parse(">1.0").contains(Version::parse("1.0.post1")),
  )
  assert_true(
    SpecifierSet::parse(">1.0.post1").contains(Version::parse("1.0.post2")),
  )
  for s in ["<1.0+abc", "<=1.0+abc", ">1.0+abc", ">=1.0+abc", "~=1.0+abc"] {
    let rejected = try {
      ignore(SpecifierSet::parse(s))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "filter prefers finals and falls back only when policy is automatic" {
  let spec = SpecifierSet::parse(">=1.0")
  let pre = Version::parse("1.1a1")
  let stable = Version::parse("1.0")
  assert_eq(SpecifierSet::filter([pre, stable], spec), [stable])
  assert_eq(SpecifierSet::filter([pre], spec), [pre])
  assert_eq(SpecifierSet::filter([pre], spec, prereleases=Some(false)), [])
  assert_eq(SpecifierSet::filter([pre, stable], spec, prereleases=Some(true)), [
    pre, stable,
  ])
  assert_true(
    SpecifierSet::parse("===1.0+ABC").contains(Version::parse("1.0+abc")),
  )
}
