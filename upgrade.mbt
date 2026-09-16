///|
/// Scenario 3: the upgrade shortlist.
///
/// "Which of these candidates is worth a test run?" is a decision a tool makes
/// constantly, and the only part of it this library can decide is the version
/// part. This module decides that part and keeps the rest out:
///
/// ```moonbit nocheck
/// let plan = upgrade_shortlist(current, Some(target), None, Some(python), candidates)
/// plan.shortlist   // ascending: the smallest step first
/// plan.dropped     // every other candidate with the rule that dropped it
/// ```
///
/// The rules, **in the order they are applied**, because the first one that fires
/// is the reason the caller is told:
///
/// 1. the candidate's version does not parse -> `Unparsable`. This is checked
///    first because there is nothing to compare otherwise;
/// 2. it is equal to the current version -> `Same`. Equal is decided by
///    `Version::compare`, so `1.5` and `1.5.0` are the same version;
/// 3. it is lower -> `Downgrade`;
/// 4. it is outside the target range -> `OutOfRange`;
/// 5. it is inside the range but the prerelease policy holds it back ->
///    `Prerelease`. The policy is `SpecifierSet::filter`'s, so `None` (the
///    automatic policy) admits prereleases **only when the range admits nothing
///    else** -- and that fallback is computed over the candidates that are newer
///    and inside the range, not over the whole input. The policy reaches the
///    candidates **through the range**: with no target range there is nothing to
///    filter, so `Some(false)` has nothing to do and prereleases are kept. That
///    is the same choice `filter` makes (a `SpecifierSet` with no clauses does
///    not filter), and it is pinned by a unit test and by the corpus;
/// 6. its `requires-python` excludes the target interpreter ->
///    `RequiresPython`. A `requires-python` that does not parse is ignored rather
///    than treated as a rejection, which is what pip does and what
///    `index.mbt`'s resolver already does;
/// 7. otherwise it is kept.
///
/// The shortlist is ordered ascending, ties broken by the caller's spelling, so
/// two spellings of one version stay two entries and the order is stable. The
/// dropped list keeps the order the rules ran in, and within one rule the order
/// the caller listed the candidates.
///
/// **What this does not answer.** A version on the shortlist satisfies a
/// constraint; that is a necessary condition, not a reason to upgrade. API
/// compatibility, dependency solvability, security advisories and whether the
/// test suite passes are all outside this module, and a caller that presents the
/// shortlist as a recommendation is misusing it. `examples/upgrade-check` prints
/// that sentence in its own output rather than leaving it in a comment.

///|
/// One candidate to consider.
///
/// `version` is `None` when the caller's spelling is not a PEP 440 version at
/// all: the candidate is then reported as `Unparsable` instead of being dropped
/// from the list, so a report can account for every input it was given.
pub(all) struct UpgradeCandidate {
  raw : String
  version : Version?
  requires_python : String?
} derive(Eq, @debug.Debug)

///|
/// Parse a candidate's version, and remember the `requires-python` it declares
/// (if any) as text: this module compares it against the target interpreter, and
/// the comparison is the only thing it needs it for.
///
/// ```moonbit nocheck
/// let c = UpgradeCandidate::parse("1.2.3", Some(">=3.8"))
/// c.version.unwrap().to_string()   // "1.2.3"
/// ```
pub fn UpgradeCandidate::parse(
  raw : String,
  requires_python : String?,
) -> UpgradeCandidate {
  let version = if raw.is_empty() { None } else { parse_version_opt(raw) }
  { raw, version, requires_python, }
}

///|
/// The rule that dropped a candidate. Closed on purpose: a report that says
/// "rejected" without saying why is not actionable, and the differential corpus
/// asserts the exact reason for each candidate.
pub(all) enum UpgradeRejection {
  Unparsable
  Same
  Downgrade
  OutOfRange
  Prerelease
  RequiresPython
} derive(Eq, @debug.Debug)

///|
/// The stable spelling of a rejection rule, for reports and for the corpus.
pub fn UpgradeRejection::code(self : UpgradeRejection) -> String {
  match self {
    Unparsable => "unparsable"
    Same => "same"
    Downgrade => "downgrade"
    OutOfRange => "out-of-range"
    Prerelease => "prerelease"
    RequiresPython => "requires-python"
  }
}

///|
/// The result: what to test, and what was dropped with the reason.
pub(all) struct UpgradePlan {
  shortlist : Array[UpgradeCandidate]
  dropped : Array[(UpgradeCandidate, UpgradeRejection)]
} derive(@debug.Debug)

