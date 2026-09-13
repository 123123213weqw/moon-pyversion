///|
fn version_rejected(input : String) -> Bool {
  try {
    ignore(Version::parse(input))
    false
  } catch {
    _ => true
  }
}

///|
test "PEP 440 normalization examples" {
  let cases : Array[(String, String)] = [
    ("1.0.dev456", "1.0.dev456"),
    ("1.0a1", "1.0a1"),
    ("1.0a2.dev456", "1.0a2.dev456"),
    ("1.0a12.dev456", "1.0a12.dev456"),
    ("1.0a12", "1.0a12"),
    ("1.0b1.dev456", "1.0b1.dev456"),
    ("1.0b2", "1.0b2"),
    ("1.0b2.post345.dev456", "1.0b2.post345.dev456"),
    ("1.0b2.post345", "1.0b2.post345"),
    ("1.0rc1.dev456", "1.0rc1.dev456"),
    ("1.0rc1", "1.0rc1"),
    ("1.0", "1.0"),
    ("1.0+abc.5", "1.0+abc.5"),
    ("1.0+abc.7", "1.0+abc.7"),
    ("1.0+5", "1.0+5"),
    ("1.0.post456.dev34", "1.0.post456.dev34"),
    ("1.0.post456", "1.0.post456"),
    ("1.1.dev1", "1.1.dev1"),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (input, expected) = cases[i]
    assert_eq(Version::normalize(input), expected)
  }
}

///|
test "normalization removes leading zeros and normalizes separators" {
  let cases : Array[(String, String)] = [
    ("01.002.0003", "1.2.3"),
    ("1.0-alpha1", "1.0a1"),
    ("1.0_alpha_1", "1.0a1"),
    ("1.0a.1", "1.0a1"),
    ("1.0-a", "1.0a0"),
    ("1.0PREVIEW2", "1.0rc2"),
    ("1.0-r4", "1.0.post4"),
    ("1.0rev4", "1.0.post4"),
    ("1.0-1", "1.0.post1"),
    ("1.0.dev_1", "1.0.dev1"),
    ("1.0.dev-1", "1.0.dev1"),
    ("v1.0", "1.0"),
    (" 1.0 ", "1.0"),
    ("1.0+ABC_7", "1.0+abc.7"),
  ]
  for i = 0; i < cases.length(); i = i + 1 {
    let (input, expected) = cases[i]
    assert_eq(Version::normalize(input), expected)
  }
}

///|
test "implicit pre post and dev numbers" {
  assert_eq(Version::normalize("1.0a"), "1.0a0")
  assert_eq(Version::normalize("1.0.post"), "1.0.post0")
  assert_eq(Version::normalize("1.0dev"), "1.0.dev0")
  assert_eq(Version::normalize("1.0.post."), "1.0.post0")
  assert_eq(Version::normalize("1.0dev."), "1.0.dev0")
  assert_eq(Version::normalize("1.0rc"), "1.0rc0")
}

///|
test "epoch is preserved and zero epoch is omitted" {
  assert_eq(Version::normalize("1!2.0"), "1!2.0")
  assert_eq(Version::normalize("0!1.0"), "1.0")
  assert_eq(Version::normalize("01!002.003"), "1!2.3")
}

///|
test "invalid version strings are rejected" {
  let bad : Array[String] = [
    "", "1..0", "1.0.", "1_0", "1.0_1", "1.0-", "1.0+", "1.0+abc.", "1.0a1.post2.dev3.post4",
    "1.0.dev1.post2", "1.0a1b2", "1.0..a1", "1.0!2", "1.0 some",
  ]
  for i = 0; i < bad.length(); i = i + 1 {
    assert_true(version_rejected(bad[i]))
  }
}

///|
test "release segments compare with zero padding" {
  assert_eq(Version::compare(Version::parse("1.0"), Version::parse("1.0.0")), 0)
  assert_true(Version::parse("1.0.1") > Version::parse("1.0"))
  assert_true(Version::parse("2.0") > Version::parse("1.9.9"))
}

///|
test "epoch dominates release comparison" {
  assert_true(Version::parse("1!0.1") < Version::parse("99!999.999"))
  assert_eq(Version::compare(Version::parse("0!1.0"), Version::parse("1.0")), 0)
}

