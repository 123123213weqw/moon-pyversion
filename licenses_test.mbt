///|
/// The stable code of the `InvalidLicense` error raised by `f`, or a marker when
/// the call unexpectedly succeeded.
fn expr_err(raw : String) -> String {
  try {
    ignore(canonicalize_license_expression(raw))
    "NO_ERROR"
  } catch {
    VersionError::InvalidLicense(code, _) => code
    _ => "OTHER_ERROR"
  }
}

///|
/// The same, for the file-path validator.
fn file_err(path : String) -> String {
  try {
    ignore(canonicalize_license_file(path))
    "NO_ERROR"
  } catch {
    VersionError::InvalidLicense(code, _) => code
    _ => "OTHER_ERROR"
  }
}

///|
test "simple identifiers are case folded" {
  assert_eq(canonicalize_license_expression("mit"), "MIT")
  assert_eq(canonicalize_license_expression("MIT"), "MIT")
  assert_eq(canonicalize_license_expression("Mit"), "MIT")
  assert_eq(canonicalize_license_expression("mIt"), "MIT")
  assert_eq(canonicalize_license_expression("apache-2.0"), "Apache-2.0")
  assert_eq(canonicalize_license_expression("BSD-2-Clause"), "BSD-2-Clause")
}

///|
test "the canonical spelling is not just title case" {
  // These four would be wrong under any hand-rolled casing rule.
  assert_eq(canonicalize_license_expression("0bsd"), "0BSD")
  assert_eq(canonicalize_license_expression("3d-slicer-1.0"), "3D-Slicer-1.0")
  assert_eq(
    canonicalize_license_expression("unicode-dfs-2016"),
    "Unicode-DFS-2016",
  )
  assert_eq(
    canonicalize_license_expression("x11-distribute-modifications-variant"),
    "X11-distribute-modifications-variant",
  )
  assert_eq(canonicalize_license_expression("adacore-doc"), "AdaCore-doc")
}

///|
test "surrounding whitespace is not significant" {
  assert_eq(canonicalize_license_expression(" mit "), "MIT")
  assert_eq(canonicalize_license_expression("  mit  "), "MIT")
  assert_eq(canonicalize_license_expression("\tmit\n"), "MIT")
  assert_eq(
    canonicalize_license_expression("mit\tand\tapache-2.0"),
    "MIT AND Apache-2.0",
  )
}

///|
test "python's unicode whitespace splits tokens too" {
  assert_eq(
    canonicalize_license_expression("MIT\u{00A0}OR\u{00A0}Apache-2.0"),
    "MIT OR Apache-2.0",
  )
  assert_eq(
    canonicalize_license_expression("MIT\u{2003}OR\u{2003}Apache-2.0"),
    "MIT OR Apache-2.0",
  )
  assert_eq(
    canonicalize_license_expression("MIT\u{000B}OR\u{000C}Apache-2.0"),
    "MIT OR Apache-2.0",
  )
}

///|
test "operators are uppercased whatever case they arrive in" {
  assert_eq(
    canonicalize_license_expression("mit and apache-2.0"),
    "MIT AND Apache-2.0",
  )
  assert_eq(
    canonicalize_license_expression("mit AND apache-2.0"),
    "MIT AND Apache-2.0",
  )
  assert_eq(
    canonicalize_license_expression("mit Or apache-2.0"),
    "MIT OR Apache-2.0",
  )
  assert_eq(
    canonicalize_license_expression("apache-2.0 with llvm-exception"),
    "Apache-2.0 WITH LLVM-exception",
  )
}

///|
test "parentheses are re-emitted without their padding" {
  assert_eq(canonicalize_license_expression("(mit)"), "(MIT)")
  assert_eq(canonicalize_license_expression("((mit))"), "((MIT))")
  assert_eq(canonicalize_license_expression("( mit )"), "(MIT)")
  assert_eq(
    canonicalize_license_expression("mit and (apache-2.0 or bsd-2-clause)"),
    "MIT AND (Apache-2.0 OR BSD-2-Clause)",
  )
  assert_eq(
    canonicalize_license_expression(
      "MIT AND (Apache-2.0 OR (BSD-2-Clause AND ISC))",
    ),
    "MIT AND (Apache-2.0 OR (BSD-2-Clause AND ISC))",
  )
}

///|
test "and binds tighter than or but neither is reordered" {
  assert_eq(
    canonicalize_license_expression("Apache-2.0 AND MIT OR BSD-3-Clause"),
    "Apache-2.0 AND MIT OR BSD-3-Clause",
  )
  assert_eq(
    canonicalize_license_expression("MIT or mit with llvm-exception"),
    "MIT OR MIT WITH LLVM-exception",
  )
}

///|
test "a plus suffix survives on the canonical identifier" {
  assert_eq(canonicalize_license_expression("mit+"), "MIT+")
  assert_eq(canonicalize_license_expression("gpl-2.0+"), "GPL-2.0+")
  assert_eq(
    canonicalize_license_expression("GPL-2.0+ OR MIT"),
    "GPL-2.0+ OR MIT",
  )
  assert_eq(canonicalize_license_expression(" MIT+ "), "MIT+")
}

