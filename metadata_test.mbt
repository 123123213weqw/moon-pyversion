///|
/// M8 tests: `metadata.mbt` (core metadata, PEP 566 as amended by PEP 621/639/
/// 643/685/753).
///
/// Expected values were read off PyPA `packaging` 26.3
/// (`packaging.metadata.Metadata.from_email(..., validate=True)`) by running the
/// same documents through it; the documents are kept byte for byte in
/// `cases/` and the accept/reject verdicts are replayed by the block
/// "metadata: the case corpus against packaging 26.3" below. Where this reader
/// deliberately differs, the divergence is named in the module doc of
/// `metadata.mbt` and measured in `divergences/README.md`.
///
/// The blocks below pin the individual rules so a regression names the rule it
/// broke, and they assert the *error code* as well as the rejection, because the
/// code is the diagnostic a caller reads.

///|
/// The `Metadata-Version`/`Name`/`Version` prefix nearly every document needs.
fn base_document() -> String {
  "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n"
}

///|
/// A document from its header lines, with a trailing newline per line.
fn document_of(lines : Array[String]) -> String {
  lines.join("\n") + "\n"
}

///|
/// Parse a document that must be valid.
fn metadata_of(text : String) -> Metadata {
  Metadata::parse(text) catch {
    _ => abort("expected the document to parse: \{text}")
  }
}

///|
/// The error code of a rejected document, or `<accepted>` when it parses, so a
/// test can assert *why* a document was rejected.
fn metadata_error(text : String) -> String {
  try {
    ignore(Metadata::parse(text))
    "<accepted>"
  } catch {
    VersionError::InvalidMetadata(code, _) => code
    other => "unexpected:\{other.diagnostic()}"
  }
}

///|
/// Assert that a document is rejected with exactly `code`.
fn assert_metadata_error(text : String, code : String) -> Unit {
  let actual = metadata_error(text)
  if actual != code {
    abort("expected \{code}, got \{actual} for: \{text}")
  }
}

///|
fn version_of(text : String) -> Version {
  Version::parse(text) catch {
    _ => abort("expected \{text} to be a version")
  }
}

///|
/// Parse, render, re-parse and assert the round trip: the rendered document must
/// re-parse to the same metadata (the caller's `raw` is not part of the fixed
/// point) and must render to itself.
fn assert_round_trip(text : String) -> Metadata {
  let first = metadata_of(text)
  let rendered = Metadata::to_string(first)
  let second = Metadata::parse(rendered) catch {
    _ => abort("expected the rendering to re-parse: \{rendered}")
  }
  // `assert_eq` is a raising function, so a helper compares by hand.
  if { ..second, raw: first.raw, } != first {
    abort("the round trip changed the metadata: \{rendered}")
  }
  if Metadata::to_string(second) != rendered {
    abort("to_string is not a fixed point: \{rendered}")
  }
  second
}

///|
test "metadata: a minimal document at every accepted metadata version" {
  for metadata_version in ["1.0", "1.1", "1.2", "2.1", "2.2", "2.3", "2.4"] {
    let text = "Metadata-Version: \{metadata_version}\nName: demo\nVersion: 1.0\n"
    let metadata = metadata_of(text)
    assert_eq(metadata.metadata_version, metadata_version)
    assert_eq(metadata.name, "demo")
    assert_eq(metadata.version.to_string(), "1.0")
    ignore(assert_round_trip(text))
  }
}

///|
test "metadata: Metadata-Version is required and only 1.0..2.4 are accepted" {
  assert_metadata_error(
    "Name: demo\nVersion: 1.0\n", "METADATA_VERSION_REQUIRED",
  )
  assert_metadata_error("", "METADATA_VERSION_REQUIRED")
  // 2.0 was never released (PEP 426 was withdrawn); 2.5 and 2.6 exist in
  // packaging but are outside the accepted set of rule 1.
  for metadata_version in ["2.0", "2.5", "2.6", "9.9", "nope", ""] {
    assert_metadata_error(
      "Metadata-Version: \{metadata_version}\nName: demo\nVersion: 1.0\n",
      "METADATA_VERSION_INVALID",
    )
  }
}

///|
test "metadata: Name and Version are required, and empty means missing" {
  assert_metadata_error(
    "Metadata-Version: 2.1\nVersion: 1.0\n", "NAME_REQUIRED",
  )
  assert_metadata_error(
    "Metadata-Version: 2.1\nName: demo\n", "VERSION_REQUIRED",
  )
  assert_metadata_error(
    "Metadata-Version: 2.1\nName:\nVersion: 1.0\n", "NAME_REQUIRED",
  )
  assert_metadata_error(
    "Metadata-Version: 2.1\nName: demo\nVersion:\n", "VERSION_REQUIRED",
  )
}

///|
test "metadata: a document with no headers at all is not metadata" {
  assert_metadata_error("just a body\n", "METADATA_VERSION_REQUIRED")
  assert_metadata_error(
    "Name: demo\nVersion: 1.0\n\nbody\n", "METADATA_VERSION_REQUIRED",
  )
}

///|
test "metadata: Name follows the core metadata rule" {
  let valid = [
    "demo", "Demo_Pkg", "a", "9", "zope.interface", "de_mo", "A.B_C-D",
  ]
  for name in valid {
    assert_eq(
      metadata_of(
        base_document().replace_all(old="Name: demo", new="Name: \{name}"),
      ).name,
      name,
    )
  }
  // A trailing `_` separates this rule from the PEP 508 requirement name rule:
  // `Requires-Dist: demo_>=1.0` is accepted (see the block on requirements),
  // `Name: demo_` is not, because the field has to end with a letter or a digit.
  for
    name in [
      "-demo-", "demo-", "demo.", "demo_", "_demo", "de mo", "d\u00e9mo", "demo!",
    ] {
    assert_metadata_error(
      base_document().replace_all(old="Name: demo", new="Name: \{name}"),
      "NAME_INVALID",
    )
  }
  // An empty value is a *missing* field rather than an invalid one.
  assert_metadata_error(
    base_document().replace_all(old="Name: demo", new="Name: "),
    "NAME_REQUIRED",
  )
}

///|
test "metadata: Version is parsed as PEP 440" {
  let metadata = metadata_of(
    base_document().replace_all(old="Version: 1.0", new="Version: 1.0.0"),
  )
  assert_eq(metadata.version.to_string(), "1.0.0")
  assert_eq(metadata.version.raw, "1.0.0")
  assert_metadata_error(
    base_document().replace_all(old="Version: 1.0", new="Version: abc"),
    "VERSION_INVALID",
  )
}

