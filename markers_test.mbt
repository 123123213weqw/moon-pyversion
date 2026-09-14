///|
/// M3 tests: `markers.mbt`. Expected values were read off PyPA `packaging`
/// 26.3; the same inputs are replayed against it by the differential corpus
/// (`marker`, `marker_env` and `marker_eval` records).

///|
fn marker_of(raw : String) -> Marker {
  Marker::parse(raw) catch {
    _ => abort("expected \{raw} to parse")
  }
}

///|
fn marker_rejected(raw : String) -> Bool {
  try {
    ignore(Marker::parse(raw))
    false
  } catch {
    _ => true
  }
}

///|
fn rendered(raw : String) -> String {
  marker_of(raw).to_string() catch {
    _ => abort("expected \{raw} to render")
  }
}

///|
/// The environment the evaluation tests use, matching the `posix38` corpus
/// environment.
fn posix38() -> MarkerEnvironment {
  let environment = MarkerEnvironment::new()
  environment.set("python_version", "3.8")
  environment.set("python_full_version", "3.8.18")
  environment.set("os_name", "posix")
  environment.set("sys_platform", "linux")
  environment.set("platform_release", "5.4.0")
  environment.set("platform_system", "Linux")
  environment.set("platform_version", "#1 SMP")
  environment.set("platform_machine", "x86_64")
  environment.set("platform_python_implementation", "CPython")
  environment.set("implementation_name", "cpython")
  environment.set("implementation_version", "3.8.18")
  environment.set("extra", "")
  environment
}

///|
fn evaluate_with(marker : String, environment : MarkerEnvironment) -> Bool {
  marker_of(marker).evaluate(environment) catch {
    error => abort("unexpected evaluation error \{error}")
  }
}

///|
fn evaluate_error(marker : String, environment : MarkerEnvironment) -> String {
  try {
    ignore(marker_of(marker).evaluate(environment))
    "<no error>"
  } catch {
    MarkerError::UndefinedEnvironmentName(name) => "undefined:\{name}"
    MarkerError::UndefinedComparison(_) => "comparison"
    MarkerError::SetValuedOnLeft(key, op) => "set-valued:\{key}:\{op}"
  }
}

///|
test "marker: the vocabulary is closed" {
  assert_eq(marker_of("python_version == '3.8'").variables(), [PythonVersion])
  assert_eq(marker_of("os_name == 'posix'").variables(), [OsName])
  assert_eq(marker_of("extra == 'test'").variables(), [Extra])
  for
    rejected in [
      "ex0tra == 'x'", "etra == 'x'", "extrax == 'x'", "python_versio == 'x'", "version == 'x'",
      "implementation == 'x'", "plat_form == 'x'",
    ] {
    assert_true(marker_rejected(rejected))
  }
}

///|
test "marker: dotted and alias spellings collapse to one key" {
  assert_eq(marker_of("os.name == 'posix'").variables(), [OsName])
  assert_eq(marker_of("sys.platform == 'linux'").variables(), [SysPlatform])
  assert_eq(marker_of("platform.version == '1'").variables(), [PlatformVersion])
  assert_eq(marker_of("platform.machine == 'x'").variables(), [PlatformMachine])
  assert_eq(
    marker_of("platform.python_implementation == 'CPython'").variables(),
    [PlatformPythonImplementation],
  )
  // the alias renders as the canonical key, as packaging does
  assert_eq(
    rendered("python_implementation == 'CPython'"),
    "platform_python_implementation == \"CPython\"",
  )
  assert_eq(rendered("os.name == 'posix'"), "os_name == \"posix\"")
  assert_eq(rendered("sys.platform == 'linux'"), "sys_platform == \"linux\"")
}

///|
test "marker: values are re-quoted with double quotes" {
  assert_eq(rendered("python_version == '3.8'"), "python_version == \"3.8\"")
  assert_eq(rendered("python_version == \"3.8\""), "python_version == \"3.8\"")
  // a value that contains a double quote keeps the single-quoted spelling
  assert_eq(rendered("extra == 'say \"hi\"'"), "extra == 'say \"hi\"'")
}

///|
test "marker: redundant parentheses are dropped, needed ones are kept" {
  assert_eq(rendered("(python_version == '3.8')"), "python_version == \"3.8\"")
  assert_eq(
    rendered("((python_version == '3.8'))"),
    "python_version == \"3.8\"",
  )
  assert_eq(
    rendered("python_version == '3.8' and (os_name == 'posix')"),
    "python_version == \"3.8\" and os_name == \"posix\"",
  )
  assert_eq(
    rendered("(os_name == 'posix' or python_version == '3.8') and extra == 'x'"),
    "(os_name == \"posix\" or python_version == \"3.8\") and extra == \"x\"",
  )
}