///|
test "licenseref rewrites the prefix only" {
  assert_eq(canonicalize_license_expression("LicenseRef-Foo"), "LicenseRef-Foo")
  assert_eq(canonicalize_license_expression("licenseref-foo"), "LicenseRef-foo")
  assert_eq(canonicalize_license_expression("LICENSEREF-FOO"), "LicenseRef-FOO")
  assert_eq(
    canonicalize_license_expression("LicenseRef-Public-Domain"),
    "LicenseRef-Public-Domain",
  )
  assert_eq(
    canonicalize_license_expression("LicenseRef-foo.bar-1"),
    "LicenseRef-foo.bar-1",
  )
  assert_eq(canonicalize_license_expression("LicenseRef--"), "LicenseRef--")
  assert_eq(
    canonicalize_license_expression("LicenseRef-a..b"),
    "LicenseRef-a..b",
  )
}

///|
test "a duplicated licenseref takes the last spelling" {
  // `packaging` builds the reference map with a dict comprehension, so the last
  // occurrence of a lowercased key overwrites the earlier one.
  assert_eq(
    canonicalize_license_expression("MIT or LicenseRef-a or licenseref-A"),
    "MIT OR LicenseRef-A OR LicenseRef-A",
  )
  assert_eq(
    canonicalize_license_expression("licenseref-a or LicenseRef-A"),
    "LicenseRef-A OR LicenseRef-A",
  )
}

///|
test "licenseref bodies are restricted" {
  assert_eq(expr_err("LicenseRef-"), "INVALID_LICENSE_REF")
  assert_eq(expr_err("LicenseRef-a+"), "INVALID_LICENSE_REF")
  assert_eq(expr_err("LicenseRef-a_b"), "INVALID_LICENSE_REF")
}

///|
test "with needs a licence and an exception" {
  assert_eq(
    canonicalize_license_expression("MIT WITH Classpath-exception-2.0"),
    "MIT WITH Classpath-exception-2.0",
  )
  assert_eq(
    canonicalize_license_expression("GPL-2.0-only with classpath-exception-2.0"),
    "GPL-2.0-only WITH Classpath-exception-2.0",
  )
  assert_eq(expr_err("MIT WITH bogus-exception"), "UNKNOWN_LICENSE_EXCEPTION")
  assert_eq(expr_err("MIT WITH LicenseRef-x"), "UNKNOWN_LICENSE_EXCEPTION")
  assert_eq(expr_err("MIT WITH"), "INVALID_EXPRESSION")
  assert_eq(expr_err("with mit"), "INVALID_EXPRESSION")
  assert_eq(expr_err("MIT WITH (MIT)"), "INVALID_EXPRESSION")
  assert_eq(
    expr_err("MIT WITH LLVM-exception WITH LLVM-exception"),
    "INVALID_EXPRESSION",
  )
}

///|
test "empty and blank input is invalid" {
  assert_eq(expr_err(""), "INVALID_EXPRESSION")
  assert_eq(expr_err(" "), "INVALID_EXPRESSION")
  assert_eq(expr_err("\t"), "INVALID_EXPRESSION")
}

///|
test "syntax errors are reported as such" {
  assert_eq(expr_err("(mit"), "INVALID_EXPRESSION")
  assert_eq(expr_err("mit)"), "INVALID_EXPRESSION")
  assert_eq(expr_err("()"), "INVALID_EXPRESSION")
  assert_eq(expr_err("( )"), "INVALID_EXPRESSION")
  assert_eq(expr_err("mit and"), "INVALID_EXPRESSION")
  assert_eq(expr_err("and mit"), "INVALID_EXPRESSION")
  assert_eq(expr_err("and"), "INVALID_EXPRESSION")
  assert_eq(expr_err("or"), "INVALID_EXPRESSION")
  assert_eq(expr_err("with"), "INVALID_EXPRESSION")
  assert_eq(expr_err("mit mit"), "INVALID_EXPRESSION")
  assert_eq(expr_err("MIT and OR MIT"), "INVALID_EXPRESSION")
}

///|
test "juxtaposition is rejected, including parenthesised operands" {
  // `(False)(False)` would compile as a call, so packaging rejects it up front.
  assert_eq(expr_err("(MIT)(MIT)"), "INVALID_EXPRESSION")
  assert_eq(expr_err("MIT(mit)"), "INVALID_EXPRESSION")
  assert_eq(expr_err("(MIT) MIT"), "INVALID_EXPRESSION")
}

///|
test "unknown identifiers keep their own error code" {
  assert_eq(expr_err("invalid"), "UNKNOWN_LICENSE")
  assert_eq(expr_err("Use-it-after-midnight"), "UNKNOWN_LICENSE")
  assert_eq(expr_err("mit++"), "UNKNOWN_LICENSE")
  assert_eq(expr_err("+mit"), "UNKNOWN_LICENSE")
  assert_eq(expr_err("DocumentRef-x:LicenseRef-y"), "UNKNOWN_LICENSE")
}

