///|
fn version_rejected(input : String) -> Bool {
  try {
    ignore(@moon_pyversion.Version::parse(input))
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
    assert_eq(@moon_pyversion.Version::normalize(input), expected)
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
    assert_eq(@moon_pyversion.Version::normalize(input), expected)
  }
}

///|
test "implicit pre post and dev numbers" {
  assert_eq(@moon_pyversion.Version::normalize("1.0a"), "1.0a0")
  assert_eq(@moon_pyversion.Version::normalize("1.0.post"), "1.0.post0")
  assert_eq(@moon_pyversion.Version::normalize("1.0dev"), "1.0.dev0")
  assert_eq(@moon_pyversion.Version::normalize("1.0.post."), "1.0.post0")
  assert_eq(@moon_pyversion.Version::normalize("1.0dev."), "1.0.dev0")
  assert_eq(@moon_pyversion.Version::normalize("1.0rc"), "1.0rc0")
}

///|
test "epoch is preserved and zero epoch is omitted" {
  assert_eq(@moon_pyversion.Version::normalize("1!2.0"), "1!2.0")
  assert_eq(@moon_pyversion.Version::normalize("0!1.0"), "1.0")
  assert_eq(@moon_pyversion.Version::normalize("01!002.003"), "1!2.3")
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
  assert_eq(
    @moon_pyversion.Version::compare(
      @moon_pyversion.Version::parse("1.0"),
      @moon_pyversion.Version::parse("1.0.0"),
    ),
    0,
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0.1") >
    @moon_pyversion.Version::parse("1.0"),
  )
  assert_true(
    @moon_pyversion.Version::parse("2.0") >
    @moon_pyversion.Version::parse("1.9.9"),
  )
}

///|
test "epoch dominates release comparison" {
  assert_true(
    @moon_pyversion.Version::parse("1!0.1") <
    @moon_pyversion.Version::parse("99!999.999"),
  )
  assert_eq(
    @moon_pyversion.Version::compare(
      @moon_pyversion.Version::parse("0!1.0"),
      @moon_pyversion.Version::parse("1.0"),
    ),
    0,
  )
}

///|
test "dev pre final post ordering" {
  let dev = @moon_pyversion.Version::parse("1.0.dev1")
  let pre = @moon_pyversion.Version::parse("1.0a1")
  let stable = @moon_pyversion.Version::parse("1.0")
  let post = @moon_pyversion.Version::parse("1.0.post1")
  assert_true(dev < pre)
  assert_true(pre < stable)
  assert_true(stable < post)
}

///|
test "pre-release phases order alpha beta rc" {
  let a = @moon_pyversion.Version::parse("1.0a2")
  let b = @moon_pyversion.Version::parse("1.0b1")
  let rc = @moon_pyversion.Version::parse("1.0rc0")
  assert_true(a < b)
  assert_true(b < rc)
}

