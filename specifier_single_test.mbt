///|
test "single specifiers parse and test versions directly" {
  let at_least = @moon_pyversion.Specifier::parse(">=1.4")
  assert_true(
    @moon_pyversion.Specifier::contains(
      at_least,
      @moon_pyversion.Version::parse("1.5"),
    ),
  )
  assert_false(
    @moon_pyversion.Specifier::contains(
      at_least,
      @moon_pyversion.Version::parse("1.3"),
    ),
  )
  let exclusion = @moon_pyversion.Specifier::parse("!=1.4.*")
  assert_false(
    @moon_pyversion.Specifier::contains(
      exclusion,
      @moon_pyversion.Version::parse("1.4.7"),
    ),
  )
  assert_true(
    @moon_pyversion.Specifier::contains(
      exclusion,
      @moon_pyversion.Version::parse("1.5"),
    ),
  )
  // Prerelease opt-out applies to a lone specifier as to a set.
  let pre = @moon_pyversion.Version::parse("1.5rc1")
  assert_true(@moon_pyversion.Specifier::contains(at_least, pre))
  assert_false(
    @moon_pyversion.Specifier::contains(at_least, pre, prereleases=Some(false)),
  )
}
