///|
/// Parse a version in a test, or abort: a test that cannot express its input has
/// nothing to say about the code under it. The `try` form is used because these
/// are black-box tests -- they see the public API only, which is the point: a
/// rule that is not reachable from outside the package is not a rule a caller
/// can rely on.
fn up_version(text : String) -> Version {
  Version::parse(text) catch {
    _ => abort("test input is not a version: \{text}")
  }
}

///|
fn up_spec(text : String) -> SpecifierSet {
  SpecifierSet::parse(text) catch {
    _ => abort("test input is not a specifier set: \{text}")
  }
}

///|
fn up_candidate(raw : String) -> UpgradeCandidate {
  UpgradeCandidate::parse(raw, None)
}

///|
fn up_candidate_with(
  raw : String,
  requires_python : String,
) -> UpgradeCandidate {
  UpgradeCandidate::parse(raw, Some(requires_python))
}

///|
/// The shortlist as raw spellings, which is what a report prints.
fn up_kept(plan : UpgradePlan) -> Array[String] {
  let out : Array[String] = []
  for candidate in plan.shortlist {
    out.push(candidate.raw)
  }
  out
}

///|
/// The dropped candidates as `raw=reason`, which is what the corpus projects.
fn up_dropped(plan : UpgradePlan) -> Array[String] {
  let out : Array[String] = []
  for entry in plan.dropped {
    out.push("\{entry.0.raw}=\{entry.1.code()}")
  }
  out
}

///|
test "upgrade: a newer candidate inside the range is kept, ascending" {
  let plan = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    None,
    None,
    [up_candidate("1.9"), up_candidate("1.2"), up_candidate("1.10")],
  )
  // Ascending, because the smallest step is the one to test first.
  assert_eq(up_kept(plan), ["1.2", "1.9", "1.10"])
  assert_true(plan.dropped.is_empty())
}

///|
test "upgrade: the current version is the boundary of newer" {
  let plan = upgrade_shortlist(up_version("1.5"), None, None, None, [
    up_candidate("1.4"),
    up_candidate("1.5"),
    up_candidate("1.6"),
  ])
  assert_eq(up_kept(plan), ["1.6"])
  assert_eq(up_dropped(plan), ["1.4=downgrade", "1.5=same"])
}

///|
test "upgrade: equal versions are equal whatever their spelling" {
  // `1.5` and `1.5.0` are one version, so neither is an upgrade of the other;
  // `Version::compare` decides that, not the spelling.
  let plan = upgrade_shortlist(up_version("1.5.0"), None, None, None, [
    up_candidate("1.5"),
    up_candidate("1.5.0"),
    up_candidate("1.5.0.0"),
  ])
  assert_true(plan.is_empty())
  assert_eq(up_dropped(plan), ["1.5=same", "1.5.0=same", "1.5.0.0=same"])
}

///|
test "upgrade: two spellings of one newer version are both kept" {
  // The shortlist is a list of candidates, not of version keys: a caller that
  // listed the same version twice gets it twice, in spelling order, so the report
  // still accounts for every input.
  let plan = upgrade_shortlist(up_version("1.0"), None, None, None, [
    up_candidate("1.1.0"),
    up_candidate("1.1"),
    up_candidate("1.1.0.0"),
  ])
  assert_eq(up_kept(plan), ["1.1", "1.1.0", "1.1.0.0"])
}

///|
test "upgrade: outside the range is a different answer from held back" {
  // `2.0` is outside the range at all; `1.9rc1` is inside it and dropped by the
  // policy. A report that called both "rejected" would lose that distinction.
  let plan = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec("<2.0")),
    None,
    None,
    [up_candidate("2.0"), up_candidate("1.9rc1"), up_candidate("1.5")],
  )
  assert_eq(up_kept(plan), ["1.5"])
  assert_eq(up_dropped(plan), ["2.0=out-of-range", "1.9rc1=prerelease"])
}

///|
test "upgrade: the automatic policy admits prereleases only when nothing else survives" {
  // The interesting rule. With a final candidate present the prerelease is held
  // back; with only prereleases, the automatic policy falls back to them, since
  // refusing would report "nothing to test" when there is something.
  let with_final = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    None,
    None,
    [up_candidate("1.1b1"), up_candidate("1.1")],
  )
  assert_eq(up_kept(with_final), ["1.1"])
  assert_eq(up_dropped(with_final), ["1.1b1=prerelease"])
  let only_pre = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    None,
    None,
    [up_candidate("1.1b1")],
  )
  assert_eq(up_kept(only_pre), ["1.1b1"])
  assert_true(only_pre.dropped.is_empty())
}

///|
test "upgrade: the forced policies are the two ends of that" {
  let candidates = [
    up_candidate("1.1b1"),
    up_candidate("1.1"),
    up_candidate("1.2.dev1"),
  ]
  let forced_on = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    Some(true),
    None,
    candidates,
  )
  assert_eq(up_kept(forced_on), ["1.1b1", "1.1", "1.2.dev1"])
  let forced_off = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    Some(false),
    None,
    candidates,
  )
  // `Some(false)` has no fallback: the finals survive and the prereleases do not,
  // even though dropping them leaves a non-empty shortlist anyway.
  assert_eq(up_kept(forced_off), ["1.1"])
  assert_eq(up_dropped(forced_off), ["1.1b1=prerelease", "1.2.dev1=prerelease"])
}

