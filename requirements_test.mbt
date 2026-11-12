///|
/// M2 tests: `requirements.mbt`. Expected values were read off PyPA
/// `packaging` 26.3 and are replayed by the differential corpus (`req`
/// records), so a change in either direction shows up twice.

///|
fn requirement_rejected(raw : String) -> Bool {
  try {
    ignore(@moon_pyversion.Requirement::parse(raw))
    false
  } catch {
    _ => true
  }
}

///|
fn requirement_of(raw : String) -> @moon_pyversion.Requirement {
  @moon_pyversion.Requirement::parse(raw) catch {
    _ => abort("expected \{raw} to parse")
  }
}

///|
test "requirement: bare name" {
  let parsed = requirement_of("foo")
  assert_eq(parsed.name, "foo")
  assert_eq(parsed.extras.length(), 0)
  assert_eq(parsed.specifier.to_string(), "")
  assert_eq(parsed.url, None)
  assert_eq(parsed.marker_text, None)
  assert_eq(parsed.to_string(), "foo")
}

///|
test "requirement: name spelling is preserved" {
  // packaging keeps the caller's spelling for the name and extras; only the
  // constraint set is normalized.
  assert_eq(requirement_of("Requests").name, "Requests")
  assert_eq(
    requirement_of("Requests[Security]").to_string(),
    "Requests[Security]",
  )
  assert_eq(requirement_of("zope.interface").name, "zope.interface")
  assert_eq(requirement_of("1foo").name, "1foo")
  assert_eq(requirement_of("FOO_BAR").name, "FOO_BAR")
}

///|
test "requirement: name grammar matches packaging" {
  for accepted in ["foo", "1foo", "foo_", "foo._", "a-b_c.d", "FOO", "x", "123"] {
    assert_false(requirement_rejected(accepted))
  }
  for
    rejected in [
      "foo-", "foo.", "-foo", ".foo", "_foo", "foo_-", "a.", ".a", "_a", "foo!",
      "foo bar",
    ] {
    assert_true(requirement_rejected(rejected))
  }
}

///|
test "requirement: extras are deduplicated and sorted" {
  let parsed = requirement_of("foo[b,a,b]")
  assert_eq(parsed.extras, ["a", "b"])
  assert_eq(parsed.to_string(), "foo[a,b]")
  // `name[]` is accepted, and `foo[ ]` too, but they contribute nothing.
  assert_eq(requirement_of("foo[]").extras.length(), 0)
  assert_eq(requirement_of("foo[ a ]").extras, ["a"])
}

///|
test "requirement: specifier is normalized, name is not" {
  let parsed = requirement_of("Requests[Security]>=2.0,<3.0")
  assert_eq(parsed.name, "Requests")
  assert_eq(parsed.extras, ["Security"])
  // clauses come back sorted by code point, not in source order
  assert_eq(parsed.specifier.to_string(), "<3.0,>=2.0")
  assert_eq(parsed.to_string(), "Requests[Security]<3.0,>=2.0")
}

///|
test "requirement: whitespace around a specifier is dropped" {
  assert_eq(requirement_of("foo >= 1.0").to_string(), "foo>=1.0")
  assert_eq(requirement_of("foo != 1.0.*").to_string(), "foo!=1.0.*")
  assert_eq(requirement_of("  foo  >=  1.0  ").to_string(), "foo>=1.0")
}

///|
test "requirement: the parenthesised specifier spelling still parses" {
  // PEP 508 dropped it, packaging still accepts it, so we do too.
  assert_eq(requirement_of("foo(>=1.0)").to_string(), "foo>=1.0")
  assert_eq(requirement_of("foo (>=1.0,<2.0)").to_string(), "foo<2.0,>=1.0")
  assert_true(requirement_rejected("foo(>=1.0"))
  assert_true(requirement_rejected("foo>=1.0)"))
}

///|
test "requirement: url form" {
  let parsed = requirement_of("foo @ https://example.com/foo-1.0.tar.gz")
  assert_eq(parsed.name, "foo")
  assert_eq(parsed.url, Some("https://example.com/foo-1.0.tar.gz"))
  assert_eq(parsed.specifier.to_string(), "")
  assert_eq(parsed.to_string(), "foo @ https://example.com/foo-1.0.tar.gz")
  assert_eq(
    requirement_of("foo[bar] @ file:///tmp/foo.zip").to_string(),
    "foo[bar] @ file:///tmp/foo.zip",
  )
  assert_true(requirement_rejected("foo @ "))
  assert_true(requirement_rejected("foo@"))
  assert_true(requirement_rejected("foo[extra] @ url2 url3"))
}

