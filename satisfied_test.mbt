///|
fn assert_satisfied(
  requirement : String,
  version : String,
  env_setup : (@moon_pyversion.MarkerEnvironment) -> Unit,
  want : String,
) -> Unit raise {
  let req = @moon_pyversion.Requirement::parse(requirement)
  let v = @moon_pyversion.Version::parse(version)
  let env = @moon_pyversion.MarkerEnvironment::new()
  env_setup(env)
  let got = req.satisfied_by(v, env)
  let got_name = match got {
    @moon_pyversion.Satisfied => "satisfied"
    @moon_pyversion.VersionRejected(_) => "version"
    @moon_pyversion.MarkerRejected(_) => "marker"
    @moon_pyversion.EvalError(_) => "error"
  }
  assert_eq(got_name, want)
}

///|
test "satisfied_by answers the PEP 508 judgment per branch" {
  // No marker: the constraint set decides alone.
  assert_satisfied("foo>=1.0,<2", "1.5", env => ignore(env), "satisfied")
  assert_satisfied("foo>=1.0,<2", "2.0", env => ignore(env), "version")
  // @moon_pyversion.Marker true in the environment.
  assert_satisfied(
    "foo>=1.0; python_version >= '3.8'",
    "1.0",
    env => env.set("python_version", "3.11"),
    "satisfied",
  )
  // @moon_pyversion.Version matches, marker false in this environment.
  assert_satisfied(
    "foo>=1.0; python_version < '3.0'",
    "1.0",
    env => env.set("python_version", "3.11"),
    "marker",
  )
  // @moon_pyversion.Version rejected takes priority: the marker is never consulted.
  assert_satisfied(
    "foo<1.0; python_version < '3.0'",
    "2.0",
    env => env.set("python_version", "3.11"),
    "version",
  )
}

///|
test "satisfied_by surfaces marker errors, never fakes a false" {
  // Unknown marker variable: rejected at requirement parse time, so it
  // can never reach a resolver as a live candidate check.
  let refused = Some(@moon_pyversion.Requirement::parse("foo>=1.0; no_such_var == 'x'")) catch {
    _ => None
  }
  let refused = match refused {
    None => true
    Some(_) => false
  }
  assert_eq(refused, true)
  // Extras membership against an unset extras value: also an error.
  let req2 = @moon_pyversion.Requirement::parse("foo>=1.0; 'csv' in extras")
  let verdict2 = req2.satisfied_by(@moon_pyversion.Version::parse("1.0"), @moon_pyversion.MarkerEnvironment::new())
  let is_error = match verdict2 {
    @moon_pyversion.EvalError(_) => true
    _ => false
  }
  assert_eq(is_error, true)
}

///|
test "satisfied_by_version is the markerless shortcut" {
  let req = @moon_pyversion.Requirement::parse("foo~=1.4")
  assert_eq(req.satisfied_by_version(@moon_pyversion.Version::parse("1.4.2")), true)
  assert_eq(req.satisfied_by_version(@moon_pyversion.Version::parse("1.9")), true)
  // Prerelease policy flows through, same as SpecifierSet::contains.
  assert_eq(req.satisfied_by_version(@moon_pyversion.Version::parse("1.4.0rc1")), false)
  // 1.4.0rc1 is below the ~=1.4 lower bound in PEP 440's prerelease
  // ordering (1.4.0rc1 < 1.4), so even prereleases=true cannot admit it.
  assert_eq(
    req.satisfied_by_version(@moon_pyversion.Version::parse("1.4.0rc1"), prereleases=Some(true)),
    false,
  )
  assert_eq(
    req.satisfied_by_version(@moon_pyversion.Version::parse("1.4.0rc1"), prereleases=Some(false)),
    false,
  )
}

///|
test "satisfied_by on a URL requirement still checks the constraints" {
  // A `name @ url` requirement carries no specifier; any version is
  // acceptable on the version side and the marker (if any) decides.
  let req = @moon_pyversion.Requirement::parse("foo @ https://example.invalid/foo.whl")
  let verdict = req.satisfied_by(@moon_pyversion.Version::parse("0.1"), @moon_pyversion.MarkerEnvironment::new())
  let ok = match verdict {
    @moon_pyversion.Satisfied => true
    _ => false
  }
  assert_eq(ok, true)
}
