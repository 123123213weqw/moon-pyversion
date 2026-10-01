///|
test "release gates expose pre post and dev markers" {
  let plain = @moon_pyversion.Version::parse("1.0.0")
  assert_false(@moon_pyversion.Version::is_prerelease(plain))
  assert_false(@moon_pyversion.Version::is_postrelease(plain))
  assert_false(@moon_pyversion.Version::is_devrelease(plain))
  let rc = @moon_pyversion.Version::parse("1.0rc1")
  assert_true(@moon_pyversion.Version::is_prerelease(rc))
  assert_false(@moon_pyversion.Version::is_devrelease(rc))
  let dev = @moon_pyversion.Version::parse("1.0.dev3")
  assert_true(@moon_pyversion.Version::is_prerelease(dev))
  assert_true(@moon_pyversion.Version::is_devrelease(dev))
  let post = @moon_pyversion.Version::parse("1.0.post2")
  assert_true(@moon_pyversion.Version::is_postrelease(post))
  assert_false(@moon_pyversion.Version::is_prerelease(post))
}

///|
test "public and base forms strip the documented components" {
  let v = @moon_pyversion.Version::parse("1!2.0.1rc1.post4.dev5+local.7")
  assert_eq(@moon_pyversion.Version::public(v), "1!2.0.1rc1.post4.dev5")
  assert_eq(@moon_pyversion.Version::base_version(v), "1!2.0.1")
  let clean = @moon_pyversion.Version::parse("3.2.1")
  assert_eq(@moon_pyversion.Version::public(clean), "3.2.1")
  assert_eq(@moon_pyversion.Version::base_version(clean), "3.2.1")
  assert_eq(@moon_pyversion.Version::epoch_string(clean), "0")
  let epoched = @moon_pyversion.Version::parse("2!0.1")
  assert_eq(@moon_pyversion.Version::epoch_string(epoched), "2")
}