///|
test "requirement: marker text is captured verbatim" {
  let parsed = requirement_of("foo>=1.0 ; extra == \"test\"")
  assert_eq(parsed.marker_text, Some("extra == \"test\""))
  assert_eq(parsed.to_string(), "foo>=1.0; extra == \"test\"")
  // A URL requirement separates its marker with a space before the semicolon,
  // which is how packaging renders it back.
  let with_url = requirement_of(
    "foo @ file:///tmp/foo.zip ; python_version < \"3.9\"",
  )
  assert_eq(with_url.url, Some("file:///tmp/foo.zip"))
  assert_eq(
    with_url.to_string(),
    "foo @ file:///tmp/foo.zip ; python_version < \"3.9\"",
  )
}

///|
test "requirement: a semicolon inside parentheses is not a marker separator" {
  let parsed = requirement_of(
    "foo; (python_version >= \"3.8\" or os_name == \"posix\")",
  )
  assert_eq(
    parsed.marker_text,
    Some("(python_version >= \"3.8\" or os_name == \"posix\")"),
  )
}

///|
test "requirement: empty and nonsense input is rejected" {
  for
    rejected in [
      "", "  ", "\t", ">=1.0", "foo[", "foo]", "foo>= ", "foo>=", "foo!", "foo 1.0",
    ] {
    assert_true(requirement_rejected(rejected))
  }
  assert_true(requirement_rejected("foo;"))
}

///|
test "requirement: diagnostics carry a stable code" {
  ignore(@moon_pyversion.Requirement::parse("foo bar")) catch {
    @moon_pyversion.VersionError::InvalidRequirement(code, pos) => {
      assert_eq(code, "EXPECTED_SPECIFIER")
      // the offset of the first character that cannot continue the requirement
      assert_eq(pos, 4)
    }
    other => abort("unexpected error \{other}")
  }
}

///|
test "requirement: show renders the normalized form" {
  let parsed = requirement_of(
    "Requests[Security]>=2.0,<3.0; python_version >= \"3.8\"",
  )
  assert_eq(
    "\{parsed}",
    "Requests[Security]<3.0,>=2.0; python_version >= \"3.8\"",
  )
}

///|
test "conflicts_with decides version-set disjointness" {
  let conflict : Array[(String, String)] = [
    ("demo>=2.0", "demo<2.0"),
    ("demo>2.0", "demo<=2.0"),
    ("demo==1.0", "demo==1.1"),
    ("demo==1.4.*", "demo==1.5.*"),
    ("demo==1.4.5", "demo!=1.4.*"),
    ("demo~=1.4", "demo>=2.0"),
    ("demo~=1.4.5", "demo<=1.4"),
    ("demo~=1.4", "demo~=2.0"),
    ("demo==1.4.*", "demo>=1.5"),
    ("demo>1.0,<2.0", "demo==2.0"),
  ]
  for entry in conflict {
    let a = @moon_pyversion.Requirement::parse(entry.0)
    let b = @moon_pyversion.Requirement::parse(entry.1)
    assert_true(@moon_pyversion.Requirement::conflicts_with(a, b))
  }
  let compatible : Array[(String, String)] = [
    ("demo>=1.0,<2.0", "demo>=1.5,<3.0"),
    ("demo>=2.0", "demo<=2.0"),
    ("demo~=1.4", "demo<1.5"),
    ("demo~=1.4", "demo>=1.5"),
    ("demo==1.4.*", "demo<1.4.6"),
    ("demo!=1.4.*", "demo>=1.0"),
    ("demo", "demo==1.0"),
  ]
  for entry in compatible {
    let a = @moon_pyversion.Requirement::parse(entry.0)
    let b = @moon_pyversion.Requirement::parse(entry.1)
    assert_false(@moon_pyversion.Requirement::conflicts_with(a, b))
  }
}

///|
test "conflicts_with is scoped to one project by canonical name" {
  // Different projects never conflict through versions.
  let different = (
    @moon_pyversion.Requirement::parse("demo>=2.0"),
    @moon_pyversion.Requirement::parse("other<2.0"),
  )
  assert_false(
    @moon_pyversion.Requirement::conflicts_with(different.0, different.1),
  )
  // Name spelling does not matter: PEP 503 canonicalization applies.
  let canonical = (
    @moon_pyversion.Requirement::parse("Demo>=2.0"),
    @moon_pyversion.Requirement::parse("DEMO<2.0"),
  )
  assert_true(
    @moon_pyversion.Requirement::conflicts_with(canonical.0, canonical.1),
  )
  let dashed = (
    @moon_pyversion.Requirement::parse("Demo.Project>=2.0"),
    @moon_pyversion.Requirement::parse("demo_project<2.0"),
  )
  assert_true(@moon_pyversion.Requirement::conflicts_with(dashed.0, dashed.1))
}