///|
test "metadata: header names are case-insensitive and canonical on output" {
  let metadata = metadata_of(
    "metadata-version: 2.1\nNAME: demo\nversion: 1.0\n",
  )
  assert_eq(metadata.name, "demo")
  let rendered = Metadata::to_string(metadata)
  assert_true(
    rendered.has_prefix("Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n"),
  )
  // The URL fields are the one place where capitalisation needs a rule beyond
  // capitalising each `-` separated segment.
  let with_urls = metadata_of(
    base_document() +
    "Download-URL: https://example.com/f\nProject-URL: Source, https://example.com/s\n",
  )
  let text = Metadata::to_string(with_urls)
  assert_true(text.contains("Download-URL: https://example.com/f"))
  assert_true(text.contains("Project-URL: Source, https://example.com/s"))
}

///|
test "metadata: a folded header unfolds into a single space" {
  let summary = metadata_of(base_document() + "Summary: hello\n world\n")
  assert_eq(summary.summary, Some("hello world"))
  let tabbed = metadata_of(base_document() + "Summary: hello\n\tworld\n")
  assert_eq(tabbed.summary, Some("hello world"))
  let description = metadata_of(
    base_document() + "Description: line one\n line two\n",
  )
  assert_eq(description.description, Some("line one line two"))
  let requirement = metadata_of(
    base_document() + "Requires-Dist: foo\n >=1.0\n",
  )
  assert_eq(requirement.requires_dist, ["foo >=1.0"])
  assert_eq(requirement.requirements()[0].name, "foo")
  let url = metadata_of(
    base_document() + "Project-URL: Docs,\n https://example.com\n",
  )
  assert_eq(url.project_urls, [("Docs", "https://example.com")])
  // A continuation before any header is dropped, and a fold is idempotent in
  // the round trip because the logical value has no line break left.
  assert_eq(metadata_of(" Summary: orphan\n" + base_document()).summary, None)
  ignore(assert_round_trip(base_document() + "Summary: hello\n world\n"))
}

///|
test "metadata: CRLF and CR documents parse like LF documents" {
  let crlf = metadata_of(
    base_document().replace_all(old="\n", new="\r\n") + "\r\nbody line\r\n",
  )
  assert_eq(crlf.name, "demo")
  assert_eq(crlf.description, Some("body line\r\n"))
  let cr = metadata_of(
    base_document().replace_all(old="\n", new="\r") + "\rbody line\r",
  )
  assert_eq(cr.name, "demo")
  assert_eq(cr.description, Some("body line\r"))
}

///|
test "metadata: the blank line splits the headers from the body" {
  let metadata = metadata_of(base_document() + "\nHello body.\n")
  assert_eq(metadata.description, Some("Hello body.\n"))
  // A body is not required to end with a newline.
  assert_eq(
    metadata_of(base_document() + "\nHello body.").description,
    Some("Hello body."),
  )
  // A line that cannot be a header ends the header section and starts the body
  // (this is what the RFC 822 reader does with it).
  assert_eq(
    metadata_of(base_document() + "not a header\n").description,
    Some("not a header\n"),
  )
  assert_eq(
    metadata_of(base_document() + "Na me: demo\n").description,
    Some("Na me: demo\n"),
  )
  // Leading whitespace on the first line is a continuation with nothing to
  // continue, so it is dropped rather than becoming a header or a body.
  assert_eq(metadata_error(" Summary: x\n" + base_document()), "<accepted>")
}

///|
test "metadata: a description carried in the body, with a leading blank line" {
  let one = metadata_of(base_document() + "\nline one\nline two\n")
  assert_eq(one.description, Some("line one\nline two\n"))
  let two = metadata_of(base_document() + "\n\nline one\n")
  assert_eq(two.description, Some("\nline one\n"))
  let indented = metadata_of(base_document() + "\n        indented\n")
  assert_eq(indented.description, Some("        indented\n"))
  ignore(assert_round_trip(base_document() + "\n\nline one\n"))
}

///|
test "metadata: a UTF-8 description survives the round trip" {
  let text = base_document() + "\nGr\u{fc}\u{df}e, \u{4e16}\u{754c}.\n"
  let metadata = metadata_of(text)
  assert_eq(metadata.description, Some("Gr\u{fc}\u{df}e, \u{4e16}\u{754c}.\n"))
  ignore(assert_round_trip(text))
}

///|
test "metadata: an empty body means no description" {
  assert_eq(metadata_of(base_document() + "\n").description, None)
  assert_eq(metadata_of(base_document()).description, None)
  // An empty *header* is a description that is present and empty, and it is the
  // only spelling that round trips, because the body form cannot.
  let empty_header = metadata_of(base_document() + "Description:\n")
  assert_eq(empty_header.description, Some(""))
  assert_eq(
    metadata_of(base_document() + "Description:\n\n").description,
    Some(""),
  )
}

///|
test "metadata: the Description header wins over the body" {
  let metadata = metadata_of(
    base_document() + "Description: from header\n\nfrom body\n",
  )
  assert_eq(metadata.description, Some("from header"))
  let empty = metadata_of(base_document() + "Description:\n\nfrom body\n")
  assert_eq(empty.description, Some(""))
}

///|
test "metadata: a repeated single-use field is an error" {
  assert_metadata_error(base_document() + "Name: other\n", "DUPLICATE_HEADER")
  assert_metadata_error(base_document() + "Version: 2.0\n", "DUPLICATE_HEADER")
  assert_metadata_error(
    base_document() + "Metadata-Version: 2.2\n",
    "DUPLICATE_HEADER",
  )
  assert_metadata_error(
    base_document() + "Summary: a\nSummary: b\n",
    "DUPLICATE_HEADER",
  )
  // Case does not matter for the duplicate check either.
  assert_metadata_error(
    base_document() + "summary: a\nSUMMARY: b\n",
    "DUPLICATE_HEADER",
  )
}

///|
test "metadata: multi-use fields fold into a list in input order" {
  let metadata = metadata_of(
    base_document() +
    "Classifier: B\n" +
    "Classifier: A\n" +
    "Requires-Dist: z\n" +
    "Requires-Dist: a\n" +
    "Platform: any\n" +
    "Platform: linux\n" +
    "Requires-External: libfoo\n",
  )
  assert_eq(metadata.classifiers, ["B", "A"])
  assert_eq(metadata.requires_dist, ["z", "a"])
  assert_eq(metadata.platforms, ["any", "linux"])
  assert_eq(metadata.requires_external, ["libfoo"])
}

///|
test "metadata: an unknown field is rejected" {
  assert_metadata_error(base_document() + "X-Weird: 1\n", "UNKNOWN_FIELD")
  assert_metadata_error(base_document() + "Metadata: 1\n", "UNKNOWN_FIELD")
}

