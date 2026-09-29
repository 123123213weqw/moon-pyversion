///|
fn parse_corpus() -> Array[@moon_pyversion.Version] {
  let inputs : Array[String] = [
    "0", "0.0", "1.0", "1.0.0", "1.0.dev1", "1.0a1", "1.0b2", "1.0rc3", "1.0.post1",
    "1.0+abc", "1.0+5", "1.0+abc.1", "2.0.dev0", "2.0a1", "2.0", "2.0.post1", "1!0.1",
    "1!1.0", "0!1.0", "v1.2.3", "1.2.3.4", "1.0a1.post2.dev3", "1.0.post456.dev34",
    "01.002.0003", "1.0-1",
  ]
  let out : Array[@moon_pyversion.Version] = []
  for i = 0; i < inputs.length(); i = i + 1 {
    out.push(try! @moon_pyversion.Version::parse(inputs[i]))
  }
  out
}

///|
test "comparison is reflexive antisymmetric and transitive on the corpus" {
  let versions = parse_corpus()
  for i = 0; i < versions.length(); i = i + 1 {
    let a = versions[i]
    assert_eq(@moon_pyversion.Version::compare(a, a), 0)
    for j = 0; j < versions.length(); j = j + 1 {
      let b = versions[j]
      let ab = @moon_pyversion.Version::compare(a, b)
      let ba = @moon_pyversion.Version::compare(b, a)
      if ab < 0 {
        assert_true(ba > 0)
      } else if ab > 0 {
        assert_true(ba < 0)
      } else {
        assert_eq(ba, 0)
        assert_true(a == b)
      }
      for k = 0; k < versions.length(); k = k + 1 {
        let c = versions[k]
        if @moon_pyversion.Version::compare(a, b) < 0 &&
          @moon_pyversion.Version::compare(b, c) < 0 {
          assert_true(@moon_pyversion.Version::compare(a, c) < 0)
        }
      }
    }
  }
}

///|
test "distinct raw spellings can share the same PEP 440 key" {
  let a = @moon_pyversion.Version::parse("1.0")
  let b = @moon_pyversion.Version::parse("1.0.0")
  let c = @moon_pyversion.Version::parse("v1.0")
  let d = @moon_pyversion.Version::parse("01.00")
  assert_eq(@moon_pyversion.Version::compare(a, b), 0)
  assert_eq(@moon_pyversion.Version::compare(a, c), 0)
  assert_eq(@moon_pyversion.Version::compare(a, d), 0)
  assert_true(a.raw != b.raw)
  assert_true(b.raw != c.raw)
}

///|
test "normalization is idempotent and preserves comparison keys" {
  let versions = parse_corpus()
  for i = 0; i < versions.length(); i = i + 1 {
    let v = versions[i]
    let once = @moon_pyversion.Version::to_string(v)
    let again = try! @moon_pyversion.Version::normalize(once)
    assert_eq(once, again)
    assert_eq(
      @moon_pyversion.Version::compare(
        try! @moon_pyversion.Version::parse(once),
        v,
      ),
      0,
    )
  }
}

///|
test "filter output is a stable subset of its input" {
  let versions = parse_corpus()
  let spec = @moon_pyversion.SpecifierSet::parse(">=1.0, !=1.0.*, <2.0")
  let filtered = @moon_pyversion.SpecifierSet::filter(versions, spec)
  let mut seen = 0
  for i = 0; i < filtered.length(); i = i + 1 {
    assert_true(spec.contains(filtered[i]))
    let mut found = false
    for j = 0; j < versions.length(); j = j + 1 {
      if filtered[i] == versions[j] {
        found = true
        break
      }
    }
    assert_true(found)
    seen = seen + 1
  }
  assert_true(seen == filtered.length())
}
