///|
/// Scenario 3, end to end: from a current version and a candidate list to the
/// shortlist of versions worth testing.
///
/// The report answers one question -- *which of these candidates is worth
/// spending a test run on?* -- and then says, in its own words, **what that
/// answer does not mean**. The two halves matter equally, because "satisfies the
/// version constraint" is the only thing this library can decide, and it is not
/// the same as "safe to upgrade".
///
/// The decision has four inputs and six rules, applied in order:
///
/// 1. **the candidate parses** as a PEP 440 version (otherwise `unparsable`);
/// 2. **it is newer than the current version** (`same` / `downgrade` otherwise --
///    an equal version is not an upgrade even when the spelling differs, because
///    `1.5` and `1.5.0` are the same version);
/// 3. **it is inside the target range** (`out-of-range` otherwise);
/// 4. **the prerelease policy admits it** (`prerelease` otherwise). The policy is
///    `SpecifierSet::filter`'s, which is the interesting one: `auto` admits a
///    prerelease only when the range admits nothing else, so `1.1b1` is dropped
///    when `1.1` exists and kept when it does not. That fallback is computed over
///    the candidates that are newer and inside the range, because those are the
///    ones this report is about;
/// 5. **its `requires-python` admits the target interpreter**
///    (`requires-python` otherwise). An unreadable `requires-python` is ignored
///    rather than treated as a rejection, which is what pip does and what this
///    library's own resolver already does;
/// 6. everything else is **kept**, and the shortlist is ordered **ascending** --
///    the smallest step first is the one to test first.
///
/// ## Why the inputs are compiled in
///
/// The library depends on `moonbitlang/core` only, and that package has no
/// filesystem API, so the candidate lists are written into this file rather than
/// read from an index. They cover the same decisions the differential corpus
/// asserts case by case (`fixtures/upgrade_corpus.mbt`, replayed against
/// `packaging`), so the example and the corpus describe the same behaviour; an
/// application replaces the lists below with whatever its index client returned.
/// Everything here is deterministic: no clock, no environment, no I/O. The output
/// is byte identical on wasm, wasm-gc, js and native.
///
/// ```sh
/// moon run examples/upgrade-check --target js
/// ```

///|
/// `1.2.3@>=3.8` -> a candidate. `@` is the separator because it cannot appear in
/// a version, and a `requires-python` may contain commas and spaces but not one.
fn parse_candidate(raw : String) -> @pyversion.UpgradeCandidate {
  let parts = raw.split("@").collect()
  if parts.length() == 2 {
    @pyversion.UpgradeCandidate::parse(
      parts[0].to_owned(),
      Some(parts[1].to_owned()),
    )
  } else {
    @pyversion.UpgradeCandidate::parse(raw, None)
  }
}

///|
fn parse_version(text : String) -> @pyversion.Version? {
  if text == "" {
    return None
  }
  Some(@pyversion.Version::parse(text)) catch {
    _ => None
  }
}

///|
fn parse_specifier(text : String) -> @pyversion.SpecifierSet? {
  if text == "" {
    return None
  }
  Some(@pyversion.SpecifierSet::parse(text)) catch {
    _ => None
  }
}

///|
/// The prerelease policy in the spelling `upgrade_shortlist` expects: `None` is
/// the automatic policy, `Some(true)` forces prereleases on and `Some(false)`
/// forces them off. The library takes the tri-state directly, because the
/// automatic policy and "force them on" are genuinely different answers.
fn prerelease_policy(code : String) -> Bool? {
  if code == "any" {
    Some(true)
  } else if code == "none" {
    Some(false)
  } else {
    None
  }
}

///|
/// One scenario: everything the decision needs, plus the name the report uses.
struct Scenario {
  name : String
  current : String
  target : String
  prereleases : String
  python : String
  candidates : Array[String]
}