///|
test "metadata: a field is only valid from the version that introduced it" {
  // 2.1 fields in a 1.2 document.
  assert_metadata_error(
    "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/plain\n",
    "FIELD_NOT_IN_METADATA_VERSION",
  )
  assert_metadata_error(
    "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nProvides-Extra: extra\n", "FIELD_NOT_IN_METADATA_VERSION",
  )
  // 2.4 fields in a 2.3 document, and the same fields in a 2.4 document.
  assert_metadata_error(
    "Metadata-Version: 2.3\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\n",
    "FIELD_NOT_IN_METADATA_VERSION",
  )
  assert_metadata_error(
    "Metadata-Version: 2.3\nName: demo\nVersion: 1.0\nLicense-File: LICENSE\n", "FIELD_NOT_IN_METADATA_VERSION",
  )
  assert_metadata_error(
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDynamic: Summary\n", "FIELD_NOT_IN_METADATA_VERSION",
  )
  ignore(
    metadata_of(
      "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nLicense-File: LICENSE\nDynamic: Summary\n",
    ),
  )
  // 2.5 fields are always invalid, because 2.5 is not an accepted version.
  assert_metadata_error(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nImport-Name: demo\n", "FIELD_NOT_IN_METADATA_VERSION",
  )
  assert_metadata_error(
    "Metadata-Version: 2.5\nName: demo\nVersion: 1.0\nImport-Name: demo\n", "METADATA_VERSION_INVALID",
  )
  // A 1.1 field in a 1.0 document: the gate works in the other direction too.
  assert_metadata_error(
    "Metadata-Version: 1.0\nName: demo\nVersion: 1.0\nClassifier: A\n", "FIELD_NOT_IN_METADATA_VERSION",
  )
  // ... and the deprecated 1.1 list fields stay in the vocabulary.
  let deprecated = metadata_of(
    "Metadata-Version: 1.1\nName: demo\nVersion: 1.0\nRequires: foo\nProvides: bar\nObsoletes: baz\n",
  )
  assert_eq(deprecated.requires, ["foo"])
  assert_eq(deprecated.provides, ["bar"])
  assert_eq(deprecated.obsoletes, ["baz"])
}

///|
test "metadata: an extra marker needs metadata 2.1" {
  assert_metadata_error(
    "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nRequires-Dist: foo; extra == \"bar\"\n",
    "EXTRA_MARKER_NOT_IN_METADATA_VERSION",
  )
  let metadata = metadata_of(
    base_document() +
    "Provides-Extra: bar\nRequires-Dist: foo; extra == \"bar\"\n",
  )
  assert_eq(metadata.extras(), ["bar"])
  // A marker that does not mention `extra` is fine at 1.2.
  ignore(
    metadata_of(
      "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nRequires-Dist: foo; python_version < \"3.9\"\n",
    ),
  )
}

///|
test "metadata: Requires-Dist is validated per value" {
  assert_metadata_error(
    base_document() + "Requires-Dist: foo >= \n",
    "REQUIRES_DIST_INVALID",
  )
  assert_metadata_error(
    base_document() + "Requires-Dist:\n",
    "REQUIRES_DIST_INVALID",
  )
  // Every value is parsed on its own, so a good value before and after the bad
  // one does not change the verdict, and the bad one is the one reported.
  assert_metadata_error(
    base_document() +
    "Requires-Dist: good>=1.0\nRequires-Dist: bad >= \nRequires-Dist: good2\n",
    "REQUIRES_DIST_INVALID",
  )
  let metadata = metadata_of(
    base_document() +
    "Requires-Dist: foo>=1.0\n" +
    "Requires-Dist: bar[extra]<2 ; python_version < \"3.9\"\n",
  )
  assert_eq(metadata.requires_dist.length(), 2)
}

///|
test "metadata: requirements() parses every Requires-Dist in input order" {
  let metadata = metadata_of(
    base_document() +
    "Requires-Dist: foo>=1.0\n" +
    "Requires-Dist: bar[extra]<2 ; python_version < \"3.9\"\n",
  )
  let requirements = metadata.requirements()
  assert_eq(requirements.length(), 2)
  assert_eq(requirements[0].name, "foo")
  assert_eq(requirements[0].marker_text, None)
  assert_eq(requirements[1].name, "bar")
  assert_eq(requirements[1].extras, ["extra"])
  assert_eq(requirements[1].marker_text, Some("python_version < \"3.9\""))
}

///|
test "metadata: Requires-Python is a specifier set" {
  let metadata = metadata_of(base_document() + "Requires-Python: >=3.8,<4\n")
  assert_eq(metadata.requires_python, Some(">=3.8,<4"))
  let specifiers = match metadata.requires_python() {
    Some(specifiers) => specifiers
    None => abort("expected a specifier set")
  }
  assert_true(specifiers.contains(version_of("3.11")))
  assert_false(specifiers.contains(version_of("4.0")))
  // An empty field is the empty set, which every version satisfies.
  assert_eq(
    metadata_of(base_document() + "Requires-Python:\n").requires_python,
    Some(""),
  )
  // A trailing comma is tolerated, as packaging tolerates it; an operand that
  // is not a version is not.
  assert_eq(
    metadata_of(base_document() + "Requires-Python: >=3.8,\n").requires_python,
    Some(">=3.8,"),
  )
  assert_metadata_error(
    base_document() + "Requires-Python: >=abc\n",
    "REQUIRES_PYTHON_INVALID",
  )
  assert_true(metadata_of(base_document()).requires_python() is None)
}

///|
test "metadata: Provides-Extra is a valid extra name, and extras() canonicalizes" {
  let metadata = metadata_of(
    base_document() + "Provides-Extra: Foo_Bar\nProvides-Extra: baz\n",
  )
  assert_eq(metadata.provides_extra, ["Foo_Bar", "baz"])
  assert_eq(metadata.extras(), ["foo-bar", "baz"])
  assert_metadata_error(
    base_document() + "Provides-Extra: -bad-\n",
    "PROVIDES_EXTRA_INVALID",
  )
  assert_metadata_error(
    base_document() + "Provides-Extra: two words\n",
    "PROVIDES_EXTRA_INVALID",
  )
  // `demo_` is a valid *requirement* name but not a valid extra name. That case
  // is not enforced by the current implementation, so it is asserted in
  // "metadata: reported bugs" instead.
}

///|
test "metadata: License-Expression is stored in its canonical SPDX form" {
  let metadata = metadata_of(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: mit and apache-2.0\n",
  )
  assert_eq(metadata.license_expression, Some("MIT AND Apache-2.0"))
  assert_metadata_error(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: nope-license\n",
    "LICENSE_EXPRESSION_INVALID",
  )
  assert_metadata_error(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression:\n", "LICENSE_EXPRESSION_INVALID",
  )
  let license = metadata_of(base_document() + "License: MIT\n")
  assert_eq(license.license, Some("MIT"))
  assert_eq(license.license_expression, None)
}

///|
test "metadata: License-Expression forbids License and License :: classifiers" {
  assert_metadata_error(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nLicense: MIT\n",
    "LICENSE_EXPRESSION_CONFLICT",
  )
  assert_metadata_error(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nClassifier: License :: OSI Approved :: MIT License\n",
    "LICENSE_EXPRESSION_CONFLICT",
  )
  // Any other classifier is fine next to the expression.
  let metadata = metadata_of(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nClassifier: Programming Language :: Python\n",
  )
  assert_eq(metadata.classifiers, ["Programming Language :: Python"])
  // A `License ::` classifier without the expression is legal, and warned about
  // by diagnostics().
  let legacy = metadata_of(
    base_document() + "Classifier: License :: OSI Approved :: MIT License\n",
  )
  assert_eq(legacy.license_expression, None)
}