///|
test "the error carries the offending token index" {
  let (code, index) = try {
    ignore(canonicalize_license_expression("MIT OR bogus OR MIT"))
    ("NO_ERROR", -1)
  } catch {
    VersionError::InvalidLicense(code, index) => (code, index)
    _ => ("OTHER_ERROR", -1)
  }
  assert_eq(code, "UNKNOWN_LICENSE")
  assert_eq(index, 2)
}

///|
test "nesting is accepted up to 200 levels and rejected at 201" {
  let at_limit = String::make(200, '(') + "MIT" + String::make(200, ')')
  assert_eq(canonicalize_license_expression(at_limit).length(), 403)
  let over_limit = String::make(201, '(') + "MIT" + String::make(201, ')')
  assert_eq(expr_err(over_limit), "INVALID_EXPRESSION")
}

///|
test "is_valid_license_expression agrees with the canonicalizer" {
  assert_true(is_valid_license_expression("mit"))
  assert_true(
    is_valid_license_expression("mit and (apache-2.0 or bsd-2-clause)"),
  )
  assert_true(is_valid_license_expression("LicenseRef-anything"))
  assert_false(is_valid_license_expression(""))
  assert_false(is_valid_license_expression("(mit"))
  assert_false(is_valid_license_expression("mit mit"))
  assert_false(is_valid_license_expression("nope"))
  assert_false(is_valid_license_expression("mit++"))
}

///|
test "the embedded table accepts a broad sample of spdx identifiers" {
  // The differential corpus exercises all 699 licences and all 79 exceptions;
  // these are the spellings a hand-rolled casing table would get wrong.
  for
    id in [
      "0BSD", "3D-Slicer-1.0", "AdaCore-doc", "GPL-2.0-or-later", "Unicode-DFS-2016",
      "X11-distribute-modifications-variant", "zlib-acknowledgement",
    ] {
    assert_eq(canonicalize_license_expression(id.to_lower()), id)
  }
  assert_true(is_valid_license_expression("MIT WITH 389-exception"))
  assert_true(is_valid_license_expression("MIT WITH LLVM-exception"))
  assert_true(
    is_valid_license_expression("GPL-2.0-only WITH Classpath-exception-2.0"),
  )
}

///|
test "plain license file names are returned unchanged" {
  assert_eq(canonicalize_license_file("LICENSE"), "LICENSE")
  assert_eq(canonicalize_license_file("LICENSE.txt"), "LICENSE.txt")
  assert_eq(canonicalize_license_file("LICENSE.md"), "LICENSE.md")
  assert_eq(canonicalize_license_file("COPYING"), "COPYING")
  assert_eq(
    canonicalize_license_file("licenses/PSF-2.0.txt"),
    "licenses/PSF-2.0.txt",
  )
  assert_eq(canonicalize_license_file("a/b/c.txt"), "a/b/c.txt")
  assert_eq(canonicalize_license_file("LICENSE-MIT"), "LICENSE-MIT")
  assert_eq(canonicalize_license_file("LICENSE "), "LICENSE ")
}

///|
test "file paths that a normalizer would change are rejected instead" {
  assert_eq(file_err("./LICENSE"), "NOT_POSIX_PATH")
  assert_eq(file_err("dir/"), "NOT_POSIX_PATH")
  assert_eq(file_err("a//b"), "NOT_POSIX_PATH")
  assert_eq(file_err("a/./b"), "NOT_POSIX_PATH")
  assert_eq(file_err(""), "NOT_POSIX_PATH")
  assert_eq(file_err("a\\b.txt"), "NOT_POSIX_PATH")
}

///|
test "parent directories and globs are rejected before anything else" {
  assert_eq(file_err("../LICENSE"), "PARENT_DIRECTORY")
  assert_eq(file_err("a/../b"), "PARENT_DIRECTORY")
  assert_eq(file_err("a..b"), "PARENT_DIRECTORY")
  assert_eq(file_err("LICENSE*"), "UNRESOLVED_GLOB")
  assert_eq(file_err("*.txt"), "UNRESOLVED_GLOB")
}

///|
test "absolute paths are rejected in both flavours" {
  assert_eq(file_err("/LICENSE"), "ABSOLUTE_PATH")
  assert_eq(file_err("//srv/LICENSE"), "ABSOLUTE_PATH")
  assert_eq(file_err("C:/LICENSE"), "ABSOLUTE_PATH")
  assert_eq(file_err("C:\\LICENSE"), "ABSOLUTE_PATH")
  // A drive with no separator is *relative* in windows terms, so it survives.
  assert_eq(canonicalize_license_file("C:foo"), "C:foo")
}

///|
test "license error diagnostics render the code and offset" {
  let error = VersionError::InvalidLicense("UNKNOWN_LICENSE", 3)
  assert_eq(error.diagnostic(), "UNKNOWN_LICENSE at 3")
  assert_eq(error.to_string(), "UNKNOWN_LICENSE at 3")
  assert_eq(error, VersionError::InvalidLicense("UNKNOWN_LICENSE", 3))
}