///|
/// Decide the version part of an upgrade. See the module documentation for the
/// rule order; every input candidate appears exactly once in the result, either
/// in `shortlist` or in `dropped`.
pub fn upgrade_shortlist(
  current : Version,
  target : SpecifierSet?,
  prereleases : Bool?,
  python : Version?,
  candidates : Array[UpgradeCandidate],
) -> UpgradePlan {
  let newer : Array[UpgradeCandidate] = []
  let dropped : Array[(UpgradeCandidate, UpgradeRejection)] = []
  // Rules 1 to 3, in the caller's order.
  for candidate in candidates {
    match candidate.version {
      None => dropped.push((candidate, Unparsable))
      Some(version) => {
        let order = Version::compare(version, current)
        if order == 0 {
          dropped.push((candidate, Same))
        } else if order < 0 {
          dropped.push((candidate, Downgrade))
        } else {
          newer.push(candidate)
        }
      }
    }
  }
  // Rules 4 and 5 together: the range and the policy are one question, and
  // `SpecifierSet::filter` is the function that answers it -- including the
  // "admit prereleases only when nothing else survives" fallback. Reusing it
  // means this module cannot disagree with `filter` about what `auto` means.
  let newer_versions : Array[Version] = []
  for candidate in newer {
    match candidate.version {
      Some(version) => newer_versions.push(version)
      None => ()
    }
  }
  let admitted : Array[Bool] = []
  for _version in newer_versions {
    admitted.push(false)
  }
  match target {
    Some(spec) => {
      let kept = SpecifierSet::filter(newer_versions, spec, prereleases~)
      for version in kept {
        // Match by value and take the first unconsumed slot, so two spellings of
        // the same version are both admitted rather than one being dropped.
        for i = 0; i < newer_versions.length(); i = i + 1 {
          if !admitted[i] && Version::compare(newer_versions[i], version) == 0 {
            admitted[i] = true
            break
          }
        }
      }
    }
    None =>
      for i = 0; i < admitted.length(); i = i + 1 {
        admitted[i] = true
      }
  }
  let inside : Array[UpgradeCandidate] = []
  for i = 0; i < newer.length(); i = i + 1 {
    let candidate = newer[i]
    if admitted[i] {
      inside.push(candidate)
    } else if target is Some(spec) {
      // Inside the range and held back by the policy is a different answer from
      // outside the range, and the report keeps them apart.
      let contained = match candidate.version {
        Some(version) => spec.contains(version, prereleases=Some(true))
        None => false
      }
      if contained {
        dropped.push((candidate, Prerelease))
      } else {
        dropped.push((candidate, OutOfRange))
      }
    } else {
      dropped.push((candidate, OutOfRange))
    }
  }
  // Rule 6: `requires-python`. An unreadable value is ignored, not rejected.
  let kept : Array[UpgradeCandidate] = []
  for candidate in inside {
    let mut allowed = true
    match (candidate.requires_python, python) {
      (Some(text), Some(python_version)) =>
        if text != "" {
          match parse_requires_python(text) {
            Some(spec) =>
              allowed = spec.contains(python_version, prereleases=Some(true))
            None => ()
          }
        }
      _ => ()
    }
    if allowed {
      kept.push(candidate)
    } else {
      dropped.push((candidate, RequiresPython))
    }
  }
  // Ascending: the smallest step is the one to test first. The raw spelling
  // breaks ties so the order is stable when two candidates are one version.
  // A kept candidate always has a version, so the comparator below pairs each
  // one with it once instead of re-deciding that inside the loop.
  let ordered : Array[(Version, UpgradeCandidate)] = []
  for candidate in kept {
    match candidate.version {
      Some(version) => ordered.push((version, candidate))
      None => ()
    }
  }
  ordered.sort_by(fn(a, b) {
    let order = Version::compare(a.0, b.0)
    if order != 0 {
      order
    } else {
      String::lexical_compare(a.1.raw, b.1.raw)
    }
  })
  let shortlist : Array[UpgradeCandidate] = []
  for entry in ordered {
    shortlist.push(entry.1)
  }
  { shortlist, dropped, }
}

///|
/// A candidate's `requires-python`, or `None` when it does not parse -- the
/// caller is told nothing and the candidate stays in the shortlist, which is what
/// pip does with a `Requires-Python` it cannot read.
fn parse_requires_python(text : String) -> SpecifierSet? {
  Some(SpecifierSet::parse(text)) catch {
    _ => None
  }
}

///|
/// The shortlist as the versions to try, most useful first. A convenience for a
/// caller that only needs the versions and not the spellings.
pub fn UpgradePlan::versions(self : UpgradePlan) -> Array[Version] {
  let out : Array[Version] = []
  for candidate in self.shortlist {
    match candidate.version {
      Some(version) => out.push(version)
      None => ()
    }
  }
  out
}

///|
/// Whether the plan found anything at all. A tool that prints "nothing to test"
/// should ask this rather than check `shortlist().length()`, because the two
/// cases it distinguishes -- "no candidate is newer" and "no candidate was
/// given" -- read differently to a user.
pub fn UpgradePlan::is_empty(self : UpgradePlan) -> Bool {
  self.shortlist.is_empty()
}

///|
/// One line per dropped candidate, in the order the rules ran, for a report.
pub fn UpgradePlan::rejection_summary(self : UpgradePlan) -> String {
  let parts : Array[String] = []
  for entry in self.dropped {
    parts.push("\{entry.0.raw}=\{entry.1.code()}")
  }
  parts.join(";")
}