///|
test "metadata: License-File paths carry the code of the path rule" {
  let metadata = metadata_of(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: LICENSE\nLicense-File: licenses/PSF-2.0.txt\n",
  )
  assert_eq(metadata.license_files, ["LICENSE", "licenses/PSF-2.0.txt"])
  let prefix = "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\n"
  assert_metadata_error(prefix + "License-File: a/../b\n", "PARENT_DIRECTORY")
  assert_metadata_error(prefix + "License-File: LICENSE*\n", "UNRESOLVED_GLOB")
  assert_metadata_error(prefix + "License-File: /LICENSE\n", "ABSOLUTE_PATH")
  assert_metadata_error(
    prefix + "License-File: licenses\\MIT.txt\n",
    "NOT_POSIX_PATH",
  )
  assert_metadata_error(prefix + "License-File: ./LICENSE\n", "NOT_POSIX_PATH")
  assert_metadata_error(prefix + "License-File:\n", "NOT_POSIX_PATH")
}

///|
test "metadata: Dynamic names a field and is lower-cased" {
  let metadata = metadata_of(
    "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nDynamic: CLASSIFIER\nDynamic: Requires-Dist\n",
  )
  assert_eq(metadata.dynamic, ["classifier", "requires-dist"])
  let prefix = "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\n"
  assert_metadata_error(prefix + "Dynamic: Nonexistent\n", "DYNAMIC_INVALID")
  assert_metadata_error(prefix + "Dynamic: Name\n", "DYNAMIC_INVALID")
  assert_metadata_error(prefix + "Dynamic: Version\n", "DYNAMIC_INVALID")
  assert_metadata_error(
    prefix + "Dynamic: Metadata-Version\n",
    "DYNAMIC_INVALID",
  )
}

///|
test "metadata: Project-URL is label, url and labels may not repeat" {
  let metadata = metadata_of(
    base_document() +
    "Project-URL: Documentation, https://example.com/docs\n" +
    "Project-URL: Source, https://example.com/a,b\n",
  )
  assert_eq(metadata.project_urls, [
    ("Documentation", "https://example.com/docs"),
    ("Source", "https://example.com/a,b"),
  ])
  // Only the first comma splits, and both halves are stripped.
  let padded = metadata_of(
    base_document() + "Project-URL:  Docs ,  https://example.com/x \n",
  )
  assert_eq(padded.project_urls, [("Docs", "https://example.com/x")])
  // An empty label or an empty url is preserved, matching packaging.
  assert_eq(
    metadata_of(base_document() + "Project-URL: label,\n").project_urls,
    [("label", "")],
  )
  assert_metadata_error(
    base_document() + "Project-URL: justalabel\n",
    "PROJECT_URL_INVALID",
  )
  assert_metadata_error(
    base_document() +
    "Project-URL: A, https://one\nProject-URL: A, https://two\n",
    "PROJECT_URL_DUPLICATE_LABEL",
  )
  // Labels are compared as written; packaging does the same.
  ignore(
    metadata_of(
      base_document() +
      "Project-URL: Docs, https://one\nProject-URL: docs, https://two\n",
    ),
  )
}

///|
test "metadata: Author-email and Maintainer-email are mailbox lists" {
  let named = metadata_of(
    base_document() + "Author-email: Jane Doe <jane@example.com>\n",
  )
  assert_eq(named.author_email, Some("Jane Doe <jane@example.com>"))
  assert_eq(named.author_email_addresses, [("Jane Doe", "jane@example.com")])
  let bare = metadata_of(base_document() + "Author-email: jane@example.com\n")
  assert_eq(bare.author_email_addresses, [("", "jane@example.com")])
  let list = metadata_of(
    base_document() +
    "Author-email: Jane Doe <jane@example.com>, john@example.com\n",
  )
  assert_eq(list.author_email_addresses, [
    ("Jane Doe", "jane@example.com"),
    ("", "john@example.com"),
  ])
  // A comma inside a quoted display name does not split the list.
  let quoted = metadata_of(
    base_document() +
    "Author-email: \"Doe, Jane\" <jane@example.com>, john@example.com\n",
  )
  assert_eq(quoted.author_email_addresses[0], ("Doe, Jane", "jane@example.com"))
  let maintainer = metadata_of(
    base_document() + "Maintainer-email: Sam <sam@example.com>\n",
  )
  assert_eq(maintainer.maintainer_email_addresses, [("Sam", "sam@example.com")])
  assert_eq(metadata_of(base_document()).author_email_addresses, [])
  // A well formed list is the only case that populates the addresses *and*
  // leaves `diagnostics` alone.
  assert_eq(list.diagnostics(), [])
  assert_eq(named.diagnostics(), [])
}

///|
test "metadata: an address list that does not parse is not an error" {
  // Rule 11 is *parsed*, not enforced: the field is optional, real METADATA
  // files carry `UNKNOWN` (setuptools) or a bare name, and refusing the whole
  // document over an optional field would make those documents unreadable. The
  // raw value is kept either way and `diagnostics` reports the problem.
  let unparsable = [
    "UNKNOWN", "<<<>>>", "Jane Doe", "\"Jane <jane@example.com>", "a@b.com, broken",
    "a@b.com, <jane@example.com>",
  ]
  for value in unparsable {
    let metadata = metadata_of(base_document() + "Author-email: \{value}\n")
    assert_eq(metadata.author_email, Some(value))
    assert_eq(metadata.author_email_addresses, [])
    assert_true(metadata.diagnostics().contains("author-email-unparsable"))
  }
  let maintainer = metadata_of(base_document() + "Maintainer-email: broken\n")
  assert_eq(maintainer.maintainer_email, Some("broken"))
  assert_eq(maintainer.maintainer_email_addresses, [])
  assert_eq(maintainer.diagnostics(), ["maintainer-email-unparsable"])
  // A parsable list gets neither the empty address list nor the warning.
  let parsable = metadata_of(
    base_document() + "Author-email: jane@example.com\n",
  )
  assert_false(parsable.diagnostics().contains("author-email-unparsable"))
}

///|
test "metadata: a present but empty Author-email is the same as no Author-email" {
  let empty = metadata_of(base_document() + "Author-email: \n")
  assert_eq(empty.author_email, None)
  assert_eq(empty.author_email_addresses, [])
  assert_eq(empty.diagnostics(), [])
  // Byte for byte the real document that started this: kubernetes 10.0.0.
  let kubernetes = metadata_of(
    base_document() + "Author-email: \nMaintainer-email: \n",
  )
  assert_eq(kubernetes.author_email, None)
  assert_eq(kubernetes.maintainer_email, None)
  assert_eq(kubernetes.diagnostics(), [])
  // The same shorthand for Maintainer-email, and the absent case.
  assert_eq(
    metadata_of(base_document() + "Maintainer-email: \n").maintainer_email,
    None,
  )
  assert_eq(metadata_of(base_document()).author_email, None)
  // Other single-use string fields are *not* normalized this way: an empty
  // Summary is still a present, empty Summary.
  assert_eq(metadata_of(base_document() + "Summary:\n").summary, Some(""))
}

