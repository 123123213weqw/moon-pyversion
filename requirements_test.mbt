///|
/// M2 tests: `requirements.mbt`. Expected values were read off PyPA
/// `packaging` 26.3 and are replayed by the differential corpus (`req`
/// records), so a change in either direction shows up twice.

///|
fn requirement_rejected(raw : String) -> Bool {
  try {
    ignore(Requirement::parse(raw))
    false
  } catch {
    _ => true
  }
}

///|
fn requirement_of(raw : String) -> Requirement {
  Requirement::parse(raw) catch {
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
  ignore(Requirement::parse("foo bar")) catch {
    VersionError::InvalidRequirement(code, pos) => {
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