///|
test "marker: whitespace around and/or is optional but not in `not in`" {
  assert_eq(
    rendered("os_name=='posix'and extra=='x'"),
    "os_name == \"posix\" and extra == \"x\"",
  )
  assert_eq(rendered("  os_name  ==  'posix'  "), "os_name == \"posix\"")
  assert_eq(
    rendered("python_version == '3.8'\tand\tos_name == 'posix'"),
    "python_version == \"3.8\" and os_name == \"posix\"",
  )
  assert_true(marker_rejected("python_version notin 'x'"))
  assert_true(marker_rejected("python_version not '3.8'"))
}

///|
test "marker: membership operators" {
  assert_eq(
    rendered("python_version in '3.8 3.9'"),
    "python_version in \"3.8 3.9\"",
  )
  assert_eq(
    rendered("python_version not in '3.8 3.9'"),
    "python_version not in \"3.8 3.9\"",
  )
  // `lhs in rhs` is a substring test with lhs as the needle
  let environment = posix38()
  assert_true(evaluate_with("python_version in '3.8 3.9'", environment))
  assert_false(evaluate_with("python_version not in '3.8 3.9'", environment))
  assert_false(evaluate_with("python_version in '3.9 3.10'", environment))
}

///|
test "marker: string escapes are decoded like Python literals" {
  assert_eq(rendered("extra == 'a\\tb'"), "extra == \"a\tb\"")
  assert_eq(
    rendered("platform_system == 'a\\x41'"),
    "platform_system == \"aA\"",
  )
  // `extra` values are name-normalized, so the decoded `A` lowercases too
  assert_eq(rendered("extra == 'a\\x41'"), "extra == \"aa\"")
  assert_eq(rendered("extra == '\\101'"), "extra == \"a\"")
  // an unrecognised escape keeps its backslash
  assert_eq(rendered("extra == 'a\\zb'"), "extra == \"a\\zb\"")
  // the escapes Python rejects are rejected here too
  for
    rejected in [
      "extra == 'a\\x'", "extra == 'a\\x4'", "extra == 'a\\u12'", "extra == 'a\\'",
    ] {
    assert_true(marker_rejected(rejected))
  }
}

///|
test "marker: extra values are normalized, PEP 685" {
  assert_eq(rendered("extra == 'Foo_Bar'"), "extra == \"foo-bar\"")
  assert_eq(rendered("extra == 'Foo.Bar'"), "extra == \"foo-bar\"")
  assert_eq(rendered("'Foo_Bar' == extra"), "\"foo-bar\" == extra")
  // and evaluation compares normalized names
  let environment = posix38()
  environment.set("extra", "docs")
  assert_true(evaluate_with("extra == 'Docs'", environment))
  assert_true(evaluate_with("extra != 'test'", environment))
}

///|
test "marker: the environment normalizes extra and set member names" {
  // A caller may hand over the spelling it read from `pyproject.toml`; PEP 685
  // compares the normalized name, and `packaging` rewrites the environment
  // value before it evaluates. The environment value here is deliberately not
  // canonical, so an implementation that only normalizes the marker literal
  // gets these wrong.
  let environment = posix38()
  environment.set("extra", "Docs.Build")
  assert_true(evaluate_with("extra == 'docs-build'", environment))
  assert_true(evaluate_with("extra == 'Docs_Build'", environment))
  assert_true(evaluate_with("'Docs-Build' == extra", environment))
  assert_true(evaluate_with("extra != 'other'", environment))
  assert_false(evaluate_with("extra == 'docs'", environment))
  // the same holds for the members of a set-valued key
  environment.set_names("extras", ["Docs_Build", "CLI"])
  assert_true(evaluate_with("'docs-build' in extras", environment))
  assert_true(evaluate_with("'cli' in extras", environment))
  assert_true(evaluate_with("'nope' not in extras", environment))
  assert_false(evaluate_with("'docs' in extras", environment))
}