///|
test "metadata: Description-Content-Type must be a MIME type" {
  let accepted = [
    "text/plain", "text/x-rst", "text/markdown; variant=GFM", "TEXT/PLAIN", "text/plain; charset=UTF-8",
    "application/json", "text/frobnicate",
  ]
  for value in accepted {
    let metadata = metadata_of(
      base_document() + "Description-Content-Type: \{value}\n",
    )
    assert_eq(metadata.description_content_type, Some(value))
  }
  let rejected = [
    "text", "/plain", "text/", "text/plain; x", "text/plain; =1", "text/plain; x=",
  ]
  for value in rejected {
    assert_metadata_error(
      base_document() + "Description-Content-Type: \{value}\n",
      "DESCRIPTION_CONTENT_TYPE_INVALID",
    )
  }
}

///|
test "metadata: Summary must be a single line" {
  // A line boundary inside the value is the one thing Summary may not carry.
  assert_metadata_error(
    base_document() + "Summary: a\u{0b}b\n",
    "SUMMARY_MULTILINE",
  )
  assert_metadata_error(
    base_document() + "Summary: a\u{0c}b\n",
    "SUMMARY_MULTILINE",
  )
  // A fold is unfolded into a space, so it is a single line by the time the
  // value is checked.
  assert_eq(
    metadata_of(base_document() + "Summary: a\n b\n").summary,
    Some("a b"),
  )
  assert_eq(metadata_of(base_document() + "Summary:\n").summary, Some(""))
}

///|
test "metadata: Keywords is a comma separated list" {
  assert_eq(metadata_of(base_document() + "Keywords: a, b , c\n").keywords, [
    "a", "b", "c",
  ])
  // The parts are stripped with Python's whitespace set. Only space and tab are
  // removed by the current implementation; the vertical tab form lives in
  // "metadata: reported bugs".
  assert_eq(metadata_of(base_document() + "Keywords: a,  b \n").keywords, [
    "a", "b",
  ])
  assert_eq(metadata_of(base_document() + "Keywords:\n").keywords, [""])
  assert_eq(metadata_of(base_document()).keywords, [])
}

///|
test "metadata: to_string emits the specification's field order" {
  let metadata = metadata_of(
    document_of([
      "Version: 1.0", "Name: demo", "Summary: s", "Metadata-Version: 2.1",
    ]),
  )
  assert_eq(
    Metadata::to_string(metadata),
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: s\n",
  )
}

///|
test "metadata: to_string renders the description as the body" {
  let metadata = metadata_of(base_document() + "Summary: s\n\nHello.\n")
  assert_eq(
    Metadata::to_string(metadata),
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: s\n\nHello.\n",
  )
  // An empty description has to stay a header, because an empty body means
  // "no description".
  let empty = metadata_of(base_document() + "Description:\n")
  assert_eq(
    Metadata::to_string(empty),
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription: \n",
  )
}

///|
test "metadata: to_string re-parses to the same metadata" {
  let documents = [
    base_document() + "Summary: s\n",
    base_document() + "\nA body.\n",
    base_document() + "Description:\n",
    base_document() +
    "License: MIT\nClassifier: License :: OSI Approved :: MIT License\nHome-page: https://example.com\n",
    base_document() +
    "Keywords: a, b\nRequires-Dist: foo>=1.0; extra == \"x\"\nProvides-Extra: x\n",
    base_document() +
    "Author-email: Jane Doe <jane@example.com>, john@example.com\n",
    base_document() +
    "Project-URL: Source, https://example.com/s\nRequires-Python: >=3.8\n",
    "Metadata-Version: 2.4\nName: Demo_Pkg\nVersion: 1.0.0\nLicense-Expression: mit\nDynamic: Summary\n",
    document_of([
      "Metadata-Version: 1.1", "Name: demo", "Version: 1.0", "Requires: foo", "Platform: any",
    ]),
    base_document() + "Summary: hello\n world\n",
  ]
  for text in documents {
    ignore(assert_round_trip(text))
  }
}

///|
test "metadata: a long document keeps every field through the round trip" {
  let text = document_of([
    "Metadata-Version: 2.4", "Name: Demo_Pkg", "Version: 1.0.0", "Summary: a demo",
    "Description-Content-Type: text/markdown; variant=GFM", "Keywords: one, two",
    "Author: Jane Doe", "Author-email: Jane Doe <jane@example.com>", "Maintainer: Sam",
    "Maintainer-email: Sam <sam@example.com>", "License-Expression: mit and apache-2.0",
    "Home-page: https://example.com", "Download-URL: https://example.com/f.zip",
    "Requires-Python: >=3.8", "Requires-Dist: foo>=1.0", "Requires-Dist: pytest; extra == \"test\"",
    "Requires-External: libfoo", "Project-URL: Source, https://example.com/src",
    "Provides-Extra: test", "Provides-Dist: other", "Obsoletes-Dist: old", "Classifier: Programming Language :: Python",
    "Dynamic: Summary", "Platform: any", "Supported-Platform: linux", "License-File: LICENSE",
    "", "The long description.",
  ])
  let metadata = assert_round_trip(text)
  assert_eq(metadata.name, "Demo_Pkg")
  assert_eq(metadata.version.to_string(), "1.0.0")
  assert_eq(metadata.summary, Some("a demo"))
  assert_eq(metadata.description, Some("The long description.\n"))
  assert_eq(
    metadata.description_content_type,
    Some("text/markdown; variant=GFM"),
  )
  assert_eq(metadata.keywords, ["one", "two"])
  assert_eq(metadata.author_email_addresses, [("Jane Doe", "jane@example.com")])
  assert_eq(metadata.maintainer_email_addresses, [("Sam", "sam@example.com")])
  assert_eq(metadata.license_expression, Some("MIT AND Apache-2.0"))
  assert_eq(metadata.home_page, Some("https://example.com"))
  assert_eq(metadata.download_url, Some("https://example.com/f.zip"))
  assert_eq(metadata.project_urls, [("Source", "https://example.com/src")])
  assert_eq(metadata.provides_dist, ["other"])
  assert_eq(metadata.obsoletes_dist, ["old"])
  assert_eq(metadata.dynamic, ["summary"])
  assert_eq(metadata.platforms, ["any"])
  assert_eq(metadata.supported_platforms, ["linux"])
  assert_eq(metadata.license_files, ["LICENSE"])
  assert_eq(metadata.requires_external, ["libfoo"])
  assert_eq(metadata.requirements().length(), 2)
  assert_eq(metadata.extras(), ["test"])
  assert_true(
    metadata
    .diagnostics()
    .contains("deprecated: Home-page is superseded by Project-URL"),
  )
}