///|
/// A named target: the range, the policy and the interpreter. The scenarios below
/// show the same candidate list under all three policies, because "which
/// prereleases are worth testing" is exactly what the policy decides and it is
/// easy to get wrong.
fn scenarios() -> Array[Scenario] {
  let prerelease_list : Array[String] = [
    "1.0.0a1", "1.0.0b1", "1.0.0rc1", "1.0.0", "1.1.0.dev1", "1.1.0",
  ]
  [
    {
      name: "patch and minor only",
      current: "1.2.3",
      target: ">=1.2.3,<2.0",
      prereleases: "auto",
      python: "3.11",
      candidates: ["1.2.4", "1.3.0", "2.0.0", "1.2.2", "1.2.3"],
    },
    {
      name: "a window with both bounds",
      current: "1.0",
      target: ">=1.5,<1.8",
      prereleases: "auto",
      python: "3.11",
      candidates: ["1.4", "1.4.9", "1.5", "1.6.1", "1.7", "1.7.9", "1.8", "1.9"],
    },
    {
      name: "prereleases, automatic policy",
      current: "0.9.0",
      target: ">=0.9",
      prereleases: "auto",
      python: "3.10",
      candidates: prerelease_list,
    },
    {
      name: "prereleases, forced on",
      current: "0.9.0",
      target: ">=0.9",
      prereleases: "any",
      python: "3.10",
      candidates: prerelease_list,
    },
    {
      name: "prereleases, forced off",
      current: "0.9.0",
      target: ">=0.9",
      prereleases: "none",
      python: "3.10",
      candidates: prerelease_list,
    },
    {
      name: "requires-python narrows it",
      current: "2.3.0",
      target: ">=2.3,<3.0",
      prereleases: "auto",
      python: "3.11",
      candidates: [
        "2.3.1", "2.3.2@>=3.8", "2.3.3@>=3.12", "2.4.0rc1", "2.4.0", "3.0.0",
      ],
    },
    {
      name: "everything at once",
      current: "1.26.0",
      target: ">=1.26,<2.0",
      prereleases: "auto",
      python: "3.11",
      candidates: [
        "1.25.2", "1.26.0", "1.26.4", "1.27.0rc1", "1.27.0", "1.28.0@>=3.13", "2.0.0",
        "not-a-version",
      ],
    },
    {
      name: "no target range at all",
      current: "1.0.0",
      target: "",
      prereleases: "auto",
      python: "3.11",
      candidates: ["0.9.0", "1.0.0", "1.1.0", "2.0.0"],
    },
  ]
}

///|
/// Print one scenario. Every input is accounted for: the shortlist, or the reason
/// it was dropped.
fn report(scenario : Scenario) -> Unit {
  println("== \{scenario.name}")
  println(
    "   current \{scenario.current}; target \{if scenario.target == "" { "(none)" } else { scenario.target }}; prereleases \{scenario.prereleases}; CPython \{scenario.python}",
  )
  let current = parse_version(scenario.current)
  if current is None {
    println(
      "   UNPARSABLE_CURRENT: the current version is not a PEP 440 version",
    )
    println("")
    return
  }
  let target = parse_specifier(scenario.target)
  if scenario.target != "" && target is None {
    println("   BAD_TARGET: the target range is not a valid specifier set")
    println("")
    return
  }
  let candidates : Array[@pyversion.UpgradeCandidate] = []
  for raw in scenario.candidates {
    candidates.push(parse_candidate(raw))
  }
  // Positional, not labelled: the four inputs are the whole point of the call.
  let plan = @pyversion.upgrade_shortlist(
    current.unwrap(),
    target,
    prerelease_policy(scenario.prereleases),
    parse_version(scenario.python),
    candidates,
  )
  println(
    "   \{candidates.length()} candidate(s): \{plan.shortlist.length()} in the shortlist, \{plan.dropped.length()} dropped",
  )
  if plan.is_empty() {
    println("   shortlist: (nothing to test)")
  } else {
    println(
      "   shortlist, smallest step first: \{plan.versions().map(fn(v) { v.to_string() }).join(" ")}",
    )
  }
  // The dropped list is printed with the rule that dropped it, in the order the
  // rules ran: a report that says "rejected" alone is not actionable.
  for entry in plan.dropped {
    println("   dropped \{entry.0.raw}: \{entry.1.code()}")
  }
  println("")
}

///|
fn main {
  let scenarios = scenarios()
  println(
    "upgrade check: which candidates are worth a test run, and what that does not mean",
  )
  println("")
  for scenario in scenarios {
    report(scenario)
  }
  println("== what this report does not check")
  println(
    "   \"inside the target range, newer than what is installed\" is the only question",
  )
  println(
    "   this library answers. It does not check API or behaviour compatibility,",
  )
  println(
    "   dependency solvability, security advisories, build or test failures, or the",
  )
  println(
    "   release notes. A version on this shortlist is a candidate for a test run,",
  )
  println(
    "   not a recommendation, and a version left off it is not a statement that the",
  )
  println("   version is broken.")
}
