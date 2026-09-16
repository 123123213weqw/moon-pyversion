#!/usr/bin/env python3
"""Check that the differential harness actually detects regressions.

A green differential run only means something if the comparison can fail. This
script deliberately breaks the library in ways a real bug would look like,
re-runs the corpus, and asserts that `tools/diff_packaging.py` reports
mismatches. A mutation that stays green means the corpus does not cover that
behaviour, which is a gap in the experiment rather than a pass.

Each mutation is applied to a single source file, which is restored afterwards
even if the run fails.

Usage::

    python -B tools/mutation_probe.py
    python -B tools/mutation_probe.py --oracle /tmp/venv/bin/python --target js
    python -B tools/mutation_probe.py --list

Exit status: 0 = every mutation was detected, 1 = at least one stayed green,
2 = environment error.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Each mutation must be detectable by the corpus; `covers` names the behaviour
# the corpus is supposed to exercise.
MUTATIONS = [
    {
        "name": "name-normalization-drops-trailing-separator",
        "file": "utils.mbt",
        "old": """  if pending_separator {
    out.push('-')
  }
  String::from_array(out)
}""",
        "new": """  String::from_array(out)
}""",
        "covers": "canonicalize_name keeps leading and trailing separators",
    },
    {
        "name": "tag-order-uses-default-string-compare",
        "file": "utils.mbt",
        "old": "  out.sort_by(fn(a, b) { String::lexical_compare(a, b) })",
        "new": "  out.sort()",
        "covers": "wheel tags are ordered by code point, not by length",
    },
    {
        "name": "wheel-tag-case-not-normalized",
        "file": "utils.mbt",
        # `packaging`'s `Tag` lowercases the interpreter, ABI and platform, so
        # `CP312-CP312-Manylinux_2_17_X86_64` and the lowercase spelling are the
        # same tag. Keeping the caller's case is what this library did until the
        # tag corpus spelled one of them in upper case; the curated wheel list
        # carries five such filenames now.
        "old": "      parts.push(text.to_lower())",
        "new": "      parts.push(text)",
        "covers": "tag components are lowercased, the way the reference Tag is",
    },
    {
        "name": "tag-threading-detection-ignored",
        "file": "tags.mbt",
        # A free-threaded ABI is spelled with a `t` (`cp313t`), and it swaps the
        # stable ABI for `abi3t`. Never seeing the `t` puts `abi3` back, which is
        # exactly what those wheels cannot use.
        "old": "    if chars[j] == 't' {",
        "new": "    if false {",
        "covers": "a free-threaded ABI selects abi3t rather than abi3",
    },
    {
        "name": "tag-platform-list-not-validated",
        "file": "tags.mbt",
        # `platforms or platform_tags()`: an empty list means "probe the host" in
        # the reference and "no platforms" to a caller. Dropping the refusal makes
        # the three declared divergences stop being divergences.
        "old": """  if platforms.length() == 0 {
    // `platforms or platform_tags()`: an empty list means "probe the host"
    // there, and an empty tag list here. Refusing is the honest reading.
    raise VersionError::InvalidTag("TAG_PLATFORMS_REQUIRED", 0)
  }