///|
test "marker: version-like keys compare numerically" {
  let environment = posix38()
  // a plain string comparison would call "3.10" smaller than "3.9"
  assert_true(evaluate_with("python_version > '3.7'", environment))
  assert_true(evaluate_with("python_version >= '3.8'", environment))
  assert_false(evaluate_with("python_version > '3.9'", environment))
  assert_true(evaluate_with("python_full_version >= '3.8.1'", environment))
  assert_false(evaluate_with("python_full_version >= '3.9'", environment))
  // non version keys fall back to string comparison, where < and > are false
  assert_true(evaluate_with("os_name == 'posix'", environment))
  assert_false(evaluate_with("os_name > 'nt'", environment))
  assert_false(evaluate_with("os_name < 'nt'", environment))
  assert_true(evaluate_with("os_name != 'nt'", environment))
}

///|
test "marker: and/or precedence matches any(all(...))" {
  let environment = posix38()
  // or binds looser than and
  assert_true(
    evaluate_with(
      "os_name == 'nt' or os_name == 'posix' and extra == ''", environment,
    ),
  )
  assert_false(
    evaluate_with(
      "os_name == 'nt' or os_name == 'posix' and extra == 'x'", environment,
    ),
  )
  // and a parenthesised group overrides that
  assert_true(
    evaluate_with(
      "(os_name == 'nt' or os_name == 'posix') and extra == ''", environment,
    ),
  )
  assert_false(
    evaluate_with(
      "(os_name == 'nt' or os_name == 'nt') and extra == ''", environment,
    ),
  )
}

///|
test "marker: a variable may be compared against another variable" {
  let environment = posix38()
  // python_version == python_full_version is false, both sides are looked up
  assert_false(
    evaluate_with("python_version == python_full_version", environment),
  )
  assert_true(
    evaluate_with("python_version != python_full_version", environment),
  )
  assert_true(evaluate_with("os_name == os_name", environment))
}

///|
test "marker: the value may be on the left" {
  let environment = posix38()
  assert_true(evaluate_with("'3.8' == python_version", environment))
  assert_true(
    evaluate_with("'CPython' == platform_python_implementation", environment),
  )
}

///|
test "marker: a missing environment key is reported" {
  let environment = MarkerEnvironment::new()
  environment.set("os_name", "posix")
  assert_eq(
    evaluate_error("python_version == '3.8'", environment),
    "undefined:python_version",
  )
  assert_eq(evaluate_error("os_name == 'posix'", environment), "<no error>")
}

///|
test "marker: set-valued keys only support membership" {
  let environment = posix38()
  environment.set_names("extras", ["cli", "docs"])
  assert_true(evaluate_with("'Cli' in extras", environment))
  assert_false(evaluate_with("'test' in extras", environment))
  assert_true(evaluate_with("'test' not in extras", environment))
  // on the left-hand side of any operator it is an error
  assert_eq(
    evaluate_error("extras == 'cli'", environment),
    "set-valued:extras:==",
  )
}

///|
test "marker: malformed expressions are rejected" {
  for
    rejected in [
      "", "   ", "python_version", "python_version =", "python_version = '3.8'",
      "python_version == 3.8", "python_version == '3.8", "python_version == \"3.8'",
      "python_version == '3.8' and", "and python_version == '3.8'", "()", "(python_version == '3.8'",
      "(python_version == '3.8'))", "python_version ==", "not python_version == '3.8'",
      "python_version == '3.8' extra", "python_version == '3.8'; os_name == 'posix'",
      "in 'x'", "'x' in",
    ] {
    assert_true(marker_rejected(rejected))
  }
}

///|
test "marker: clauses and variables can be inspected" {
  let marker = marker_of(
    "(os_name == 'posix' or python_version == '3.8') and extra == 'test'",
  )
  assert_eq(marker.clauses().length(), 3)
  assert_eq(marker.variables(), [OsName, PythonVersion, Extra])
  assert_eq(marker.clauses()[0].render(), "os_name == \"posix\"")
}

///|
test "marker: show renders through the fallible path" {
  let marker = marker_of("extra == 'a' and os_name == 'b'")
  assert_eq("\{marker}", "extra == \"a\" and os_name == \"b\"")
}

///|
test "marker: requirements hand their marker to this module" {
  // the same text must be accepted or rejected on both sides of the boundary
  for
    accepted in [
      "python_version == '3.8'", "extra == 'test'", "(os_name == 'posix')", "python_version in '3.8 3.9'",
    ] {
    validate_marker_text(accepted)
    assert_true(!requirement_rejected("foo; \{accepted}"))
  }
  for rejected in ["ex0tra == 'x'", "python_version ==", "()"] {
    assert_true(marker_rejected(rejected))
    assert_true(requirement_rejected("foo; \{rejected}"))
  }
}
