///|
/// M1 tests: `utils.mbt`. The expected values were read off PyPA
/// `packaging` 26.3; the same inputs are replayed against it by the
/// differential corpus (`canon` and `file` records).

///|
fn wheel_rejected(filename : String) -> Bool {
  try {
    ignore(parse_wheel_filename(filename))
    false
  } catch {
    _ => true
  }
}

///|
fn sdist_rejected(filename : String) -> Bool {
  try {
    ignore(parse_sdist_filename(filename))
    false
  } catch {
    _ => true
  }
}

///|
test "canonicalize_name follows PEP 503" {
  assert_eq(canonicalize_name("Flask"), "flask")
  assert_eq(canonicalize_name("importlib_metadata"), "importlib-metadata")
  assert_eq(canonicalize_name("zope.interface"), "zope-interface")
  assert_eq(canonicalize_name("Foo.Bar-Baz"), "foo-bar-baz")
  assert_eq(canonicalize_name("Foo__Bar"), "foo-bar")
  assert_eq(canonicalize_name("a.-_b"), "a-b")
  assert_eq(canonicalize_name("requests"), "requests")
}

///|
test "canonicalize_name keeps leading and trailing separators" {
  // packaging collapses runs but does not strip the ends.
  assert_eq(canonicalize_name("--"), "-")
  assert_eq(canonicalize_name("-foo-"), "-foo-")
  assert_eq(canonicalize_name("-"), "-")
  assert_eq(canonicalize_name(""), "")
}

///|
test "canonicalize_version key form strips trailing release zeros" {
  assert_eq(canonicalize_version("1.0.0"), "1")
  assert_eq(canonicalize_version("1.4.0.0.0"), "1.4")
  assert_eq(canonicalize_version("0.0"), "0")
  assert_eq(canonicalize_version("0.0.0"), "0")
  // At least one release segment survives even when it is zero.
  assert_eq(canonicalize_version("0"), "0")
}

///|
test "canonicalize_version keeps pre post dev and local segments" {
  assert_eq(canonicalize_version("1.0.0.post0"), "1.post0")
  assert_eq(canonicalize_version("1.0.0.dev0"), "1.dev0")
  assert_eq(canonicalize_version("1.0.0a1"), "1a1")
  assert_eq(canonicalize_version("1.0.0+abc"), "1+abc")
  assert_eq(canonicalize_version("1!1.0.0"), "1!1")
  assert_eq(canonicalize_version("1.0.0.post1.dev2"), "1.post1.dev2")
}

///|
test "canonicalize_version without trimming only normalizes the spelling" {
  assert_eq(
    canonicalize_version("1.4.0.0.0", strip_trailing_zero=false),
    "1.4.0.0.0",
  )
  assert_eq(canonicalize_version("0.0", strip_trailing_zero=false), "0.0")
  assert_eq(canonicalize_version("v1.2.3", strip_trailing_zero=false), "1.2.3")
}

///|
test "canonicalize_version returns invalid input unaltered" {
  // packaging does not raise here, and neither do we.
  assert_eq(canonicalize_version("foo bar baz"), "foo bar baz")
  assert_eq(canonicalize_version(""), "")
  assert_eq(canonicalize_version("1.0."), "1.0.")
}

///|
test "wheel filenames parse name version build and tags" {
  let plain = parse_wheel_filename("flask-3.0.3-py3-none-any.whl")
  assert_eq(plain.name, "flask")
  assert_eq(Version::to_string(plain.version), "3.0.3")
  assert_true(plain.build is None)
  assert_eq(plain.tags, ["py3-none-any"])
  let built = parse_wheel_filename("flask-3.0.3-1-py3-none-any.whl")
  assert_eq(built.build, Some((1, "")))
  let with_local = parse_wheel_filename(
    "torch-2.4.0+cu121-cp311-cp311-linux_x86_64.whl",
  )
  assert_eq(Version::to_string(with_local.version), "2.4.0+cu121")
  assert_eq(with_local.tags, ["cp311-cp311-linux_x86_64"])
  // The project name is escaped with underscores and then normalized.
  assert_eq(
    parse_wheel_filename("foo_bar-1.0-py3-none-any.whl").name,
    "foo-bar",
  )
}

///|
test "compressed tag sets expand to sorted tag triples" {
  assert_eq(parse_wheel_filename("foo-1.0-py2.py3-none-any.whl").tags, [
    "py2-none-any", "py3-none-any",
  ])
  assert_eq(
    parse_wheel_filename("foo-1.0-cp39.cp310-abi3-manylinux1_x86_64.whl").tags,
    ["cp310-abi3-manylinux1_x86_64", "cp39-abi3-manylinux1_x86_64"],
  )
  let numpy = parse_wheel_filename(
    "numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
  )
  assert_eq(numpy.tags, [
    "cp312-cp312-manylinux2014_x86_64", "cp312-cp312-manylinux_2_17_x86_64",
  ])
  assert_eq(numpy.name, "numpy")
}

///|
test "invalid wheel filenames are rejected" {
  let bad : Array[String] = [
    // wrong or missing extension
    "foo-1.0-py3-none-any.zip", "foo-1.0-py3-none.whl", "foo-.whl",
    // wrong part count
     "a-b-c.whl", "foo-1.0-py3-none-any-extra-part.whl",
    // project name rules: no `__`, no dashes, must be non-empty
     "foo__bar-1.0-py3-none-any.whl", "foo-bar-1.0-py3-none-any.whl", "-1.0-py3-none-any.whl",
    "foo$bar-1.0-py3-none-any.whl",
    // build tag must start with a digit
     "foo-1.0-abc-py3-none-any.whl",
  ]
  for raw in bad {
    assert_true(wheel_rejected(raw))
  }
}

///|
test "tag components are validated" {
  // interpreter must be an identifier, components must be non-empty,
  // and exactly three components are required.
  assert_true(wheel_rejected("foo-1.0-2py-none-any.whl"))
  assert_true(wheel_rejected("foo-1.0-py3--any.whl"))
  assert_true(wheel_rejected("foo-1.0-py3.none-any.whl"))
}

///|
test "sdist filenames split on the last dash and normalize the name" {
  let tar = parse_sdist_filename("flask-3.0.3.tar.gz")
  assert_eq(tar.name, "flask")
  assert_eq(Version::to_string(tar.version), "3.0.3")
  let zip = parse_sdist_filename("flask-3.0.3.zip")
  assert_eq(zip.name, "flask")
  assert_eq(Version::to_string(zip.version), "3.0.3")
  // A dash in the project name survives, because the version cannot contain one.
  assert_eq(parse_sdist_filename("foo-bar-1.0.tar.gz").name, "foo-bar")
  assert_eq(
    parse_sdist_filename("Zope.Interface-5.4.0.tar.gz").name,
    "zope-interface",
  )
}

///|
test "invalid sdist filenames are rejected" {
  let bad : Array[String] = [
    "foo-1.0.tar.bz2", // unsupported extension
     "foo.tar.gz", // no separator
     "-1.0.tar.gz", // empty project name
     "foo-abc.tar.gz", // version is not PEP 440
     "foo-1.0.whl", // not an sdist at all
  ]
  for raw in bad {
    assert_true(sdist_rejected(raw))
  }
}

///|
test "filename errors carry a stable code" {
  let code = try {
    ignore(parse_wheel_filename("nope.whl"))
    "NO_ERROR"
  } catch {
    VersionError::InvalidFilename(value, _) => value
    _ => "WRONG_VARIANT"
  }
  assert_eq(code, "WHEEL_PART_COUNT")
}