""",
        "new": "",
        "covers": "an empty platform list is refused instead of answered",
    },
    {
        "name": "tag-case-not-lowered",
        "file": "tags.mbt",
        # `Tag` lowercases all three components, so `CP310-CP310-ANY` and the
        # lowercase spelling are the same tag.
        "old": "  \"\\{interpreter.to_lower()}-\\{abi.to_lower()}-\\{platform.to_lower()}\"",
        "new": "  \"\\{interpreter}-\\{abi}-\\{platform}\"",
        "covers": "generated tags are lowercased, the way the reference Tag is",
    },
    {
        "name": "tag-stable-abi-tail-not-generated",
        "file": "tags.mbt",
        # Older `abi3` wheels stay usable, so the stable ABI is replayed for every
        # earlier minor version down to cp32.
        "old": "  if use_abi3 || use_abi3t {",
        "new": "  if false {",
        "covers": "the abi3 tail is generated down to cp32",
    },
    {
        "name": "version-key-keeps-trailing-zeros",
        "file": "utils.mbt",
        "old": "        Version::to_string({ ..v, release: trim_release(v.release), })",
        "new": "        Version::to_string(v)",
        "covers": "canonicalize_version strips trailing release zeros",
    },
    {
        "name": "wheel-name-underscores-not-normalized",
        "file": "utils.mbt",
        "old": "  let name = canonicalize_name(name_part)",
        "new": "  let name = name_part.to_lower()",
        "covers": "wheel project names are canonicalized after unescaping",
    },
    {
        "name": "sdist-splits-on-first-dash",
        "file": "utils.mbt",
        "old": """  let mut cut = -1
  for i = chars.length() - 1; i >= 0; i = i - 1 {""",
        "new": """  let mut cut = -1
  for i = 0; i < chars.length(); i = i + 1 {""",
        "covers": "sdist names split on the last dash",
    },
    {
        "name": "local-segments-compared-by-length",
        "file": "version.mbt",
        "old": "      String::lexical_compare(l.text, r.text)",
        "new": "      l.text.compare(r.text)",
        "covers": "textual local segments order lexically",
    },
    {
        # The comparison canonicalizes the left operand too, but the left
        # operand of a set-valued clause is a literal that the parser has
        # already normalized, so removing that call alone cannot be observed.
        # What is observable is the environment half: `packaging` rewrites the
        # values it is handed, and the `oddnames` corpus environment spells its
        # extra and its set members the way a `pyproject.toml` may spell them.
        "name": "marker-extra-environment-not-normalized",
        "file": "markers.mbt",
        "old": """  match MarkerVar::parse(key) {
    Some(Extra) => self.values[key] = canonicalize_name(value)
    _ => self.values[key] = value
  }""",
        "new": """  ignore(MarkerVar::parse(key))
  self.values[key] = value""",
        "covers": "PEP 685: the environment's extra name is normalized too",
    },
    {
        "name": "marker-set-members-not-normalized",
        "file": "markers.mbt",
        "old": """  let names : Array[String] = []
  for name in value {
    names.push(canonicalize_name(name))
  }
  self.names[key] = names""",
        "new": """  self.names[key] = value""",
        "covers": "PEP 685/735: set-valued environment members are normalized too",
    },
    {
        "name": "marker-in-operand-swapped",
        "file": "markers.mbt",
        "old": """        In => text.contains(lhs)
        NotIn => !text.contains(lhs)""",
        "new": """        In => lhs.contains(text)
        NotIn => !lhs.contains(text)""",
        "covers": "`lhs in rhs` asks whether lhs occurs inside rhs",
    },
    {
        "name": "marker-vocabulary-misses-extras",
        "file": "markers.mbt",
        "old": """    "os_name", "os.name", "extras", "extra",""",
        "new": """    "os_name", "os.name", "extra",""",
        "covers": "the marker vocabulary is closed and complete",
    },
    {
        "name": "requirement-marker-not-validated",
        "file": "requirements.mbt",
        "old": "  validate_marker_text(text)",
        "new": "  ignore(text)",
        "covers": "a bad marker makes the whole requirement bad",
    },
    {
        "name": "license-lookup-case-sensitive",
        "file": "licenses.mbt",
        "old": """  for entry in table {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None""",
        "new": """  for entry in table {
    if entry.1 == key {
      return Some(entry.1)
    }
  }
  None""",
        "covers": "SPDX identifiers are matched case-insensitively",
    },
    {
        "name": "toml-inline-table-allows-newline",
        "file": "toml.mbt",
        "old": """  if self.peek() == 10 {
    self.fail("NEWLINE_IN_INLINE_TABLE")
  }""",
        "new": """  if self.peek() == 10 {
    self.advance()
    self.skip_ws()
  }""",
        "covers": "an inline table stays on one line in TOML 1.0, and the declared leniency still diverges",
    },
    {
        "name": "toml-multiline-skips-first-character",
        "file": "toml.mbt",
        "old": """  let mut text = self.parse_basic_string(true, true)""",
        "new": """  let mut text = self.parse_basic_string(true, false)""",
        "covers": "a multiline string keeps its first character",
    },
    {
        "name": "toml-integer-narrowed-to-32-bit",
        "file": "toml.mbt",
        "old": """  let value = @string.parse_int64(digits, base~) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }""",
        "new": """  let value = Int64::from_int(@string.parse_int(digits, base~) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }""",
        "covers": "TOML integers are 64-bit, not 32-bit",
    },
    {
        "name": "metadata-license-field-conflict-allowed",
        "file": "metadata.mbt",
        "old": """      match license {
        Some(_) => fail("LICENSE_EXPRESSION_CONFLICT", headers, "license")
        None => ()
      }""",
        "new": """      ignore(license)""",
        "covers": "PEP 639 forbids `License-Expression` next to the free text `License`",
    },
    {
        "name": "metadata-license-classifier-conflict-allowed",
        "file": "metadata.mbt",
        "old": """      for classifier in classifiers {
        if classifier.has_prefix("License ::") {
          fail("LICENSE_EXPRESSION_CONFLICT", headers, "classifier")
        }
      }""",
        "new": """      ignore(classifiers)""",
        "covers": "PEP 639 forbids `License-Expression` next to a `License ::` classifier",
    },
    {
        "name": "metadata-unknown-field-accepted",
        "file": "metadata.mbt",
        "old": """      None => raise InvalidMetadata("UNKNOWN_FIELD", header.offset)""",
        "new": """      None => 0""",
        "covers": "an unrecognized field is rejected",
    },
    {
        "name": "metadata-requires-dist-not-validated",
        "file": "metadata.mbt",
        "old": """    let requirement = Requirement::parse(value) catch {
      _ => fail("REQUIRES_DIST_INVALID", headers, "requires-dist")
    }
    match requirement.marker_text {
      Some(marker_text) =>
        if rank < EXTRA_SUPPORT_VERSION_RANK &&
          marker_mentions_extra(marker_text) {
          fail("EXTRA_MARKER_NOT_IN_METADATA_VERSION", headers, "requires-dist")
        }
      None => ()
    }""",
        "new": """    ignore(value)""",
        "covers": "every `Requires-Dist` value is parsed",
    },
    {
        # The corpus has a duplicate-name document, declared as a deliberate
        # divergence: the library rejects it while `json` keeps the last member. A
        # library that starts accepting it makes the two answers equal, which the
        # harness reports.
        "name": "index-duplicate-json-keys-allowed",
        "file": "index.mbt",
        "old": """      if members[j].0 == key {
        raise json_error("JSON_DUPLICATE_KEY", chars, i)
      }""",
        "new": """      if false {
        raise json_error("JSON_DUPLICATE_KEY", chars, i)
      }""",
        "covers": "a repeated JSON member name is rejected, unlike `json`",
    },
    {
        "name": "index-scan-sorts-by-default-string-order",
        "file": "index.mbt",
        "old": """  files.sort_by(fn(a, b) {
    let by_name = String::lexical_compare(a.name, b.name)""",
        "new": """  files.sort_by(fn(a, b) {
    let by_name = a.name.compare(b.name)""",
        "covers": "a directory scan orders names by code point, not by length",
    },
    {
        # The `Name` rule ends on a letter or a digit. The version of the code
        # before this rule was fixed also accepted a trailing `_` (which is a legal
        # character *inside* a name), so `Name: demo_` was accepted where
        # `packaging` rejects it. Putting the `|| c == '_'` back is exactly that
        # defect, and `metadata_cases/43_name_trailing_underscore.metadata` is the
        # document that has to notice.
        "name": "metadata-name-may-end-with-underscore",
        "file": "metadata.mbt",
        "old": """  if !is_ascii_alphanumeric(chars[n - 1]) {
    return false
  }""",
        "new": """  if !(is_ascii_alphanumeric(chars[n - 1]) || chars[n - 1] == '_') {
    return false
  }""",
        "covers": "a project name may not end in an underscore",
    },
    {
        # `Keywords` parts are stripped with Python's whitespace set, which is
        # wider than RFC 5322's WSP. Trimming with WSP alone leaves the vertical tab
        # and the form feed inside a part, and the `meta_values` records for
        # `metadata_cases/46_keywords_vertical_tab.metadata` are what notice: the
        # `meta` record beside them does *not*, because the reference implementation
        # normalises the same characters away when it re-reads the re-rendering.
        "name": "metadata-keywords-trimmed-with-wsp-only",
        "file": "metadata.mbt",
        "old": """  for part in text.split(",") {
    out.push(strip_python_space(part.to_owned()))
  }""",
        "new": """  for part in text.split(",") {
    out.push(trim_wsp(part.to_owned()))
  }""",
        "covers": "a Keywords part is stripped with Python's whitespace, not with WSP",
    },
    {
        # `created-by` is `Required? : yes`. Accepting its absence again is exactly
        # the leniency this milestone removed, and the corpus's
        # `CB_created_by_missing` / `CC_created_by_empty` cases are what notice.
        "name": "pylock-created-by-may-be-absent",
        "file": "pylock.mbt",
        "old": """  let created_by = match document.get("created-by") {
    Some(TString(value)) if !value.is_empty() => value
    Some(TString(_)) | None => raise pylock_error("CREATED_BY_REQUIRED", 0)
    Some(_) => raise pylock_error("CREATED_BY_TYPE", 0)
  }""",
        "new": """  let created_by = match document.get("created-by") {
    Some(TString(value)) => value
    Some(_) => raise pylock_error("CREATED_BY_TYPE", 0)
    None => ""
  }""",
        "covers": "the tool that wrote a lock file must be recorded",
    },
    {
        # `hashes` is `Required? : yes`, with "The table MUST contain at least one
        # entry"; the corpus's `CE_file_record_without_hashes` notices a reader that
        # treats the table as optional.
        "name": "pylock-file-record-without-hashes",
        "file": "pylock.mbt",
        "old": """    None => raise pylock_error("FILE_HASHES_REQUIRED", ordinal)""",
        "new": """    None => []""",
        "covers": "a file record must carry a non-empty hashes table",
    },
    {
        # "The date and time MUST be recorded in UTC." The corpus's
        # `CF_upload_time_not_utc` and `CG_upload_time_has_no_offset` are the two
        # shapes that have to be refused.
        "name": "pylock-upload-time-offset-not-checked",
        "file": "pylock.mbt",
        "old": """      if !is_utc_datetime(text) {
        raise pylock_error("FILE_UPLOAD_TIME_NOT_UTC", ordinal)
      }""",
        "new": """      if false {
        raise pylock_error("FILE_UPLOAD_TIME_NOT_UTC", ordinal)
      }""",
        "covers": "upload-time must be recorded in UTC",
    },
    {
        # "The version MUST NOT be included when ... a source tree is used". The
        # corpus's `CD_version_next_to_a_source_tree` notices a reader that keeps it.
        "name": "pylock-version-allowed-next-to-a-source-tree",
        "file": "pylock.mbt",
        "old": """      if source_tree {
        raise pylock_error("PACKAGE_VERSION_NOT_ALLOWED", ordinal)
      } else {""",
        "new": """      if false {
        raise pylock_error("PACKAGE_VERSION_NOT_ALLOWED", ordinal)
      } else {""",
        "covers": "a version may not be recorded next to a source tree",
    },
    {
        # `packages.version` is `Required? : no`; demanding it again is the old
        # divergence, and `24_file_list_entry_without_a_version` is what notices.
        "name": "pylock-version-demanded-on-a-file-list-entry",
        "file": "pylock.mbt",
        "old": """    Some(TString(_)) | None => None
    Some(_) => raise pylock_error("PACKAGE_VERSION_TYPE", ordinal)""",
        "new": """    Some(TString(_)) | None =>
      if has_member(table, "vcs") || has_member(table, "directory") {
        None
      } else {
        raise pylock_error("PACKAGE_VERSION_TYPE", ordinal)
      }
    Some(_) => raise pylock_error("PACKAGE_VERSION_TYPE", ordinal)""",
        "covers": "packages.version is optional unless a source tree is recorded",
    },
    {
        # PEP 751 records the major/minor version the file was written for, and
        # this reader rejects anything but 1.0 instead of warning. Accepting every
        # value would make the declared divergence disappear, which the harness
        # reports as a mismatch.
        "name": "pylock-accepts-any-lock-version",
        "file": "pylock.mbt",
        "old": """  if lock_version != PYLOCK_LOCK_VERSION {
    raise pylock_error("LOCK_VERSION_INVALID", 0)
  }""",
        "new": """  if false {
    raise pylock_error("LOCK_VERSION_INVALID", 0)
  }""",
        "covers": "a lock-version the reader does not implement is rejected, not warned about",
    },
    {
        "name": "pylock-ignores-source-exclusivity",
        "file": "pylock.mbt",
        "old": """  if direct > 1 || (direct > 0 && lists > 0) {
    raise pylock_error("PACKAGE_SOURCE_CONFLICT", ordinal)
  }""",
        "new": """  if false {
    raise pylock_error("PACKAGE_SOURCE_CONFLICT", ordinal)
  }""",
        "covers": "a package entry with two sources is rejected",
    },
    {
        "name": "pylock-file-order-puts-wheels-first",
        "file": "pylock.mbt",
        "old": """pub fn PylockPackage::all_files(self : PylockPackage) -> Array[PylockFile] {
  let out : Array[PylockFile] = []
  for file in self.files {
    out.push(file)
  }""",
        "new": """pub fn PylockPackage::all_files(self : PylockPackage) -> Array[PylockFile] {
  let out : Array[PylockFile] = []
  for file in self.wheels {
    out.push(file)
  }""",
        "covers": "the file records of a locked package come out in a fixed order",
    },
    {
        "name": "pylock-filename-ignores-the-url",
        "file": "pylock.mbt",
        "old": """        Some(url) => last_path_component(url)""",
        "new": """        Some(url) => None""",
        "covers": "a file record without `name` resolves its name from the URL",
    },
    {
        "name": "resolver-ignores-tags",
        "file": "index.mbt",
        "old": """  } else if file.kind is WheelFile && tag_priority(file, tags) == tags.length() {
    Some("tags")""",
        "new": """  } else if false {
    Some("tags")""",
        "covers": "a wheel for another platform is rejected",
    },
    {
        "name": "resolver-ignores-requires-python",
        "file": "index.mbt",
        "old": """  } else if !requires_python_ok(file, python) {
    Some("requires-python")""",
        "new": """  } else if false {
    Some("requires-python")""",
        "covers": "a file whose Requires-Python excludes the interpreter is rejected",
    },
    {
        "name": "resolver-prerelease-policy-ignored",
        "file": "index.mbt",
        "old": """  } else if !in_versions(allowed, file.version) {
    Some("prerelease")""",
        "new": """  } else if false {
    Some("prerelease")""",
        "covers": "the prerelease policy is applied to resolved candidates",
    },
    {
        "name": "prerelease-policy-always-allows",
        "file": "specifier.mbt",
        "old": """  let allow_pre = prereleases.unwrap_or(true)
  if version_is_prerelease(version) && !allow_pre {
    return false
  }""",
        "new": """  ignore(prereleases)""",
        "covers": "prereleases=Some(false) excludes prerelease candidates",
    },
]


def default_oracle() -> str:
    """The interpreter that holds the pinned oracle, when this machine has one.

    The corpus needs a TOML reference reader too, which only the pinned venv is
    guaranteed to have; falling back to `python3` would fail on Linux 3.10.
    """
    pinned = Path.home() / "oracle-versions" / "venv26.3" / "bin" / "python"
    if pinned.exists():
        return str(pinned)
    return sys.executable


def run(command: list[str], cwd: Path, env: dict) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, env=env, check=False)


def modified_sources(root: Path) -> list[str]:
    """The mutated source files that do not look untouched.

    Two checks, because either can be unavailable. `git status` is the real
    invariant -- the files this probe edits must be clean before it starts -- and
    it catches any modification, including one that leaves the mutation anchors
    intact. Without git (or outside a checkout), each mutation's own anchor is the
    next best thing: a leftover edit is usually the very edit that removes it.
    """
    files = sorted({mutation["file"] for mutation in MUTATIONS})
    git = shutil.which("git")
    if git is not None and (root / ".git").exists():
        result = subprocess.run(
            [git, "status", "--porcelain", "--", *files],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            print(
                f"warning: `git status` failed ({result.stderr.strip()}), "
                "falling back to the anchor check"
            )
        else:
            return [
                line[3:].strip()
                for line in result.stdout.splitlines()
                if line.strip()
            ]
    return [
        mutation["file"]
        for mutation in MUTATIONS
        if mutation["old"] not in (root / mutation["file"]).read_text(encoding="utf-8")
    ]


def leftover_injections(root: Path) -> list[str]:
    """Mutations whose *injected* form is already in the source.

    An interrupted run cannot restore the file it was editing: the process died
    between the write and the `finally`. The signature is the injected text being
    present while the anchor it replaced is gone, and it is only looked for in
    files that `modified_sources` already reports as touched. Both restrictions
    are needed:

    - without the file restriction the test is not specific enough. Several
      mutations inject an ordinary-looking snippet (one injects the empty string,
      which is a substring of everything), so a *clean* file can match by
      coincidence. A clean file cannot hold a leftover.
    - without the anchor restriction the test is not sensitive enough: some
      mutations replace a line with a shorter one, and the shorter spelling may
      appear elsewhere in the same file.
    """
    dirty = set(modified_sources(root))
    found: list[str] = []
    for mutation in MUTATIONS:
        if mutation["file"] not in dirty:
            continue
        text = (root / mutation["file"]).read_text(encoding="utf-8")
        if mutation["old"] in text:
            continue
        if mutation["new"] and mutation["new"] not in text:
            continue
        found.append(mutation["name"])
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", default="js", choices=["js", "wasm", "wasm-gc", "native"])
    parser.add_argument(
        "--oracle",
        default=None,
        help="python with packaging 26.3 installed (defaults to ~/oracle-versions/venv26.3)",
    )
    parser.add_argument("--pinned-oracle", default="26.3")
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help=(
            "run even though the files it mutates differ from the committed state; "
            "for development, where the difference is the work in progress. The "
            "strict default exists because a leftover injection from an interrupted "
            "run makes a 'detected' verdict meaningless"
        ),
    )
    parser.add_argument("--list", action="store_true", help="list mutations and exit")
    args = parser.parse_args(argv)

    if args.list:
        for mutation in MUTATIONS:
            print(f"{mutation['name']:<42} {mutation['file']:<14} {mutation['covers']}")
        return 0

    root = Path(__file__).resolve().parents[1]
    moon = shutil.which("moon") or str(Path.home() / ".moon" / "bin" / "moon")
    oracle = args.oracle or default_oracle()
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.moon' / 'bin'}{os.pathsep}{env.get('PATH', '')}"
    harness = root / "tools" / "diff_packaging.py"

    # Refuse to start on a tree that is already modified. The `finally` below
    # restores each file on the way out -- including on a normal failure -- but a
    # killed process gets no chance to run it, and a leftover mutation is worse
    # than no run at all: the next run would stack a second edit on top of it, and
    # a "detected" verdict could be reporting the leftovers rather than the
    # mutation under test. Restoring is the caller's job; saying so is this
    # function's.
    leftovers = leftover_injections(root)
    if leftovers and not args.allow_dirty:
        print("refusing to run: the sources already contain an injected mutation")
        for name in leftovers:
            print(f"  {name}")
        print("an interrupted run cannot restore what it rewrote; restore the file")
        print("(for example `git checkout -- <file>`) and run this again")
        return 2
    dirty = modified_sources(root)
    if dirty and not args.allow_dirty:
        print("refusing to run: the sources it would mutate are already modified")
        for name in dirty:
            print(f"  {name}")
        print("restore them (for example `git checkout -- <file>`) and run this again")
        print(
            "during development, when the edit is intentional, pass --allow-dirty "
            "and accept that a leftover injection can inflate a count"
        )
        return 2
    if dirty:
        print(
            "warning: running on a modified tree (--allow-dirty); every mutation's "
            "own anchor was checked, but a leftover injection from an interrupted "
            "run would still count as detection"
        )
        for name in dirty:
            print(f"  {name}")
        if leftovers:
            print("  already injected (count these with suspicion):")
            for name in leftovers:
                print(f"    {name}")
        print()

    undetected: list[str] = []
    print(f"{'mutation':<44} {'mismatches':>10}  verdict")
    with tempfile.TemporaryDirectory() as tmp:
        report_path = Path(tmp) / "report.json"
        corpus_path = Path(tmp) / "corpus.tsv"
        for mutation in MUTATIONS:
            target = root / mutation["file"]
            original = target.read_text(encoding="utf-8")
            if mutation["old"] not in original:
                print(
                    f"{mutation['name']:<44} {'-':>10}  SKIPPED (anchor not found: "
                    "`moon fmt` may have rewritten it)"
                )
                undetected.append(mutation["name"])
                continue
            target.write_text(original.replace(mutation["old"], mutation["new"], 1), encoding="utf-8")
            try:
                emitted = run(
                    [moon, "run", "examples/diff", "--target", args.target], root, env
                )
                corpus_path.write_bytes(emitted.stdout)
                if emitted.returncode != 0:
                    print(f"{mutation['name']:<44} {'-':>10}  BUILD FAILED (counts as detected)")
                    continue
                completed = run(
                    [
                        oracle, "-B", str(harness),
                        "--input", str(corpus_path),
                        "--target", args.target,
                        "--pinned-oracle", args.pinned_oracle,
                        "--json", str(report_path),
                    ],
                    root, env,
                )
                if not report_path.exists():
                    # The harness did not get far enough to write a report; that
                    # is a harness or protocol problem, not evidence of coverage.
                    print(f"{mutation['name']:<44} {'-':>10}  HARNESS ERROR")
                    sys.stderr.write(
                        completed.stderr.decode("utf-8", "replace")[-2000:]
                    )
                    sys.stderr.write(
                        completed.stdout.decode("utf-8", "replace")[-500:]
                    )
                    undetected.append(mutation["name"])
                    continue
                report = json.loads(report_path.read_text(encoding="utf-8"))
                detected = report["mismatch_total"]
            finally:
                target.write_text(original, encoding="utf-8")
            if detected > 0:
                print(f"{mutation['name']:<44} {detected:>10}  detected")
            else:
                print(f"{mutation['name']:<44} {detected:>10}  NOT DETECTED")
                undetected.append(mutation["name"])

    if undetected:
        print(f"\nFAILED: {len(undetected)} mutation(s) stayed green, so the corpus")
        print("does not cover: " + ", ".join(undetected))
        return 1
    print(f"\nOK: all {len(MUTATIONS)} mutations were detected by the corpus")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