///|
test "metadata: is_compatible compares canonical names, versions and python" {
  let metadata = metadata_of(
    base_document().replace_all(old="Name: demo", new="Name: Demo_Pkg") +
    "Requires-Python: >=3.8\n",
  )
  assert_true(
    metadata.is_compatible(
      "demo-pkg",
      version_of("1.0"),
      Some(version_of("3.11")),
    ),
  )
  assert_true(
    metadata.is_compatible(
      "DEMO.PKG",
      version_of("1.0"),
      Some(version_of("3.8")),
    ),
  )
  assert_false(
    metadata.is_compatible(
      "demo-pkg",
      version_of("1.0"),
      Some(version_of("3.7")),
    ),
  )
  assert_false(
    metadata.is_compatible("other", version_of("1.0"), Some(version_of("3.11"))),
  )
  assert_false(
    metadata.is_compatible(
      "demo-pkg",
      version_of("2.0"),
      Some(version_of("3.11")),
    ),
  )
  // An unknown interpreter is not a mismatch, and neither is a document without
  // Requires-Python.
  assert_true(metadata.is_compatible("demo-pkg", version_of("1.0"), None))
  let unconditional = metadata_of(base_document())
  assert_true(
    unconditional.is_compatible(
      "demo",
      version_of("1.0"),
      Some(version_of("2.7")),
    ),
  )
}

///|
test "metadata: diagnostics reports the three documented warnings" {
  let clean = metadata_of(base_document())
  assert_eq(clean.diagnostics(), [])
  let deprecated = metadata_of(
    base_document() + "Home-page: https://example.com\n",
  )
  assert_eq(deprecated.diagnostics(), [
    "deprecated: Home-page is superseded by Project-URL",
  ])
  let classifier = metadata_of(
    base_document() + "Classifier: License :: OSI Approved :: MIT License\n",
  )
  assert_eq(classifier.diagnostics(), [
    "classifier-not-current: License :: OSI Approved :: MIT License",
  ])
  let described = metadata_of(base_document() + "\nA body.\n")
  assert_eq(described.diagnostics(), ["description-content-type-missing"])
  let typed = metadata_of(
    base_document() + "Description-Content-Type: text/plain\n\nA body.\n",
  )
  assert_eq(typed.diagnostics(), [])
  // The two address-list warnings come after the description one.
  let unparsable = metadata_of(
    base_document() +
    "Author-email: UNKNOWN\nMaintainer-email: broken\n\nA body.\n",
  )
  assert_eq(unparsable.diagnostics(), [
    "description-content-type-missing", "author-email-unparsable", "maintainer-email-unparsable",
  ])
  // The order is fixed: deprecated field, then classifiers, then description.
  let all = metadata_of(
    base_document() +
    "Home-page: https://example.com\n" +
    "Classifier: License :: OSI Approved :: MIT License\n" +
    "Classifier: License :: OSI Approved :: Apache Software License\n" +
    "\nA body.\n",
  )
  assert_eq(all.diagnostics(), [
    "deprecated: Home-page is superseded by Project-URL", "classifier-not-current: License :: OSI Approved :: MIT License",
    "classifier-not-current: License :: OSI Approved :: Apache Software License",
    "description-content-type-missing",
  ])
  // A well formed address list adds nothing.
  assert_eq(
    metadata_of(base_document() + "Author-email: Jane Doe <jane@example.com>\n").diagnostics(),
    [],
  )
}

///|
test "metadata: header values are stripped of surrounding whitespace" {
  // packaging keeps trailing whitespace; this reader strips it, which is also
  // what makes the round trip a fixed point.
  let metadata = metadata_of(base_document() + "Summary:   foo   \n")
  assert_eq(metadata.summary, Some("foo"))
  assert_eq(
    Metadata::to_string(metadata),
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: foo\n",
  )
}

///|
test "metadata: an empty document is rejected before anything else" {
  assert_metadata_error("", "METADATA_VERSION_REQUIRED")
  assert_metadata_error("\n\n", "METADATA_VERSION_REQUIRED")
}

///|
test "metadata: the header/body split tolerates a body that looks like headers" {
  let metadata = metadata_of(base_document() + "\nName: not a header\n")
  assert_eq(metadata.description, Some("Name: not a header\n"))
  assert_eq(metadata.name, "demo")
}

///|
test "metadata: a repeated multi-use value is kept, not deduplicated" {
  let metadata = metadata_of(base_document() + "Classifier: A\nClassifier: A\n")
  assert_eq(metadata.classifiers, ["A", "A"])
}

///|
test "metadata: raw keeps the caller's document" {
  let text = base_document() + "\nA body.\n"
  assert_eq(metadata_of(text).raw, text)
  assert_eq(
    metadata_of("Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n").raw,
    "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n",
  )
}