///|
test "dev pre final post ordering" {
  let dev = Version::parse("1.0.dev1")
  let pre = Version::parse("1.0a1")
  let stable = Version::parse("1.0")
  let post = Version::parse("1.0.post1")
  assert_true(dev < pre)
  assert_true(pre < stable)
  assert_true(stable < post)
}

///|
test "pre-release phases order alpha beta rc" {
  let a = Version::parse("1.0a2")
  let b = Version::parse("1.0b1")
  let rc = Version::parse("1.0rc0")
  assert_true(a < b)
  assert_true(b < rc)
}

///|
test "local versions are compared segment by segment" {
  assert_true(Version::parse("1.0+abc") < Version::parse("1.0+1"))
  assert_true(Version::parse("1.0+1") < Version::parse("1.0+2"))
  assert_true(Version::parse("1.0+2") < Version::parse("1.0+10"))
  assert_true(Version::parse("1.0+abc") < Version::parse("1.0+abc.1"))
  assert_true(Version::parse("1.0+abc.1") < Version::parse("1.0+1.abc"))
}

///|
test "equality ignores release padding but not pre or local labels" {
  assert_eq(Version::parse("1.0"), Version::parse("1.0.0"))
  assert_true(
    Version::compare(Version::parse("1.0+abc"), Version::parse("1.0+xyz")) != 0,
  )
  assert_true(
    Version::compare(Version::parse("1.0a1"), Version::parse("1.0")) != 0,
  )
}

///|
test "raw input is retained while normalized output is canonical" {
  let v = Version::parse("  v01.002-rc3+ABC_007  ")
  assert_eq(v.raw, "  v01.002-rc3+ABC_007  ")
  assert_eq(Version::to_string(v), "1.2rc3+abc.7")
}

///|
/// The generated corpus in `examples/diff` found these: PEP 440 allows a
/// single `[-_.]` separator on either side of a suffix label, so spellings
/// such as `1.0post1`, `1.0-post1` and `1.0a1post2dev3` are all legal and must
/// normalize the way packaging does.
test "separators around suffix labels follow the PEP 440 grammar" {
  let cases : Array[(String, String)] = [
    ("1.0post1", "1.0.post1"),
    ("1.0-post1", "1.0.post1"),
    ("1.0_post1", "1.0.post1"),
    ("1.0.post1", "1.0.post1"),
    ("1.0rev2", "1.0.post2"),
    ("1.0-2", "1.0.post2"),
    ("1.0a1-5", "1.0a1.post5"),
    ("1.0.post1dev1", "1.0.post1.dev1"),
    ("1.0a1post2dev3", "1.0a1.post2.dev3"),
    ("1.0DEV1", "1.0.dev1"),
    ("1.0.preview2", "1.0rc2"),
    ("1.0c-2", "1.0rc2"),
    ("1.0alpha1", "1.0a1"),
    ("1.0-apost1+2.3", "1.0a0.post1+2.3"),
    ("1.0.rc1.post2", "1.0rc1.post2"),
  ]
  for entry in cases {
    assert_eq(Version::normalize(entry.0), entry.1)
  }
}

///|
test "separator tolerance does not admit illegal suffix orders" {
  let bad : Array[String] = [
    "1.0a1a2", "1.0.post1.post2", "1.0.dev1.dev2", "1.0a1.dev1.post1", "1.0dev1a1",
    "1.0a1post.post2", "1!1.0_1a1", "1.0-1-2", "1.0+_abc", "1.0+.", "1.0-", "1.0_",
  ]
  for raw in bad {
    let rejected = try {
      ignore(Version::parse(raw))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
/// PEP 440 compares textual local segments as byte strings. MoonBit's default
/// `String` comparison orders by length first, which would rank `x` below
/// `a1`; the differential oracle caught exactly that inversion.
test "textual local segments order lexically rather than by length" {
  assert_true(Version::parse("1.0+a1") < Version::parse("1.0+x"))
  assert_true(Version::parse("1.0+aa") < Version::parse("1.0+b"))
  assert_true(Version::parse("1.0+a") < Version::parse("1.0+aa"))
  assert_true(Version::parse("0.0+a1") < Version::parse("0+x"))
}