///|
test "local versions are compared segment by segment" {
  assert_true(
    @moon_pyversion.Version::parse("1.0+abc") <
    @moon_pyversion.Version::parse("1.0+1"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+1") <
    @moon_pyversion.Version::parse("1.0+2"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+2") <
    @moon_pyversion.Version::parse("1.0+10"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+abc") <
    @moon_pyversion.Version::parse("1.0+abc.1"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+abc.1") <
    @moon_pyversion.Version::parse("1.0+1.abc"),
  )
}

///|
test "equality ignores release padding but not pre or local labels" {
  assert_eq(
    @moon_pyversion.Version::parse("1.0"),
    @moon_pyversion.Version::parse("1.0.0"),
  )
  assert_true(
    @moon_pyversion.Version::compare(
      @moon_pyversion.Version::parse("1.0+abc"),
      @moon_pyversion.Version::parse("1.0+xyz"),
    ) !=
    0,
  )
  assert_true(
    @moon_pyversion.Version::compare(
      @moon_pyversion.Version::parse("1.0a1"),
      @moon_pyversion.Version::parse("1.0"),
    ) !=
    0,
  )
}

///|
test "raw input is retained while normalized output is canonical" {
  let v = @moon_pyversion.Version::parse("  v01.002-rc3+ABC_007  ")
  assert_eq(v.raw, "  v01.002-rc3+ABC_007  ")
  assert_eq(@moon_pyversion.Version::to_string(v), "1.2rc3+abc.7")
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
    assert_eq(@moon_pyversion.Version::normalize(entry.0), entry.1)
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
      ignore(@moon_pyversion.Version::parse(raw))
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
  assert_true(
    @moon_pyversion.Version::parse("1.0+a1") <
    @moon_pyversion.Version::parse("1.0+x"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+aa") <
    @moon_pyversion.Version::parse("1.0+b"),
  )
  assert_true(
    @moon_pyversion.Version::parse("1.0+a") <
    @moon_pyversion.Version::parse("1.0+aa"),
  )
  assert_true(
    @moon_pyversion.Version::parse("0.0+a1") <
    @moon_pyversion.Version::parse("0+x"),
  )
}

///|
/// The next-release helpers answer with release numbers, not with the
/// smallest version above: pre/post/dev and local parts are dropped, the
/// epoch survives, and short releases zero-pad before the bump.
test "next_major bumps the first digit and drops the rest" {
  let cases : Array[(String, String)] = [
    ("1.2.3", "2"),
    ("0.9", "1"),
    ("1!1.9", "1!2"),
    ("1.2.3rc4+local", "2"),
    ("1.0.post3", "2"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::next_major(v).to_string(), entry.1)
  }
}

///|
test "next_minor pads to two digits and bumps the second" {
  let cases : Array[(String, String)] = [
    ("1.2.3", "1.3"),
    ("2", "2.1"),
    ("1.9.9", "1.10"),
    ("1!2.0.dev1", "1!2.1"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::next_minor(v).to_string(), entry.1)
  }
}

///|
test "next_patch pads to three digits and bumps the third" {
  let cases : Array[(String, String)] = [
    ("1.2.3", "1.2.4"),
    ("1.2", "1.2.1"),
    ("0", "0.0.1"),
    ("10.0.0.post1", "10.0.1"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::next_patch(v).to_string(), entry.1)
  }
}

///|
/// The helpers compose the way release planning does: after a major bump
/// the minor and patch dimensions restart from zero, so the first patch of
/// the next major is `<next>.0.1`, not a carry of the old digits.
test "next helpers chain across dimensions" {
  let v = @moon_pyversion.Version::parse("1.2.3")
  let next_major = @moon_pyversion.Version::next_major(v)
  assert_eq(
    @moon_pyversion.Version::next_patch(next_major).to_string(),
    "2.0.1",
  )
  assert_eq(@moon_pyversion.Version::next_minor(next_major).to_string(), "2.1")
  let next_minor = @moon_pyversion.Version::next_minor(v)
  assert_eq(
    @moon_pyversion.Version::next_patch(next_minor).to_string(),
    "1.3.1",
  )
  // Every bumped form is a final release above its origin.
  assert_true(@moon_pyversion.Version::next_patch(v) > v)
  assert_true(@moon_pyversion.Version::next_minor(v) > v)
  assert_true(@moon_pyversion.Version::next_major(v) > v)
  assert_false(
    @moon_pyversion.Version::is_prerelease(
      @moon_pyversion.Version::next_patch(
        @moon_pyversion.Version::parse("1.2.3.dev4"),
      ),
    ),
  )
}

///|
/// On a final release the bump family answers exactly what next_ answers:
/// the suffix policy only differs once there is a pre or dev stage to
/// carry.
test "bump matches next on final releases" {
  let cases : Array[(String, String, String, String)] = [
    // input, bump_major, bump_minor, bump_patch
    ("1.2.3", "2", "1.3", "1.2.4"),
    ("0.9", "1", "0.10", "0.9.1"),
    ("2", "3", "2.1", "2.0.1"),
    ("1!1.9", "1!2", "1!1.10", "1!1.9.1"),
    ("1.0.post3", "2", "1.1", "1.0.1"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::bump_major(v).to_string(), entry.1)
    assert_eq(@moon_pyversion.Version::bump_minor(v).to_string(), entry.2)
    assert_eq(@moon_pyversion.Version::bump_patch(v).to_string(), entry.3)
  }
}

///|
/// A pre-release keeps riding its cycle: the release number advances, the
/// stage and its number survive verbatim. The result sorts between its own
/// input and the bumped final, which is the order a release cycle expects.
test "bump carries the pre-release stage to the advanced number" {
  let cases : Array[(String, String, String, String)] = [
    ("1.2.3rc1", "2rc1", "1.3rc1", "1.2.4rc1"),
    ("1.2.3a2", "2a2", "1.3a2", "1.2.4a2"),
    ("1.2.3b3", "2b3", "1.3b3", "1.2.4b3"),
    ("1rc1", "2rc1", "1.1rc1", "1.0.1rc1"),
    ("1.2.3c2", "2rc2", "1.3rc2", "1.2.4rc2"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::bump_major(v).to_string(), entry.1)
    assert_eq(@moon_pyversion.Version::bump_minor(v).to_string(), entry.2)
    assert_eq(@moon_pyversion.Version::bump_patch(v).to_string(), entry.3)
  }
  // The promoted pre-release stays ordered: input < promoted < final.
  let rc = @moon_pyversion.Version::parse("1.2.3rc1")
  let promoted = @moon_pyversion.Version::bump_minor(rc)
  assert_true(rc < promoted)
  assert_true(
    promoted <
    @moon_pyversion.Version::bump_minor(@moon_pyversion.Version::parse("1.2.3")),
  )
  assert_true(
    @moon_pyversion.Version::is_prerelease(
      @moon_pyversion.Version::bump_minor(rc),
    ),
  )
}

///|
/// Dev releases carry like pre-releases; a post-release never does - it
/// patches the release it rides on, and the bumped number is a different
/// release. A post+dev version keeps only the dev half.
test "bump carries dev releases but drops post-releases" {
  let cases : Array[(String, String, String, String)] = [
    ("1.2.3.dev4", "2.dev4", "1.3.dev4", "1.2.4.dev4"),
    ("1.2.3.post1", "2", "1.3", "1.2.4"),
    ("1.2.3.post1.dev2", "2.dev2", "1.3.dev2", "1.2.4.dev2"),
    ("1.2.3rc1.dev5", "2rc1.dev5", "1.3rc1.dev5", "1.2.4rc1.dev5"),
    ("1.2.3rc1+local", "2rc1", "1.3rc1", "1.2.4rc1"),
  ]
  for entry in cases {
    let v = @moon_pyversion.Version::parse(entry.0)
    assert_eq(@moon_pyversion.Version::bump_major(v).to_string(), entry.1)
    assert_eq(@moon_pyversion.Version::bump_minor(v).to_string(), entry.2)
    assert_eq(@moon_pyversion.Version::bump_patch(v).to_string(), entry.3)
  }
  // A dev-only bump stays below the cycle it is working toward.
  let dev = @moon_pyversion.Version::parse("1.2.3.dev4")
  let promoted = @moon_pyversion.Version::bump_minor(dev)
  assert_true(dev < promoted)
  assert_true(promoted < @moon_pyversion.Version::parse("1.3a1"))
}
