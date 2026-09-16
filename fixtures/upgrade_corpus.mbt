///|
/// Upgrade-shortlist cases for `examples/upgrade-check`. Each entry is
/// `(name, payload, projection)`; the payload is
/// `<current>|<target spec>|<mode>|<python>|<candidate>;<candidate>` and the
/// projection is `<shortlist, ascending>|<rejected as v=reason;...>`, or a
/// `!CODE` when the whole case cannot be decided.
///
/// Regenerate with tools/fetch_upgrade_corpus.py; do not edit by hand.
pub let upgrade_cases : Array[(String, String, String)] = [
  (
    "no-target-range", "1.0.0||auto|3.11|1.0.0;1.1.0;2.0.0;0.9.0", "1.1.0,2.0.0|1.0.0=same;0.9.0=downgrade",
  ),
  (
    "patch-and-minor-only", "1.2.3|>=1.2.3,<2.0|auto|3.11|1.2.4;1.3.0;2.0.0;1.2.2",
    "1.2.4,1.3.0|1.2.2=downgrade;2.0.0=out-of-range",
  ),
  (
    "target-range-is-a-window", "1.0|>=1.5,<1.8|auto|3.11|1.4;1.5;1.6.1;1.7;1.8;1.9",
    "1.5,1.6.1,1.7|1.4=out-of-range;1.8=out-of-range;1.9=out-of-range",
  ),
  (
    "upper-bound-excludes-the-boundary", "1.0|<2.0|auto|3.11|1.9.9;2.0;2.0.1", "1.9.9|2.0=out-of-range;2.0.1=out-of-range",
  ),
  (
    "lower-bound-includes-the-current", "1.0|>=1.0|auto|3.11|1.0;1.0.1", "1.0.1|1.0=same",
  ),
  (
    "lower-bound-excludes-the-current", "1.0|>1.0|auto|3.11|1.0;1.0.1", "1.0.1|1.0=same",
  ),
  (
    "every-candidate-out-of-range", "1.0|>=2.0|auto|3.11|1.0.1;1.5", "|1.0.1=out-of-range;1.5=out-of-range",
  ),
  ("one-candidate-only", "0.1|>=0.2|auto|3.11|0.2", "0.2|"),
  ("no-candidates", "1.0|>=1.0|auto|3.11|", "|"),
  (
    "nothing-newer-than-the-current", "9.9||auto|3.11|1.0;2.0", "|1.0=downgrade;2.0=downgrade",
  ),
  (
    "shortlist-is-ascending", "1.0|>=1.0|auto|3.11|1.9;1.2;1.5;1.10", "1.2,1.5,1.9,1.10|",
  ),
  (
    "duplicate-spellings-of-one-version", "1.0||auto|3.11|1.1;1.1.0;1.1.0.0", "1.1,1.1.0,1.1.0.0|",
  ),
  (
    "local-versions-order-after-their-release", "1.0||auto|3.11|1.1;1.1+local", "1.1,1.1+local|",
  ),
  (
    "normalized-equal-version-is-not-an-upgrade", "1.5.0||auto|3.11|1.5;1.5.0", "|1.5=same;1.5.0=same",
  ),
  ("epoch-makes-a-version-newer", "1.0||auto|3.11|1!0.1;1.0.1", "1.0.1,1!0.1|"),
  (
    "epoch-on-the-current-version", "1!1.0||auto|3.11|1!1.1;2.0", "1!1.1|2.0=downgrade",
  ),
  (
    "equal-version-is-not-an-upgrade", "1.5||auto|3.11|1.4;1.5;1.6", "1.6|1.4=downgrade;1.5=same",
  ),
  (
    "downgrade-only", "2.0||auto|3.11|1.9;1.0;0.1", "|1.9=downgrade;1.0=downgrade;0.1=downgrade",
  ),
  (
    "prerelease-auto-dropped-when-a-final-exists", "1.0|>=1.0|auto|3.11|1.1b1;1.1",
    "1.1|1.1b1=prerelease",
  ),
  (
    "prerelease-auto-kept-when-none-else-exists", "1.0|>=1.0|auto|3.11|1.1b1", "1.1b1|",
  ),
  ("prerelease-any-keeps-them", "1.0|>=1.0|any|3.11|1.1b1;1.1", "1.1b1,1.1|"),
  (
    "prerelease-none-drops-them", "1.0|<2.0|none|3.11|1.1b1;1.1;1.2rc1;1.2", "1.1,1.2|1.1b1=prerelease;1.2rc1=prerelease",
  ),
  (
    "prerelease-excluded-by-the-range", "1.0|<2.0|any|3.11|2.0b1;1.9", "1.9|2.0b1=out-of-range",
  ),
  ("dev-release-under-auto", "1.0||auto|3.11|1.1.dev1;1.0.1", "1.0.1,1.1.dev1|"),
  (
    "post-release-is-not-a-prerelease", "1.0|>=1.0|none|3.11|1.0.post1;1.0.1", "1.0.post1,1.0.1|",
  ),
  (
    "prerelease-only-and-none-mode", "1.0||none|3.11|1.1b1;1.2rc1", "1.1b1,1.2rc1|",
  ),
  (
    "range-mentions-a-prerelease-so-auto-admits", "1.0|>=1.1b1|auto|3.11|1.1b1;1.1",
    "1.1b1,1.1|",
  ),
  (
    "requires-python-admits-the-target", "1.0||auto|3.11|1.1@>=3.8;1.2@>=3.8", "1.1,1.2|",
  ),
  (
    "requires-python-excludes-the-target", "1.0||auto|3.11|1.1@>=3.12;1.2@<3.11",
    "|1.1=requires-python;1.2=requires-python",
  ),
  (
    "requires-python-missing-means-any", "1.0||auto|3.11|1.1;1.2@>=3.8", "1.1,1.2|",
  ),
  (
    "requires-python-with-a-window", "1.0||auto|3.11|1.1@>=3.8,<4;1.2@>=3.11,<3.12",
    "1.1,1.2|",
  ),
  (
    "requires-python-equal-boundary-is-admitted", "1.0||auto|3.11|1.1@>=3.11", "1.1|",
  ),
  (
    "requires-python-prerelease-target", "1.0||auto|3.12.0rc1|1.1@>=3.12", "|1.1=requires-python",
  ),
  (
    "requires-python-on-an-old-interpreter", "1.0||auto|3.7|1.1@>=3.6;1.2@>=3.8",
    "1.1|1.2=requires-python",
  ),
  (
    "unreadable-requires-python-is-ignored", "1.0||auto|3.11|1.1@not-a-specifier",
    "1.1|",
  ),
  (
    "unparsable-candidate", "1.0||auto|3.11|1.1;not-a-version;1.2", "1.1,1.2|not-a-version=unparsable",
  ),
  (
    "rejected-candidates-keep-input-order", "1.5|>=1.5,<2.0|auto|3.11|1.4;2.5;1.6;1.5",
    "1.6|1.4=downgrade;1.5=same;2.5=out-of-range",
  ),
  (
    "every-reason-at-once", "1.5|>=1.5,<2.0|auto|3.11|nope;1.4;2.5;1.6@>=3.12;1.7",
    "1.7|nope=unparsable;1.4=downgrade;2.5=out-of-range;1.6=requires-python",
  ),
  (
    "reason-order-prefers-the-earlier-rule", "1.5|>=1.5|auto|3.11|1.4@>=3.12;2.0@>=3.12",
    "|1.4=downgrade;2.0=requires-python",
  ),
  (
    "unparsable-candidate-that-is-also-old", "1.5||auto|3.11|nope;1.4", "|nope=unparsable;1.4=downgrade",
  ),
  (
    "unparsable-current", "not-a-version||auto|3.11|1.1;1.2", "!UNPARSABLE_CURRENT",
  ),
  ("bad-target-range", "1.0|not-a-specifier|auto|3.11|1.1;1.2", "!BAD_TARGET"),
  ("empty-current-version", "||auto|3.11|1.0;2.0", "!UNPARSABLE_CURRENT"),
  (
    "compatible-release-form", "1.0|~=1.4.2|auto|3.11|1.4.2;1.4.9;1.5;1.4.1", "1.4.2,1.4.9|1.5=out-of-range;1.4.1=out-of-range",
  ),
  (
    "exclusion-form", "1.0|>=1.0,!=1.2|auto|3.11|1.1;1.2;1.3", "1.1,1.3|1.2=out-of-range",
  ),
  (
    "wildcard-form", "1.0|==1.4.*|auto|3.11|1.3.9;1.4;1.4.9;1.5", "1.4,1.4.9|1.3.9=out-of-range;1.5=out-of-range",
  ),
  (
    "arbitrary-equality-form", "1.0|===1.5|auto|3.11|1.5;1.5.0;1.6", "1.5|1.5.0=out-of-range;1.6=out-of-range",
  ),
  (
    "two-sided-window", "1.0|>=1.0,<1.3|auto|3.11|1.2.9;1.3;2.0", "1.2.9|1.3=out-of-range;2.0=out-of-range",
  ),
  (
    "realistic-flask-style-window", "2.3.0|>=2.3,<3.0|auto|3.11|2.3.0;2.3.1;2.3.2;2.3.3;3.0.0;3.1.0;2.4.0rc1;2.4.0;2.2.5;2.5.0@>=3.12",
    "2.3.1,2.3.2,2.3.3,2.4.0|2.3.0=same;2.2.5=downgrade;3.0.0=out-of-range;3.1.0=out-of-range;2.4.0rc1=prerelease;2.5.0=requires-python",
  ),
  (
    "realistic-mixed-with-everything", "1.26.0|>=1.26,<2.0|auto|3.11|1.26.0;1.26.1;1.26.2;1.26.3;1.26.4;1.27.0rc1;1.27.0;2.0.0;1.25.2;bad;1.28.0@>=3.13",
    "1.26.1,1.26.2,1.26.3,1.26.4,1.27.0|1.26.0=same;1.25.2=downgrade;bad=unparsable;1.27.0rc1=prerelease;2.0.0=out-of-range;1.28.0=requires-python",
  ),
  (
    "realistic-prerelease-heavy", "0.9.0|>=0.9|auto|3.10|0.9.0;1.0.0a1;1.0.0b1;1.0.0rc1;1.0.0;1.1.0.dev1;1.1.0;2.0.0",
    "1.0.0,1.1.0,2.0.0|0.9.0=same;1.0.0a1=prerelease;1.0.0b1=prerelease;1.0.0rc1=prerelease;1.1.0.dev1=prerelease",
  ),
]

///|
/// Case names whose inputs cannot be decided at all, so both sides report
/// a stable code instead of a shortlist.
pub let upgrade_fatal_cases : Array[String] = [
  "unparsable-current", "bad-target-range", "empty-current-version",
]