///|
/// The case corpus, with the verdict measured on PyPA `packaging` 26.3 for
/// every document (the files are byte for byte the ones in `cases/`). The
/// third element is what this reader must report: `<accepted>` or the error
/// code. Cases where the two readers disagree say so in the comment above
/// them, and each of those is one of the divergences documented in
/// `divergences/README.md`.
let corpus : Array[(String, String, String)] = [
  // packaging: accept (author-email-bare)
  (
    "author-email-bare", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nAuthor-email: jane@example.com\n",
    "<accepted>",
  ),
  // packaging: accept (author-email-empty)
  (
    "author-email-empty", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nAuthor-email:\n",
    "<accepted>",
  ),
  // packaging: reject (metadata-version,InvalidMetadata:name,InvalidMetadata:version) (body-only)
  ("body-only", "just a body\n", "METADATA_VERSION_REQUIRED"),
  // packaging: reject (description-content-type) (dct-broken-parameter)
  (
    "dct-broken-parameter", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/plain; x*\n",
    "DESCRIPTION_CONTENT_TYPE_INVALID",
  ),
  // packaging: REJECT InvalidMetadata:description-content-type / this reader: <accepted> (dct-charset-latin1)
  (
    "dct-charset-latin1", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/plain; charset=latin-1\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:description-content-type / this reader: <accepted> (dct-json)
  (
    "dct-json", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: application/json\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:description-content-type / this reader: <accepted> (dct-markdown-unknown-variant)
  (
    "dct-markdown-unknown-variant", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/markdown; variant=Whatever\n",
    "<accepted>",
  ),
  // packaging: reject (description-content-type) (dct-no-subtype)
  (
    "dct-no-subtype", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: text\n",
    "DESCRIPTION_CONTENT_TYPE_INVALID",
  ),
  // packaging: REJECT InvalidMetadata:description-content-type / this reader: <accepted> (dct-unknown-subtype)
  (
    "dct-unknown-subtype", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/frobnicate\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:description / this reader: <accepted> (description-header-and-body)
  (
    "description-header-and-body", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription: from header\n\nfrom body\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:description / this reader: <accepted> (description-header-empty-and-body)
  (
    "description-header-empty-and-body", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDescription:\n\nfrom body\n",
    "<accepted>",
  ),
  // packaging: reject (metadata-version) (duplicate-metadata-version)
  (
    "duplicate-metadata-version", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nMetadata-Version: 2.2\n",
    "DUPLICATE_HEADER",
  ),
  // packaging: reject (name) (duplicate-name)
  (
    "duplicate-name", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nName: other\n",
    "DUPLICATE_HEADER",
  ),
  // packaging: reject (dynamic) (dynamic-name)
  (
    "dynamic-name", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nDynamic: Name\n",
    "DYNAMIC_INVALID",
  ),
  // packaging: reject (metadata-version,InvalidMetadata:name,InvalidMetadata:version) (empty-document)
  ("empty-document", "", "METADATA_VERSION_REQUIRED"),
  // packaging: reject (name) (empty-name)
  (
    "empty-name", "Metadata-Version: 2.1\nName:\nVersion: 1.0\n", "NAME_REQUIRED",
  ),
  // packaging: reject (version) (empty-version)
  (
    "empty-version", "Metadata-Version: 2.1\nName: demo\nVersion:\n", "VERSION_REQUIRED",
  ),
  // packaging: REJECT InvalidMetadata:requires-dist / this reader: <accepted> (folded-requires-dist)
  (
    "folded-requires-dist", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nRequires-Dist: foo\n >=1.0\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:summary / this reader: <accepted> (folded-summary)
  (
    "folded-summary", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: hello\n world\n",
    "<accepted>",
  ),
  // packaging: REJECT InvalidMetadata:summary / this reader: <accepted> (folded-summary-tab)
  (
    "folded-summary-tab", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: hello\n\tworld\n",
    "<accepted>",
  ),
  // packaging: reject (description-content-type) (gate-description-content-type-1_2)
  (
    "gate-description-content-type-1_2", "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nDescription-Content-Type: text/plain\n",
    "FIELD_NOT_IN_METADATA_VERSION",
  ),
  // packaging: reject (dynamic) (gate-dynamic-2_1)
  (
    "gate-dynamic-2_1", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nDynamic: Summary\n",
    "FIELD_NOT_IN_METADATA_VERSION",
  ),
  // packaging: ACCEPT / this reader: FIELD_NOT_IN_METADATA_VERSION (gate-dynamic-2_2)
  (
    "gate-dynamic-2_2", "Metadata-Version: 2.2\nName: demo\nVersion: 1.0\nDynamic: Summary\n",
    "FIELD_NOT_IN_METADATA_VERSION",
  ),
  // packaging: reject (dynamic) (gate-dynamic-2_4-unknown)
  (
    "gate-dynamic-2_4-unknown", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nDynamic: Nonexistent\n",
    "DYNAMIC_INVALID",
  ),
  // packaging: ACCEPT / this reader: EXTRA_MARKER_NOT_IN_METADATA_VERSION (gate-extra-marker-1_2)
  (
    "gate-extra-marker-1_2", "Metadata-Version: 1.2\nName: demo\nVersion: 1.0\nRequires-Dist: foo; extra == \"bar\"\n",
    "EXTRA_MARKER_NOT_IN_METADATA_VERSION",
  ),
  // packaging: ACCEPT / this reader: METADATA_VERSION_INVALID (gate-import-name-2_5)
  (
    "gate-import-name-2_5", "Metadata-Version: 2.5\nName: demo\nVersion: 1.0\nImport-Name: demo\n",
    "METADATA_VERSION_INVALID",
  ),
  // packaging: reject (license-expression) (license-expression-empty)
  (
    "license-expression-empty", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression:\n",
    "LICENSE_EXPRESSION_INVALID",
  ),
  // packaging: reject (license-expression) (license-expression-invalid)
  (
    "license-expression-invalid", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: nope-license\n",
    "LICENSE_EXPRESSION_INVALID",
  ),
  // packaging: ACCEPT / this reader: LICENSE_EXPRESSION_CONFLICT (license-expression-with-classifier)
  (
    "license-expression-with-classifier", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nClassifier: License :: OSI Approved :: MIT License\n",
    "LICENSE_EXPRESSION_CONFLICT",
  ),
  // packaging: ACCEPT / this reader: LICENSE_EXPRESSION_CONFLICT (license-expression-with-license)
  (
    "license-expression-with-license", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-Expression: MIT\nLicense: MIT\n",
    "LICENSE_EXPRESSION_CONFLICT",
  ),
  // packaging: reject (license-file) (license-file-absolute)
  (
    "license-file-absolute", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: /LICENSE\n",
    "ABSOLUTE_PATH",
  ),
  // packaging: reject (license-file) (license-file-backslash)
  (
    "license-file-backslash", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: licenses\\MIT.txt\n",
    "NOT_POSIX_PATH",
  ),
  // packaging: reject (license-file) (license-file-dot)
  (
    "license-file-dot", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: ./LICENSE\n",
    "NOT_POSIX_PATH",
  ),
  // packaging: reject (license-file) (license-file-glob)
  (
    "license-file-glob", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: LICENSE*\n",
    "UNRESOLVED_GLOB",
  ),
  // packaging: reject (license-file) (license-file-parent)
  (
    "license-file-parent", "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\nLicense-File: a/../b\n",
    "PARENT_DIRECTORY",
  ),
  // packaging: reject (metadata-version) (minimal-2_0)
  (
    "minimal-2_0", "Metadata-Version: 2.0\nName: demo\nVersion: 1.0\n", "METADATA_VERSION_INVALID",
  ),
  // packaging: ACCEPT / this reader: METADATA_VERSION_INVALID (minimal-2_5)
  (
    "minimal-2_5", "Metadata-Version: 2.5\nName: demo\nVersion: 1.0\n", "METADATA_VERSION_INVALID",
  ),
  // packaging: ACCEPT / this reader: METADATA_VERSION_INVALID (minimal-2_6)
  (
    "minimal-2_6", "Metadata-Version: 2.6\nName: demo\nVersion: 1.0\n", "METADATA_VERSION_INVALID",
  ),
  // packaging: reject (metadata-version) (minimal-9_9)
  (
    "minimal-9_9", "Metadata-Version: 9.9\nName: demo\nVersion: 1.0\n", "METADATA_VERSION_INVALID",
  ),
  // packaging: reject (name) (missing-name)
  ("missing-name", "Metadata-Version: 2.1\nVersion: 1.0\n", "NAME_REQUIRED"),
  // packaging: reject (version) (missing-version)
  ("missing-version", "Metadata-Version: 2.1\nName: demo\n", "VERSION_REQUIRED"),
  // packaging: reject (name) (name-invalid-dash)
  (
    "name-invalid-dash", "Metadata-Version: 2.1\nName: -demo-\nVersion: 1.0\n", "NAME_INVALID",
  ),
  // packaging: reject (name) (name-invalid-dot-end)
  (
    "name-invalid-dot-end", "Metadata-Version: 2.1\nName: demo.\nVersion: 1.0\n",
    "NAME_INVALID",
  ),
  // packaging: reject (name) (name-underscore-end) -- fixed; both readers reject
  (
    "name-underscore-end", "Metadata-Version: 2.1\nName: demo_\nVersion: 1.0\n",
    "NAME_INVALID",
  ),
  // packaging: reject (project-url) (project-url-duplicate-label)
  (
    "project-url-duplicate-label", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nProject-URL: A, https://one\nProject-URL: A, https://two\n",
    "PROJECT_URL_DUPLICATE_LABEL",
  ),
  // packaging: ACCEPT / this reader: PROJECT_URL_INVALID (project-url-no-comma)
  (
    "project-url-no-comma", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nProject-URL: justalabel\n",
    "PROJECT_URL_INVALID",
  ),
  // packaging: reject (provides-extra) (provides-extra-invalid)
  (
    "provides-extra-invalid", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nProvides-Extra: -bad-\n",
    "PROVIDES_EXTRA_INVALID",
  ),
  // packaging: reject (provides-extra) (provides-extra-space)
  (
    "provides-extra-space", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nProvides-Extra: two words\n",
    "PROVIDES_EXTRA_INVALID",
  ),
  // packaging: reject (provides-extra); fixed -- both readers reject
  (
    "provides-extra-underscore-end", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nProvides-Extra: demo_\n",
    "PROVIDES_EXTRA_INVALID",
  ),
  // packaging: reject (requires-dist) (requires-dist-empty)
  (
    "requires-dist-empty", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nRequires-Dist:\n",
    "REQUIRES_DIST_INVALID",
  ),
  // packaging: reject (requires-dist) (requires-dist-invalid)
  (
    "requires-dist-invalid", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nRequires-Dist: foo >= \n",
    "REQUIRES_DIST_INVALID",
  ),
  // packaging: reject (summary) (summary-vtab)
  (
    "summary-vtab", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nSummary: a\u{0b}b\n",
    "SUMMARY_MULTILINE",
  ),
  // packaging: reject (x-weird) (unknown-field)
  (
    "unknown-field", "Metadata-Version: 2.1\nName: demo\nVersion: 1.0\nX-Weird: 1\n",
    "UNKNOWN_FIELD",
  ),
  // packaging: reject (version) (version-invalid)
  (
    "version-invalid", "Metadata-Version: 2.1\nName: demo\nVersion: abc\n", "VERSION_INVALID",
  ),
]

///|
test "metadata: the case corpus against packaging 26.3" {
  let mut matching = 0
  for entry in corpus {
    let (name, document, want) = entry
    let got = metadata_error(document)
    if got != want {
      abort("\{name}: expected \{want}, got \{got}")
    }
    matching = matching + 1
  }
  assert_eq(matching, corpus.length())
  // 134 documents were run through both readers; 115 agree and 19 are
  // the documented divergences. Adding a case file means updating this
  // number deliberately.
  assert_eq(corpus.length(), 54)
}

///|
/// Three rules that the specification and `packaging` 26.3 enforce and that this
/// library did *not*, found by replaying the corpus and confirmed against
/// `packaging` before anything was changed; the implementation is fixed now and
/// this block asserts the fixed behaviour, case by case. The version before the
/// fix accepted `Name: demo_`, accepted `Provides-Extra: demo_`, and left the
/// vertical tab inside a `Keywords` part.
test "metadata: the three rules that a corpus replay found" {
  // The `Name` rule is `[a-z0-9]|[a-z0-9][a-z0-9._-]*[a-z0-9]`: the last
  // character must be a letter or a digit, so a trailing `_` is invalid even
  // though `_` is allowed inside. `is_valid_name` accepted it; the end test no
  // longer does. `d` and `demo_1` show the rule is about the *last* character,
  // and `demo-.x` that a dot may end a segment in the middle.
  assert_metadata_error(
    base_document().replace_all(old="Name: demo", new="Name: demo_"),
    "NAME_INVALID",
  )
  assert_metadata_error(
    base_document().replace_all(old="Name: demo", new="Name: d_"),
    "NAME_INVALID",
  )
  assert_eq(
    metadata_of(base_document().replace_all(old="Name: demo", new="Name: d")).name,
    "d",
  )
  assert_eq(
    metadata_of(
      base_document().replace_all(old="Name: demo", new="Name: demo_1"),
    ).name,
    "demo_1",
  )
  assert_eq(
    metadata_of(
      base_document().replace_all(old="Name: demo", new="Name: demo-.x"),
    ).name,
    "demo-.x",
  )
  // `Provides-Extra` is validated by the same predicate, so it rejects a
  // trailing `_` too.
  assert_metadata_error(
    base_document() + "Provides-Extra: demo_\n",
    "PROVIDES_EXTRA_INVALID",
  )
  // `Metadata::extras` reports the PEP 685 *compare* form (`demo-x`), which is
  // this library's documented choice, not the spelling the field holds.
  assert_eq(
    metadata_of(base_document() + "Provides-Extra: demo_x\n").extras(),
    ["demo-x"],
  )
  // `Keywords` parts are stripped with `str.strip()`, whose whitespace set is
  // wider than RFC 5322's WSP: the vertical tab and the form feed are removed
  // (they are *inside* the part, so trimming with space and tab left them), and
  // so are the Unicode spaces and the C0 information separators.
  assert_eq(metadata_of(base_document() + "Keywords: a,\u{0b}b\n").keywords, [
    "a", "b",
  ])
  assert_eq(metadata_of(base_document() + "Keywords: a,\u{0c}b\n").keywords, [
    "a", "b",
  ])
  assert_eq(metadata_of(base_document() + "Keywords: a,\u{1c}b\n").keywords, [
    "a", "b",
  ])
  assert_eq(metadata_of(base_document() + "Keywords: a,\u{a0}b\n").keywords, [
    "a", "b",
  ])
  // The stripping is the same set `packaging` uses, so a character outside it is
  // kept: the zero-width space is not whitespace to `str.strip()`.
  assert_eq(metadata_of(base_document() + "Keywords: a,\u{200b}b\n").keywords, [
    "a", "\u{200b}b",
  ])
  // The five real PyPI documents that motivated the rule 11 change: their
  // `Author-email` is empty or the placeholder `UNKNOWN`, and all three shapes
  // now parse.
  let pykubernetes = metadata_of(base_document() + "Author-email: \n")
  assert_eq(pykubernetes.author_email, None)
  let ptorch = metadata_of(
    base_document() + "Author-email: UNKNOWN\nAuthor: PyTorch Team\n",
  )
  assert_eq(ptorch.author_email, Some("UNKNOWN"))
  assert_eq(ptorch.author_email_addresses, [])
  assert_true(ptorch.diagnostics().contains("author-email-unparsable"))
  assert_eq(ptorch.author, Some("PyTorch Team"))
}