///|
test "upgrade: a dev release is a prerelease and a post release is not" {
  // The policy reaches the candidates through the range, so a range is required
  // for it to have any effect at all -- see the next block for the case where it
  // is not consulted.
  let dev = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    Some(false),
    None,
    [up_candidate("1.1.dev1")],
  )
  assert_eq(up_dropped(dev), ["1.1.dev1=prerelease"])
  let post = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    Some(false),
    None,
    [up_candidate("1.0.post1")],
  )
  assert_eq(up_kept(post), ["1.0.post1"])
}

///|
test "upgrade: without a target range the prerelease policy is not consulted" {
  // There is nothing to filter, so `Some(false)` has nothing to do: the policy
  // is `SpecifierSet::filter`'s, and `filter` only ever sees the range. A caller
  // that wants prereleases gone with no range in mind has to say so by passing
  // the range, not by passing the policy.
  let plan = upgrade_shortlist(up_version("1.0"), None, Some(false), None, [
    up_candidate("1.1b1"),
    up_candidate("1.1"),
  ])
  assert_eq(up_kept(plan), ["1.1b1", "1.1"])
  assert_true(plan.dropped.is_empty())
}

///|
test "upgrade: requires-python excludes a candidate, an unreadable one does not" {
  let plan = upgrade_shortlist(
    up_version("1.0"),
    None,
    None,
    Some(up_version("3.11")),
    [
      up_candidate_with("1.1", ">=3.8"),
      up_candidate_with("1.2", ">=3.12"),
      up_candidate_with("1.3", "not a specifier"),
      up_candidate("1.4"),
    ],
  )
  // `1.3`'s value cannot be read, so it is ignored rather than treated as a
  // rejection -- the same choice pip makes and `index.mbt`'s resolver already
  // made. `1.4` declares nothing, which means "no constraint".
  assert_eq(up_kept(plan), ["1.1", "1.3", "1.4"])
  assert_eq(up_dropped(plan), ["1.2=requires-python"])
}

///|
test "upgrade: requires-python is skipped when no interpreter is given" {
  let plan = upgrade_shortlist(up_version("1.0"), None, None, None, [
    up_candidate_with("1.1", ">=3.12"),
  ])
  assert_eq(up_kept(plan), ["1.1"])
}

///|
test "upgrade: a candidate whose version does not parse is reported, not dropped" {
  let plan = upgrade_shortlist(up_version("1.0"), None, None, None, [
    up_candidate("not-a-version"),
    up_candidate("1.1"),
  ])
  // The ordering rule cannot run without a version, so `Unparsable` is decided
  // first -- and the candidate still appears in the report.
  assert_eq(up_kept(plan), ["1.1"])
  assert_eq(up_dropped(plan), ["not-a-version=unparsable"])
  // An empty spelling is unparsable too, rather than being read as "0".
  assert_eq(
    up_dropped(
      upgrade_shortlist(up_version("1.0"), None, None, None, [up_candidate("")]),
    ),
    ["=unparsable"],
  )
}

///|
test "upgrade: the first rule that fires is the reason" {
  // `1.2` is older than the current version *and* excluded by requires-python;
  // it is reported as a downgrade, because that is the rule that ran first. The
  // corpus pins this order on both sides, so the two implementations cannot
  // disagree about which reason a caller is told.
  let plan = upgrade_shortlist(
    up_version("1.5"),
    Some(up_spec(">=1.5,<2.0")),
    None,
    Some(up_version("3.11")),
    [
      up_candidate_with("1.2", ">=3.12"),
      up_candidate_with("2.5", ">=3.12"),
      up_candidate_with("1.4", ">=3.12"),
      up_candidate_with("1.6", ">=3.12"),
    ],
  )
  assert_true(plan.is_empty())
  // `1.2` is older *and* excluded by requires-python, and it is reported as a
  // downgrade; `1.6` is newer and inside the range, and it is reported as
  // requires-python. The order of the reasons is the order the rules ran in.
  assert_eq(up_dropped(plan), [
    "1.2=downgrade", "1.4=downgrade", "2.5=out-of-range", "1.6=requires-python",
  ])
}

///|
test "upgrade: no target range means the range rule is skipped" {
  let plan = upgrade_shortlist(up_version("1.0"), None, None, None, [
    up_candidate("0.9"),
    up_candidate("1.0"),
    up_candidate("2.0"),
  ])
  assert_eq(up_kept(plan), ["2.0"])
  assert_eq(up_dropped(plan), ["0.9=downgrade", "1.0=same"])
}

///|
test "upgrade: an empty candidate list is not an error" {
  let plan = upgrade_shortlist(
    up_version("1.0"),
    Some(up_spec(">=1.0")),
    None,
    None,
    [],
  )
  assert_true(plan.is_empty())
  assert_true(plan.dropped.is_empty())
  assert_eq(plan.rejection_summary(), "")
}

///|
test "upgrade: the summary is the vocabulary the corpus projects" {
  let plan = upgrade_shortlist(
    up_version("1.5"),
    Some(up_spec(">=1.5,<2.0")),
    None,
    None,
    [
      up_candidate("nope"),
      up_candidate("1.4"),
      up_candidate("2.5"),
      up_candidate("1.5"),
      up_candidate("1.6"),
    ],
  )
  // Both halves of the projection a corpus record carries.
  assert_eq(up_kept(plan), ["1.6"])
  // Grouped by the rule that ran, and within a rule in the caller's order: the
  // ordering rules first, then the range. That is the vocabulary and the order
  // the corpus projects, so the two implementations cannot disagree about it.
  assert_eq(
    plan.rejection_summary(),
    "nope=unparsable;1.4=downgrade;1.5=same;2.5=out-of-range",
  )
  assert_eq(plan.versions().length(), 1)
  assert_eq(Version::to_string(plan.versions()[0]), "1.6")
}