///|
/// Two direct URLs for one project are pip's "double requirement": the
/// same URL is the same artifact, a different URL is a conflict no version
/// can reconcile. One URL against a specifier cannot be decided here.
test "conflicts_with handles the direct-URL form" {
  let same_url = (
    @moon_pyversion.Requirement::parse("demo @ https://a.example/x.whl"),
    @moon_pyversion.Requirement::parse("demo @ https://a.example/x.whl"),
  )
  assert_false(
    @moon_pyversion.Requirement::conflicts_with(same_url.0, same_url.1),
  )
  let other_url = (
    @moon_pyversion.Requirement::parse("demo @ https://a.example/x.whl"),
    @moon_pyversion.Requirement::parse("demo @ https://b.example/y.whl"),
  )
  assert_true(
    @moon_pyversion.Requirement::conflicts_with(other_url.0, other_url.1),
  )
  let url_vs_spec = (
    @moon_pyversion.Requirement::parse("demo @ https://a.example/x.whl"),
    @moon_pyversion.Requirement::parse("demo<1.0"),
  )
  assert_false(
    @moon_pyversion.Requirement::conflicts_with(url_vs_spec.0, url_vs_spec.1),
  )
}

///|
/// Markers that provably never co-apply keep two disjoint requirements
/// from being a conflict - one of them is always switched off. The
/// exclusivity proof works through version comparisons, string equality
/// and set membership; a disjunction gives up and co-applies.
test "conflicts_with respects markers that separate environments" {
  let separated : Array[(String, String)] = [
    ("demo>=2.0; python_version >= '3'", "demo<2.0; python_version < '3'"),
    ("demo==1.0; extra == 'html'", "demo==1.1; extra == 'pdf'"),
    ("demo>=2.0; os_name == 'nt'", "demo<2.0; os_name == 'posix'"),
    ("demo>=2.0; python_version >= '4' and python_version < '3'", "demo<2.0"),
    (
      "demo>=2.0; python_version in '3.9 3.10'", "demo<2.0; python_version == '3.8'",
    ),
  ]
  for entry in separated {
    let a = @moon_pyversion.Requirement::parse(entry.0)
    let b = @moon_pyversion.Requirement::parse(entry.1)
    assert_false(@moon_pyversion.Requirement::conflicts_with(a, b))
  }
  // Markers on different variables (or an `or`) do not separate anything:
  // the disjoint constraints are a real conflict.
  let together : Array[(String, String)] = [
    ("demo>=2.0; python_version >= '3'", "demo<2.0; extra == 'html'"),
    (
      "demo>=2.0; python_version >= '3' or os_name == 'nt'", "demo<2.0; python_version < '3'",
    ),
    (
      "demo>=2.0; (python_version >= '3' and sys_platform == 'linux')", "demo<2.0; implementation_name == 'cpython'",
    ),
  ]
  for entry in together {
    let a = @moon_pyversion.Requirement::parse(entry.0)
    let b = @moon_pyversion.Requirement::parse(entry.1)
    assert_true(@moon_pyversion.Requirement::conflicts_with(a, b))
  }
}

///|
/// A requirement whose own constraint set is unsatisfiable admits nothing,
/// so it conflicts with every requirement on the same project - including
/// an unconstrained one - but still with no other project.
test "conflicts_with reports a self-contradicting requirement" {
  let broken = @moon_pyversion.Requirement::parse("demo==1.0,==2.0")
  let unconstrained = @moon_pyversion.Requirement::parse("demo")
  assert_true(
    @moon_pyversion.Requirement::conflicts_with(broken, unconstrained),
  )
  let other_project = @moon_pyversion.Requirement::parse("other>=1.0")
  assert_false(
    @moon_pyversion.Requirement::conflicts_with(broken, other_project),
  )
  let excluded = @moon_pyversion.Requirement::parse("demo==1.0,!=1.0")
  assert_true(
    @moon_pyversion.Requirement::conflicts_with(unconstrained, excluded),
  )
}
