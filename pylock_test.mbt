///|
/// M8 tests: `pylock.mbt` (PEP 751 lock files).
///
/// The documents below are the specification's own: the example that PEP 751
/// prints is parsed verbatim, and every other document is small enough to read as
/// the rule it pins. A block asserts the *error code* of a rejection, not merely
/// that something failed, because the code is the diagnostic a caller reads, and
/// the blocks that check a family of documents run a table of
/// `(document, code)` pairs so a regression names the member it broke.
///
/// The last blocks pin the divergences the module doc lists: `created-by` may be
/// absent, `version` may sit next to a source tree, a file record may omit
/// `hashes`, `upload-time` is recorded verbatim instead of being normalized to
/// UTC, and unknown keys are ignored.

///|
/// The two members nearly every document here needs.
fn lock_prefix() -> String {
  let text =
    #|lock-version = "1.0"
    #|created-by = "moon-pyversion"
  text
}

///|
/// A document from its remaining text.
fn lock_document(body : String) -> String {
  lock_prefix() + "\n" + body
}

///|
/// A document without `created-by`, for the block that pins its acceptance.
fn lock_without_created_by(body : String) -> String {
  "lock-version = \"1.0\"\n" + body
}

///|
/// Parse a document that must be valid.
fn lock_of(text : String) -> Pylock {
  Pylock::parse(text) catch {
    _ => abort("expected a valid lock file: \{text}")
  }
}

///|
/// The error code of a rejected document, or `<accepted>` when it parses, so a
/// test can assert *why* a document was rejected.
fn lock_error(text : String) -> String {
  try {
    ignore(Pylock::parse(text))
    "<accepted>"
  } catch {
    VersionError::InvalidPylock(code, _) => code
    other => "unexpected:\{other.diagnostic()}"
  }
}

///|
/// The `(code, ordinal)` pair of a rejected document, or `("<accepted>", -1)`.
fn lock_error_at(text : String) -> (String, Int) {
  try {
    ignore(Pylock::parse(text))
    ("<accepted>", -1)
  } catch {
    VersionError::InvalidPylock(code, ordinal) => (code, ordinal)
    other => ("unexpected:\{other.diagnostic()}", -1)
  }
}

///|
/// Assert that a document is rejected with exactly `code`.
fn assert_lock_error(text : String, code : String) -> Unit {
  let actual = lock_error(text)
  if actual != code {
    abort("expected \{code}, got \{actual} for: \{text}")
  }
}

///|
/// Assert that a document is rejected with `code` at `ordinal`.
fn assert_lock_error_at(text : String, code : String, ordinal : Int) -> Unit {
  let outcome = lock_error_at(text)
  if outcome.0 != code || outcome.1 != ordinal {
    abort(
      "expected \{code}@\{ordinal}, got \{outcome.0}@\{outcome.1} for: \{text}",
    )
  }
}

///|
/// Run a table of `(document, code)` pairs.
fn assert_codes(cases : Array[(String, String)]) -> Unit {
  for pair in cases {
    assert_lock_error(pair.0, pair.1)
  }
}

///|
/// Run a table of `([[packages]] fields, code)` pairs: every fragment is the body
/// of the single package entry of an otherwise valid document.
fn assert_entry_codes(cases : Array[(String, String)]) -> Unit {
  for pair in cases {
    assert_lock_error(lock_document("\n[[packages]]\n" + pair.0), pair.1)
  }
}

///|
/// The single entry of a document that holds exactly one package.
fn lock_entry(fields : String) -> PylockPackage {
  lock_of(lock_document("\n[[packages]]\n" + fields)).packages()[0]
}

///|
/// A marker environment from its single-valued pairs.
///
/// The set-valued keys (`extras`, `dependency_groups`) are seeded empty rather
/// than left out: a PEP 751 marker may test them, and an environment that cannot
/// answer a key raises instead of answering. Tests that want the raising
/// behaviour build their environment with `MarkerEnvironment::new` directly.
fn marker_environment_of(pairs : Array[(String, String)]) -> MarkerEnvironment {
  let environment = MarkerEnvironment::new()
  environment.set_names("extras", [])
  environment.set_names("dependency_groups", [])
  for pair in pairs {
    environment.set(pair.0, pair.1)
  }
  environment
}

///|
/// The example PEP 751 prints, byte for byte, including the `[tool]` table and the
/// `[[packages.attestation-identities]]` entries this reader ignores.
fn pep751_example() -> String {
  let text =
    #|lock-version = '1.0'
    #|environments = ["sys_platform == 'win32'", "sys_platform == 'linux'"]
    #|requires-python = '==3.12'
    #|created-by = 'mousebender'
    #|
    #|[[packages]]
    #|name = 'attrs'
    #|version = '25.1.0'
    #|requires-python = '>=3.8'
    #|wheels = [
    #|  {name = 'attrs-25.1.0-py3-none-any.whl', upload-time = 2025-01-25T11:30:10.164985+00:00, url = 'https://files.pythonhosted.org/packages/fc/30/d4986a882011f9df997a55e6becd864812ccfcd821d64aac8570ee39f719/attrs-25.1.0-py3-none-any.whl', size = 63152, hashes = {sha256 = 'c75a69e28a550a7e93789579c22aa26b0f5b83b75dc4e08fe092980051e1090a'}},
    #|]
    #|[[packages.attestation-identities]]
    #|environment = 'release-pypi'
    #|kind = 'GitHub'
    #|repository = 'python-attrs/attrs'
    #|workflow = 'pypi-package.yml'
    #|
    #|[[packages]]
    #|name = 'cattrs'
    #|version = '24.1.2'
    #|requires-python = '>=3.8'
    #|dependencies = [
    #|    {name = 'attrs'},
    #|]
    #|wheels = [
    #|    {name = 'cattrs-24.1.2-py3-none-any.whl', upload-time = 2024-09-22T14:58:34.812643+00:00, url = 'https://files.pythonhosted.org/packages/c8/d5/867e75361fc45f6de75fe277dd085627a9db5ebb511a87f27dc1396b5351/cattrs-24.1.2-py3-none-any.whl', size = 66446, hashes = {sha256 = '67c7495b760168d931a10233f979b28dc04daf853b30752246f4f8471c6d68d0'}},
    #|]
    #|
    #|[[packages]]
    #|name = 'numpy'
    #|version = '2.2.3'
    #|requires-python = '>=3.10'
    #|wheels = [
    #|  {name = 'numpy-2.2.3-cp312-cp312-win_amd64.whl', upload-time = 2025-02-13T16:51:21.821880+00:00, url = 'https://files.pythonhosted.org/packages/42/6e/55580a538116d16ae7c9aa17d4edd56e83f42126cb1dfe7a684da7925d2c/numpy-2.2.3-cp312-cp312-win_amd64.whl', size = 12626357, hashes = {sha256 = '83807d445817326b4bcdaaaf8e8e9f1753da04341eceec705c001ff342002e5d'}},
    #|  {name = 'numpy-2.2.3-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl', upload-time = 2025-02-13T16:50:00.079662+00:00, url = 'https://files.pythonhosted.org/packages/39/04/78d2e7402fb479d893953fb78fa7045f7deb635ec095b6b4f0260223091a/numpy-2.2.3-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl', size = 16116679, hashes = {sha256 = '3b787adbf04b0db1967798dba8da1af07e387908ed1553a0d6e74e084d1ceafe'}},
    #|]
    #|
    #|[tool.mousebender]
    #|command = ['.', 'lock', '--platform', 'cpython3.12-windows-x64', '--platform', 'cpython3.12-manylinux2014-x64', 'cattrs', 'numpy']
    #|run-on = 2025-03-06T12:28:57.760769
  text
}

///|
test "pylock: a minimal lock file parses and every accessor is empty" {
  let text =
    #|lock-version = "1.0"
    #|created-by = "moon-pyversion"
    #|
    #|[[packages]]
    #|name = "attrs"
    #|version = "25.1.0"
  let lock = lock_of(text)
  assert_eq(lock.lock_version(), "1.0")
  assert_eq(lock.created_by(), "moon-pyversion")
  assert_eq(lock.environments(), [])
  assert_eq(lock.requires_python(), None)
  assert_eq(lock.extras(), [])
  assert_eq(lock.dependency_groups(), [])
  assert_eq(lock.default_groups(), [])
  assert_eq(lock.packages().length(), 1)
  let entry = lock.packages()[0]
  assert_eq(entry.name, "attrs")
  assert_eq(entry.version.unwrap().to_string(), "25.1.0")
  assert_true(entry.marker is None)
  assert_true(entry.requires_python is None)
  assert_eq(entry.dependencies, [])
  assert_eq(entry.all_files(), [])
  assert_true(entry.vcs is None)
  assert_true(entry.directory is None)
  assert_true(entry.sdist is None)
  assert_true(entry.archive is None)
  assert_true(entry.index is None)
  assert_true(entry.path is None)
  assert_false(entry.is_source_tree())
  assert_false(entry.is_direct_reference())
  assert_false(lock.supports_python(Version::parse("2.7")) is false)
}

///|
test "pylock: packages may be an empty array, and lookups of nothing are empty" {
  let lock = lock_of(lock_document("packages = []\n"))
  assert_eq(lock.packages(), [])
  assert_eq(lock.packages_named("attrs"), [])
  assert_eq(lock.files_for("attrs"), [])
  assert_eq(lock.dependencies_of("attrs"), [])
  let environment = marker_environment_of([("sys_platform", "linux")])
  assert_false(lock.is_applicable("attrs", environment))
  assert_eq(lock.applicable_packages(environment), [])
  assert_true(lock.accepts_environment(environment))
}

///|
test "pylock: lock-version is required, is a string, and must be 1.0" {
  assert_lock_error("", "LOCK_VERSION_REQUIRED")
  assert_lock_error(
    "created-by = \"x\"\npackages = []\n", "LOCK_VERSION_REQUIRED",
  )
  assert_lock_error("lock-version = \"\"\n", "LOCK_VERSION_REQUIRED")
  assert_lock_error("lock-version = 1.0\n", "LOCK_VERSION_TYPE")
  assert_lock_error("lock-version = 10\n", "LOCK_VERSION_TYPE")
  assert_lock_error("lock-version = true\n", "LOCK_VERSION_TYPE")
  // 1.1 is a *minor* version of a major version this reader does support; the
  // specification asks for a warning there, and this reader has no warning
  // channel, so it rejects instead of accepting something it cannot check.
  for version in ["1", "1.1", "2.0", "1.0.0", "v1.0", "01.0"] {
    assert_lock_error("lock-version = \"\{version}\"\n", "LOCK_VERSION_INVALID")
  }
  assert_eq(
    lock_of("lock-version = \"1.0\"\ncreated-by = \"x\"\npackages = []\n").lock_version(),
    "1.0",
  )
}

///|
test "pylock: packages is required, is an array of tables, and reports a position" {
  assert_lock_error(lock_document(""), "PACKAGES_REQUIRED")
  assert_lock_error(
    lock_document("packages = \"attrs\"\n"),
    "PACKAGES_NOT_ARRAY",
  )
  assert_lock_error(
    lock_document("packages = { name = \"attrs\" }\n"),
    "PACKAGES_NOT_ARRAY",
  )
  assert_lock_error(
    lock_document("packages = [\"attrs\"]\n"),
    "PACKAGE_NOT_TABLE",
  )
  assert_lock_error(lock_document("packages = [1]\n"), "PACKAGE_NOT_TABLE")
  // The `Int` of the error is the ordinal of the offending entry, not an offset.
  // The third entry is broken with an unparsable version: leaving the member out
  // is not an error any more, since `packages.version` is `Required? : no`.
  let broken = lock_document(
    "\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n\n[[packages]]\nname = \"cattrs\"\nversion = \"24.1.2\"\n\n[[packages]]\nname = \"numpy\"\nversion = \"not a version\"\n",
  )
  assert_lock_error_at(broken, "PACKAGE_VERSION_INVALID", 2)
}

///|
test "pylock: packages.name is required, a string and a valid project name" {
  assert_entry_codes([
    ("version = \"1.0\"\n", "PACKAGE_NAME_REQUIRED"),
    ("name = \"\"\nversion = \"1.0\"\n", "PACKAGE_NAME_REQUIRED"),
    ("name = 1\nversion = \"1.0\"\n", "PACKAGE_NAME_TYPE"),
    ("name = \"foo-\"\nversion = \"1.0\"\n", "PACKAGE_NAME_INVALID"),
    ("name = \"_foo\"\nversion = \"1.0\"\n", "PACKAGE_NAME_INVALID"),
    ("name = \"foo bar\"\nversion = \"1.0\"\n", "PACKAGE_NAME_INVALID"),
  ])
  // The spelling is kept: a locker writes a normalized name, but a reader that
  // compared spellings would not find `Zope.Interface` through `zope-interface`.
  let entry = lock_entry("name = \"Zope.Interface\"\nversion = \"5.0\"\n")
  assert_eq(entry.name, "Zope.Interface")
}

///|
test "pylock: packages.version is optional, and forbidden next to a source tree" {
  // `packages.version` is `Required? : no`, and a SHOULD for an entry that names
  // files ("The version SHOULD be specified when the version is known to be
  // stable"), so an entry that omits it is well formed and simply has no version
  // to report. This reader used to demand one unless a direct reference was
  // recorded; that was a declared divergence and it is settled now.
  let no_version = lock_entry("name = \"attrs\"\n")
  assert_true(no_version.version is None)
  assert_false(no_version.is_source_tree())
  assert_false(no_version.is_direct_reference())
  let wheel_only = lock_entry(
    "name = \"attrs\"\n[[packages.wheels]]\nname = \"attrs-25.1.0-py3-none-any.whl\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_true(wheel_only.version is None)
  assert_eq(wheel_only.wheels.length(), 1)
  // An empty value counts as absent, so it is no more an error than omission is.
  assert_true(lock_entry("name = \"attrs\"\nversion = \"\"\n").version is None)
  // A version that is present is still parsed, and a bad one is still rejected.
  assert_entry_codes([
    ("name = \"attrs\"\nversion = 1.0\n", "PACKAGE_VERSION_TYPE"),
    ("name = \"attrs\"\nversion = true\n", "PACKAGE_VERSION_TYPE"),
    (
      "name = \"attrs\"\nversion = \"not a version\"\n", "PACKAGE_VERSION_INVALID",
    ),
  ])
  // A *source tree* is the case the specification forbids it in: "The version MUST
  // NOT be included when it cannot be guaranteed to be consistent with the code
  // used (i.e. when a source tree is used)".
  assert_entry_codes([
    (
      "name = \"attrs\"\nversion = \"25.1.0\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/attrs.git\"\ncommit-id = \"0f1e2d3c\"\n",
      "PACKAGE_VERSION_NOT_ALLOWED",
    ),
    (
      "name = \"attrs\"\nversion = \"25.1.0\"\n[packages.directory]\npath = \"../attrs\"\n",
      "PACKAGE_VERSION_NOT_ALLOWED",
    ),
  ])
  // An *archive* is a file rather than a tree, so a version is allowed next to it.
  let with_archive = lock_entry(
    "name = \"attrs\"\nversion = \"25.1.0\"\n[packages.archive]\nurl = \"https://example.invalid/attrs-25.1.0.tar.gz\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(with_archive.version.unwrap().to_string(), "25.1.0")
  // ... and the version stays absent when the entry is a source tree.
  let fields =
    #|name = "attrs"
    #|[packages.vcs]
    #|type = "git"
    #|url = "https://example.invalid/attrs.git"
    #|commit-id = "0f1e2d3c"
  let entry = lock_entry(fields)
  assert_true(entry.version is None)
  assert_true(entry.is_source_tree())
  assert_true(entry.is_direct_reference())
}

///|
test "pylock: packages.marker must parse" {
  let entry = lock_entry(
    "name = \"attrs\"\nversion = \"25.1.0\"\nmarker = \"python_version >= '3.8'\"\n",
  )
  // The spelling is the caller's, not the normalized rendering.
  assert_eq(entry.marker, Some("python_version >= '3.8'"))
  assert_entry_codes([
    ("name = \"attrs\"\nversion = \"1.0\"\nmarker = 1\n", "PACKAGE_MARKER_TYPE"),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nmarker = \"python_version >=\"\n", "PACKAGE_MARKER_INVALID",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nmarker = \"python_versoin >= '3.8'\"\n",
      "PACKAGE_MARKER_INVALID",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nmarker = \"extra == 'docs' and\"\n",
      "PACKAGE_MARKER_INVALID",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nmarker = \"'docs' in extras and\"\n",
      "PACKAGE_MARKER_INVALID",
    ),
  ])
}

///|
test "pylock: packages.requires-python must parse" {
  let entry = lock_entry(
    "name = \"attrs\"\nversion = \"1.0\"\nrequires-python = \">=3.8\"\n",
  )
  assert_eq(entry.requires_python, Some(">=3.8"))
  assert_true(
    entry.requires_python_set().unwrap().contains(Version::parse("3.12")),
  )
  assert_false(
    entry.requires_python_set().unwrap().contains(Version::parse("3.7")),
  )
  assert_entry_codes([
    (
      "name = \"attrs\"\nversion = \"1.0\"\nrequires-python = 3\n", "PACKAGE_REQUIRES_PYTHON_TYPE",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nrequires-python = \"3.8\"\n", "PACKAGE_REQUIRES_PYTHON_INVALID",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nrequires-python = \"=>3.8\"\n", "PACKAGE_REQUIRES_PYTHON_INVALID",
    ),
    (
      "name = \"attrs\"\nversion = \"1.0\"\nrequires-python = \"3.8.*\"\n", "PACKAGE_REQUIRES_PYTHON_INVALID",
    ),
  ])
}

///|
test "pylock: environments are marker expressions" {
  let lock = lock_of(
    lock_document(
      "environments = [\"sys_platform == 'linux'\", \"sys_platform == 'win32'\"]\npackages = []\n",
    ),
  )
  assert_eq(lock.environments(), [
    "sys_platform == 'linux'", "sys_platform == 'win32'",
  ])
  // `===` is one of PEP 508's operators, so an environment set may use it:
  // measured against `packaging`, which accepts `sys_platform === "linux"`.
  let strict = lock_of(
    lock_document(
      "environments = [\"sys_platform === 'linux'\"]\npackages = []\n",
    ),
  )
  assert_eq(strict.environments(), ["sys_platform === 'linux'"])
  assert_codes([
    (
      lock_document(
        "environments = \"sys_platform == 'linux'\"\npackages = []\n",
      ),
      "ENVIRONMENTS_NOT_ARRAY",
    ),
    (
      lock_document("environments = [1]\npackages = []\n"),
      "ENVIRONMENTS_ENTRY_TYPE",
    ),
    (
      lock_document("environments = [\"\"]\npackages = []\n"),
      "ENVIRONMENT_MARKER_INVALID",
    ),
    (
      lock_document(
        "environments = [\"sys_platform == linux\"]\npackages = []\n",
      ),
      "ENVIRONMENT_MARKER_INVALID",
    ),
    (
      lock_document("environments = [\"unknown_key == 'x'\"]\npackages = []\n"),
      "ENVIRONMENT_MARKER_INVALID",
    ),
  ])
}

///|
test "pylock: requires-python is a specifier set" {
  let lock = lock_of(
    lock_document("requires-python = \">=3.9\"\npackages = []\n"),
  )
  assert_eq(lock.requires_python(), Some(">=3.9"))
  assert_true(
    lock.requires_python_set().unwrap().contains(Version::parse("3.13")),
  )
  assert_true(lock.supports_python(Version::parse("3.9")))
  assert_false(lock.supports_python(Version::parse("3.8")))
  // A trailing comma is accepted: measured against `packaging`, whose
  // `SpecifierSet(">=3.9,")` is `>=3.9`.
  assert_eq(
    lock_of(lock_document("requires-python = \">=3.9,\"\npackages = []\n")).requires_python(),
    Some(">=3.9,"),
  )
  let unrestricted = lock_of(lock_document("packages = []\n"))
  assert_eq(unrestricted.requires_python(), None)
  assert_true(unrestricted.supports_python(Version::parse("2.7")))
  assert_codes([
    (
      lock_document("requires-python = 3\npackages = []\n"),
      "REQUIRES_PYTHON_TYPE",
    ),
    (
      lock_document("requires-python = \"3.9\"\npackages = []\n"),
      "REQUIRES_PYTHON_INVALID",
    ),
    (
      lock_document("requires-python = \">=3.9,<\"\npackages = []\n"),
      "REQUIRES_PYTHON_INVALID",
    ),
  ])
}

///|
test "pylock: extras, dependency-groups and default-groups" {
  let lock = lock_of(
    lock_document(
      "extras = [\"docs\", \"Test.Helpers\"]\ndependency-groups = [\"dev\"]\ndefault-groups = [\"dev\"]\npackages = []\n",
    ),
  )
  assert_eq(lock.extras(), ["docs", "Test.Helpers"])
  assert_eq(lock.dependency_groups(), ["dev"])
  assert_eq(lock.default_groups(), ["dev"])
  let absent = lock_of(lock_document("packages = []\n"))
  assert_eq(absent.extras(), [])
  assert_eq(absent.dependency_groups(), [])
  assert_eq(absent.default_groups(), [])
  assert_codes([
    (lock_document("extras = \"docs\"\npackages = []\n"), "EXTRAS_NOT_ARRAY"),
    (lock_document("extras = [1]\npackages = []\n"), "EXTRAS_ENTRY_TYPE"),
    (lock_document("extras = [\"foo-\"]\npackages = []\n"), "EXTRA_INVALID"),
    (lock_document("extras = [\"\"]\npackages = []\n"), "EXTRA_INVALID"),
    (
      lock_document("dependency-groups = \"dev\"\npackages = []\n"),
      "DEPENDENCY_GROUPS_NOT_ARRAY",
    ),
    (
      lock_document("dependency-groups = [1]\npackages = []\n"),
      "DEPENDENCY_GROUPS_ENTRY_TYPE",
    ),
    (
      lock_document("dependency-groups = [\"dev group\"]\npackages = []\n"),
      "DEPENDENCY_GROUP_INVALID",
    ),
    (
      lock_document("default-groups = \"dev\"\npackages = []\n"),
      "DEFAULT_GROUPS_NOT_ARRAY",
    ),
    (
      lock_document("default-groups = [true]\npackages = []\n"),
      "DEFAULT_GROUPS_ENTRY_TYPE",
    ),
    (
      lock_document("default-groups = [\"dev-group-\"]\npackages = []\n"),
      "DEFAULT_GROUP_INVALID",
    ),
  ])
}

///|
test "pylock: created-by is required" {
  assert_eq(
    lock_of(lock_document("packages = []\n")).created_by(),
    "moon-pyversion",
  )
  // The specification's `created-by` line is `Required? : yes`, and this reader
  // used to accept its absence; it no longer does. Absence and an empty value are
  // both rejections now, and the emptiness is a rejection of its own because an
  // empty string cannot name the tool that wrote the file.
  assert_codes([
    (lock_without_created_by("packages = []\n"), "CREATED_BY_REQUIRED"),
    (
      lock_without_created_by("created-by = \"\"\npackages = []\n"),
      "CREATED_BY_REQUIRED",
    ),
    // Built without the prefix, because `created-by` may only appear once: with
    // the prefix the document fails on the duplicate key instead of the type.
    (
      lock_without_created_by("created-by = 1\npackages = []\n"),
      "CREATED_BY_TYPE",
    ),
    (
      lock_without_created_by("created-by = [\"x\"]\npackages = []\n"),
      "CREATED_BY_TYPE",
    ),
  ])
}

///|
test "pylock: dependencies are inline tables with a valid name" {
  let entry = lock_entry(
    "name = \"cattrs\"\nversion = \"24.1.2\"\ndependencies = [{ name = \"attrs\" }]\n",
  )
  assert_eq(entry.dependencies.length(), 1)
  assert_eq(entry.dependencies[0].name, "attrs")
  assert_true(entry.dependencies[0].version is None)
  assert_true(entry.dependencies[0].marker is None)
  assert_eq(entry.dependencies[0].extras, [])
  assert_entry_codes([
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = \"attrs\"\n", "DEPENDENCIES_NOT_ARRAY",
    ),
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = [\"attrs\"]\n", "DEPENDENCY_NOT_TABLE",
    ),
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = [{ version = \"1.0\" }]\n",
      "DEPENDENCY_NAME_REQUIRED",
    ),
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = [{ name = \"\" }]\n",
      "DEPENDENCY_NAME_REQUIRED",
    ),
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = [{ name = 1 }]\n", "DEPENDENCY_NAME_TYPE",
    ),
    (
      "name = \"cattrs\"\nversion = \"1.0\"\ndependencies = [{ name = \"foo-\" }]\n",
      "DEPENDENCY_NAME_INVALID",
    ),
  ])
}

///|
test "pylock: a dependency may carry a version, a marker and extras" {
  let entry = lock_entry(
    "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", version = \"25.1.0\", marker = \"python_version >= '3.8'\", extras = [\"docs\"] }]\n",
  )
  let dependency = entry.dependencies[0]
  assert_eq(dependency.name, "attrs")
  assert_eq(dependency.version.unwrap().to_string(), "25.1.0")
  assert_eq(dependency.marker, Some("python_version >= '3.8'"))
  assert_eq(dependency.extras, ["docs"])
  assert_entry_codes([
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", version = 1 }]\n",
      "DEPENDENCY_VERSION_TYPE",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", version = \"nope\" }]\n",
      "DEPENDENCY_VERSION_INVALID",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", marker = 1 }]\n",
      "DEPENDENCY_MARKER_TYPE",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", marker = \"python_version >=\" }]\n",
      "DEPENDENCY_MARKER_INVALID",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", extras = \"docs\" }]\n",
      "DEPENDENCY_EXTRAS_NOT_ARRAY",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", extras = [1] }]\n",
      "DEPENDENCY_EXTRAS_ENTRY_TYPE",
    ),
    (
      "name = \"demo\"\nversion = \"1.0\"\ndependencies = [{ name = \"attrs\", extras = [\"foo-\"] }]\n",
      "DEPENDENCY_EXTRA_INVALID",
    ),
  ])
}

///|
test "pylock: a package must not depend on itself" {
  assert_entry_codes([
    (
      "name = \"spam\"\nversion = \"1.0\"\ndependencies = [{ name = \"spam\" }]\n",
      "DEPENDENCY_SELF_REFERENCE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\ndependencies = [{ name = \"spam\", version = \"1.0\" }]\n",
      "DEPENDENCY_SELF_REFERENCE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\ndependencies = [{ name = \"SPAM\" }]\n",
      "DEPENDENCY_SELF_REFERENCE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\ndependencies = [{ name = \"spam\", version = \"1.0.0\" }]\n",
      "DEPENDENCY_SELF_REFERENCE",
    ),
  ])
  // A dependency that names another version of the same project is a reference to
  // a different `[[packages]]` entry, which the file format allows.
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"2.0\"\ndependencies = [{ name = \"spam\", version = \"1.0\" }]\n",
  )
  assert_eq(entry.dependencies[0].name, "spam")
  // Another entry's dependency on the name is not self-referential at all.
  let other = lock_entry(
    "name = \"eggs\"\nversion = \"1.0\"\ndependencies = [{ name = \"spam\" }]\n",
  )
  assert_eq(other.dependencies[0].name, "spam")
}

///|
test "pylock: the source forms are mutually exclusive" {
  let vcs =
    #|[packages.vcs]
    #|type = "git"
    #|url = "https://example.invalid/spam.git"
    #|commit-id = "0f1e2d3c"
  let directory =
    #|[packages.directory]
    #|path = "../spam"
  let archive =
    #|[packages.archive]
    #|url = "https://example.invalid/spam-1.0.tar.gz"
    #|hashes = { sha256 = "abc" }
  let wheels =
    #|[[packages.wheels]]
    #|name = "spam-1.0-py3-none-any.whl"
    #|hashes = { sha256 = "abc" }
  let sdist =
    #|[packages.sdist]
    #|name = "spam-1.0.tar.gz"
    #|hashes = { sha256 = "abc" }
  // two direct references, or a direct reference next to a file list
  assert_codes([
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\n" + vcs + "\n" + wheels + "\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\n" + directory + "\n" + archive + "\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\n" + vcs + "\n" + directory + "\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\n" + archive + "\n" + sdist + "\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\npath = \"../spam\"\nfiles = [{ name = \"spam-1.0.tar.gz\" }]\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
  ])
  // A file list may sit next to another file list: a package that publishes both
  // an sdist and wheels is the specification's own example.
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n" + sdist + "\n" + wheels,
  )
  assert_eq(entry.sdist.unwrap().kind, SdistFile)
  assert_eq(entry.wheels[0].kind, WheelFile)
  assert_eq(entry.all_files().length(), 2)
  // ... and `index` sits next to anything.
  let indexed = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\nindex = \"https://pypi.org/simple/\"\n" +
    wheels,
  )
  assert_eq(indexed.index, Some("https://pypi.org/simple/"))
}

///|
test "pylock: [packages.vcs] needs a type, a location and a commit" {
  let fields =
    #|name = "spam"
    #|version = ""
    #|[packages.vcs]
    #|type = "git"
    #|url = "https://example.invalid/spam.git"
    #|requested-revision = "main"
    #|commit-id = "0f1e2d3c"
    #|subdirectory = "python"
  let entry = lock_entry(fields)
  let vcs = entry.vcs.unwrap()
  assert_eq(vcs.vcs_type, "git")
  assert_eq(vcs.url, Some("https://example.invalid/spam.git"))
  assert_eq(vcs.path, None)
  assert_eq(vcs.requested_revision, Some("main"))
  assert_eq(vcs.commit_id, "0f1e2d3c")
  assert_eq(vcs.subdirectory, Some("python"))
  // `path` instead of `url` is the other half of the same rule.
  let direct = lock_entry(
    "name = \"spam\"\n[packages.vcs]\ntype = \"hg\"\npath = \"../spam\"\ncommit-id = \"deadbeef\"\n",
  )
  assert_eq(direct.vcs.unwrap().path, Some("../spam"))
  // The package-level `path` (the draft spelling) is a source of its own, so it
  // cannot sit next to a `[packages.vcs]` table.
  assert_codes([
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\npath = \"spam\"\n[packages.vcs]\ntype = \"hg\"\npath = \"../spam\"\ncommit-id = \"deadbeef\"\n",
      ),
      "PACKAGE_SOURCE_CONFLICT",
    ),
  ])
  let entry_cases : Array[(String, String)] = [
    ("name = \"spam\"\nvcs = \"git\"\n", "VCS_NOT_TABLE"),
    (
      "name = \"spam\"\n[packages.vcs]\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"x\"\n",
      "VCS_TYPE_REQUIRED",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"x\"\n",
      "VCS_TYPE_REQUIRED",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = 1\ncommit-id = \"x\"\n", "VCS_TYPE_INVALID",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"github\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"x\"\n",
      "VCS_TYPE_INVALID",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\ncommit-id = \"x\"\n", "VCS_URL_REQUIRED",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = 1\ncommit-id = \"x\"\n",
      "VCS_URL_TYPE",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\npath = 1\ncommit-id = \"x\"\n",
      "VCS_PATH_TYPE",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\n",
      "VCS_COMMIT_ID_REQUIRED",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = 1\n",
      "VCS_COMMIT_ID_TYPE",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"x\"\nrequested-revision = 1\n",
      "VCS_REQUESTED_REVISION_TYPE",
    ),
    (
      "name = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"x\"\nsubdirectory = 1\n",
      "VCS_SUBDIRECTORY_TYPE",
    ),
  ]
  assert_entry_codes(entry_cases)
}

///|
test "pylock: [packages.directory] needs a path and defaults editable to false" {
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"\"\n[packages.directory]\npath = \"../spam\"\nsubdirectory = \"python\"\n",
  )
  let directory = entry.directory.unwrap()
  assert_eq(directory.path, "../spam")
  assert_false(directory.editable)
  assert_eq(directory.subdirectory, Some("python"))
  let editable = lock_entry(
    "name = \"spam\"\nversion = \"\"\n[packages.directory]\npath = \"../spam\"\neditable = true\n",
  )
  assert_true(editable.directory.unwrap().editable)
  assert_true(editable.directory.unwrap().subdirectory is None)
  assert_entry_codes([
    ("name = \"spam\"\ndirectory = \"../spam\"\n", "DIRECTORY_NOT_TABLE"),
    (
      "name = \"spam\"\n[packages.directory]\neditable = true\n", "DIRECTORY_PATH_REQUIRED",
    ),
    ("name = \"spam\"\n[packages.directory]\npath = 1\n", "DIRECTORY_PATH_TYPE"),
    (
      "name = \"spam\"\n[packages.directory]\npath = \"../spam\"\neditable = \"yes\"\n",
      "DIRECTORY_EDITABLE_TYPE",
    ),
    (
      "name = \"spam\"\n[packages.directory]\npath = \"../spam\"\nsubdirectory = 1\n",
      "DIRECTORY_SUBDIRECTORY_TYPE",
    ),
  ])
}

///|
test "pylock: [packages.archive] is a file record that has to say where it is" {
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nhashes = { sha256 = \"abc123\" }\nsize = 4096\nupload-time = 2025-01-25T11:30:10Z\nsubdirectory = \"python\"\n",
  )
  let archive = entry.archive.unwrap()
  assert_eq(archive.kind, ArchiveFile)
  assert_eq(archive.filename(), Some("spam-1.0.tar.gz"))
  assert_eq(archive.hash_for("sha256"), Some("abc123"))
  assert_eq(archive.size, Some(4096))
  assert_eq(archive.upload_time, Some("2025-01-25T11:30:10Z"))
  assert_eq(archive.subdirectory, Some("python"))
  assert_eq(entry.all_files().length(), 1)
  assert_entry_codes([
    (
      "name = \"spam\"\nversion = \"1.0\"\narchive = \"spam-1.0.tar.gz\"\n", "ARCHIVE_NOT_TABLE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nname = \"spam-1.0.tar.gz\"\nhashes = { sha256 = \"abc\" }\n",
      "ARCHIVE_URL_REQUIRED",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nsize = -1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_SIZE_NEGATIVE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nupload-time = \"2025-01-25T11:30:10Z\"\nhashes = { sha256 = \"abc\" }\n",
      "FILE_UPLOAD_TIME_TYPE",
    ),
  ])
}

///|
test "pylock: packages.index and packages.path are strings" {
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\nindex = \"https://pypi.org/simple/\"\n",
  )
  assert_eq(entry.index, Some("https://pypi.org/simple/"))
  assert_true(entry.path is None)
  // `path` is the draft spelling of a direct direct reference; a version is
  // therefore optional next to it.
  let direct = lock_entry(
    "name = \"spam\"\npath = \"dist/spam-1.0-py3-none-any.whl\"\n",
  )
  assert_eq(direct.path, Some("dist/spam-1.0-py3-none-any.whl"))
  assert_true(direct.version is None)
  assert_true(direct.is_direct_reference())
  assert_entry_codes([
    ("name = \"spam\"\nversion = \"1.0\"\nindex = 1\n", "INDEX_TYPE"),
    ("name = \"spam\"\nversion = \"1.0\"\npath = 1\n", "PATH_TYPE"),
  ])
}

///|
test "pylock: files entries carry name, url, path, hashes, size and upload-time" {
  let fields =
    #|name = "spam"
    #|version = "1.0"
    #|[[packages.files]]
    #|name = "spam-1.0-py3-none-any.whl"
    #|url = "https://example.invalid/dists/spam-1.0-py3-none-any.whl"
    #|hashes = { sha256 = "abc123", md5 = "def456" }
    #|size = 63152
    #|upload-time = 2025-01-25T11:30:10.164985+00:00
  let entry = lock_entry(fields)
  assert_eq(entry.files.length(), 1)
  let file = entry.files[0]
  assert_eq(file.kind, FilesEntry)
  assert_eq(file.name, Some("spam-1.0-py3-none-any.whl"))
  assert_eq(file.filename(), Some("spam-1.0-py3-none-any.whl"))
  assert_eq(file.hashes, [("sha256", "abc123"), ("md5", "def456")])
  assert_eq(file.hash_for("md5"), Some("def456"))
  assert_eq(file.hash_for("sha512"), None)
  assert_eq(file.size, Some(63152))
  assert_eq(file.upload_time, Some("2025-01-25T11:30:10.164985+00:00"))
  assert_true(file.subdirectory is None)
  assert_eq(entry.all_files().length(), 1)
  // The last component of `url` or `path` names the file when `name` is absent,
  // which the specification allows, with any query or fragment removed.
  let from_url = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nurl = \"https://example.invalid/dists/spam-1.0.tar.gz#sha256=abc\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(from_url.files[0].filename(), Some("spam-1.0.tar.gz"))
  let from_path = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\npath = \"dist/spam-1.0.tar.gz\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(from_path.files[0].filename(), Some("spam-1.0.tar.gz"))
  assert_eq(from_path.files[0].hashes, [("sha256", "abc")])
  assert_entry_codes([
    (
      "name = \"spam\"\nversion = \"1.0\"\nfiles = \"spam-1.0.tar.gz\"\n", "FILES_NOT_ARRAY",
    ),
    ("name = \"spam\"\nversion = \"1.0\"\nfiles = [1]\n", "FILE_NOT_TABLE"),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nhashes = { sha256 = \"abc\" }\n",
      "FILE_NAME_REQUIRED",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = 1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_NAME_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nurl = 1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_URL_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\npath = 1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_PATH_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nhashes = \"abc\"\n",
      "FILE_HASHES_NOT_TABLE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nhashes = { sha256 = 1 }\n",
      "FILE_HASH_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nsize = \"63152\"\nhashes = { sha256 = \"abc\" }\n",
      "FILE_SIZE_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nsize = -1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_SIZE_NEGATIVE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nupload-time = \"2025-01-25T11:30:10Z\"\nhashes = { sha256 = \"abc\" }\n",
      "FILE_UPLOAD_TIME_TYPE",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nsubdirectory = 1\nhashes = { sha256 = \"abc\" }\n",
      "FILE_SUBDIRECTORY_TYPE",
    ),
  ])
}

///|
test "pylock: a hashes table must hold at least one entry when it is present" {
  assert_entry_codes([
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nhashes = {}\n",
      "FILE_HASHES_EMPTY",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[[packages.wheels]]\nname = \"spam-1.0-py3-none-any.whl\"\nhashes = {}\n",
      "FILE_HASHES_EMPTY",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.sdist]\nname = \"spam-1.0.tar.gz\"\nhashes = {}\n",
      "FILE_HASHES_EMPTY",
    ),
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nhashes = {}\n",
      "FILE_HASHES_EMPTY",
    ),
  ])
  // The specification requires `hashes` on all three of them -- `Required? : yes`,
  // "The table MUST contain at least one entry" -- and this reader enforces both
  // halves now: a record with no table, and a table with no entry, are different
  // rejections. A record that carries one is read as before.
  assert_lock_error(
    lock_document(
      "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[packages.sdist]\nname = \"spam-1.0.tar.gz\"\n",
    ),
    "FILE_HASHES_REQUIRED",
  )
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[packages.sdist]\nname = \"spam-1.0.tar.gz\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(entry.sdist.unwrap().hashes, [("sha256", "abc")])
}

///|
test "pylock: wheels is an array of tables and sdist is one table" {
  let fields =
    #|name = "numpy"
    #|version = "2.2.3"
    #|[[packages.wheels]]
    #|name = "numpy-2.2.3-cp312-cp312-win_amd64.whl"
    #|hashes = { sha256 = "83807d445817326b4bcdaaaf8e8e9f1753da04341eceec705c001ff342002e5d" }
    #|[[packages.wheels]]
    #|name = "numpy-2.2.3-cp312-cp312-manylinux_2_17_x86_64.whl"
    #|hashes = { sha256 = "abc" }
    #|[packages.sdist]
    #|name = "numpy-2.2.3.tar.gz"
    #|hashes = { sha256 = "abc123" }
  let entry = lock_entry(fields)
  assert_eq(entry.wheels.length(), 2)
  assert_eq(entry.wheels[0].kind, WheelFile)
  assert_eq(entry.sdist.unwrap().kind, SdistFile)
  // `all_files` is `files`, then `sdist`, then `wheels`, then `archive`.
  assert_eq(entry.all_files().length(), 3)
  assert_eq(entry.all_files()[0].filename(), Some("numpy-2.2.3.tar.gz"))
  assert_eq(
    entry.all_files()[1].filename(),
    Some("numpy-2.2.3-cp312-cp312-win_amd64.whl"),
  )
  assert_eq(entry.all_files()[2].kind, WheelFile)
  assert_entry_codes([
    (
      "name = \"numpy\"\nversion = \"1.0\"\nwheels = \"numpy-1.0.whl\"\n", "WHEELS_NOT_ARRAY",
    ),
    ("name = \"numpy\"\nversion = \"1.0\"\nwheels = [1]\n", "FILE_NOT_TABLE"),
    (
      "name = \"numpy\"\nversion = \"1.0\"\nsdist = \"numpy-1.0.tar.gz\"\n", "SDIST_NOT_TABLE",
    ),
  ])
}

///|
test "pylock: the example from PEP 751 parses" {
  let lock = lock_of(pep751_example())
  assert_eq(lock.lock_version(), "1.0")
  assert_eq(lock.created_by(), "mousebender")
  assert_eq(lock.environments(), [
    "sys_platform == 'win32'", "sys_platform == 'linux'",
  ])
  assert_eq(lock.requires_python(), Some("==3.12"))
  assert_eq(lock.packages().length(), 3)
  assert_eq(lock.packages()[0].name, "attrs")
  assert_eq(lock.packages()[1].name, "cattrs")
  assert_eq(lock.packages()[2].name, "numpy")
  assert_eq(lock.packages()[0].requires_python, Some(">=3.8"))
  assert_eq(lock.packages()[0].version.unwrap().to_string(), "25.1.0")
  assert_eq(lock.packages()[1].version.unwrap().to_string(), "24.1.2")
  assert_eq(lock.packages()[2].version.unwrap().to_string(), "2.2.3")
  assert_eq(lock.dependencies_of("cattrs").length(), 1)
  assert_eq(lock.dependencies_of("cattrs")[0].name, "attrs")
  assert_eq(lock.files_for("attrs").length(), 1)
  assert_eq(lock.files_for("cattrs").length(), 1)
  assert_eq(lock.files_for("numpy").length(), 2)
  let attrs = lock.files_for("attrs")[0]
  assert_eq(attrs.kind, WheelFile)
  assert_eq(attrs.filename(), Some("attrs-25.1.0-py3-none-any.whl"))
  assert_eq(attrs.size, Some(63152))
  assert_eq(attrs.upload_time, Some("2025-01-25T11:30:10.164985+00:00"))
  assert_eq(
    attrs.hash_for("sha256"),
    Some("c75a69e28a550a7e93789579c22aa26b0f5b83b75dc4e08fe092980051e1090a"),
  )
  assert_eq(lock.files_for("numpy")[1].size, Some(16116679))
  // The `[tool]` table, `[[packages.attestation-identities]]` and the unknown
  // keys they carry are ignored rather than rejected.
  assert_eq(lock.packages()[0].files, [])
  assert_true(
    lock.accepts_environment(marker_environment_of([("sys_platform", "linux")])),
  )
}

///|
test "pylock: the accessors look a name up under PEP 503 normalization" {
  let fields =
    #|name = "Zope.Interface"
    #|version = "5.0"
    #|dependencies = [{ name = "setuptools" }]
    #|[[packages.wheels]]
    #|name = "zope_interface-5.0-cp312-cp312-linux_x86_64.whl"
    #|hashes = { sha256 = "abc" }
  let text = lock_document(
    "\n[[packages]]\n" +
    fields +
    "\n\n[[packages]]\nname = \"setuptools\"\nversion = \"68.0\"\n",
  )
  let lock = lock_of(text)
  assert_eq(lock.packages_named("zope-interface").length(), 1)
  assert_eq(lock.packages_named("Zope.Interface").length(), 1)
  assert_eq(lock.packages_named("ZOPE_INTERFACE")[0].name, "Zope.Interface")
  assert_eq(lock.packages_named("nothing"), [])
  assert_eq(lock.files_for("zope.interface").length(), 1)
  assert_eq(
    lock.files_for("zope.interface")[0].filename(),
    Some("zope_interface-5.0-cp312-cp312-linux_x86_64.whl"),
  )
  assert_eq(lock.files_for("nothing"), [])
  assert_eq(lock.dependencies_of("Zope.Interface")[0].name, "setuptools")
  assert_eq(lock.dependencies_of("nothing"), [])
  // `name` wins over the last component of `url` when both are present.
  let named = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nurl = \"https://example.invalid/other/file.tar.gz\"\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(named.files[0].filename(), Some("spam-1.0.tar.gz"))
}

///|
test "pylock: is_applicable, applicable_packages and accepts_environment" {
  let text =
    #|lock-version = "1.0"
    #|created-by = "moon-pyversion"
    #|environments = ["sys_platform == 'linux'"]
    #|
    #|[[packages]]
    #|name = "spam"
    #|version = "1.0"
    #|marker = "sys_platform == 'linux'"
    #|
    #|[[packages]]
    #|name = "spam"
    #|version = "1.0"
    #|marker = "sys_platform == 'win32'"
    #|
    #|[[packages]]
    #|name = "eggs"
    #|version = "2.0"
    #|marker = "'docs' in extras"
    #|
    #|[[packages]]
    #|name = "ham"
    #|version = "3.0"
  let lock = lock_of(text)
  let linux = marker_environment_of([("sys_platform", "linux")])
  let windows = marker_environment_of([("sys_platform", "win32")])
  assert_true(lock.is_applicable("spam", linux))
  assert_true(lock.is_applicable("spam", windows))
  assert_false(lock.is_applicable("nothing", linux))
  let applicable = lock.applicable_packages(linux)
  assert_eq(applicable.length(), 2)
  assert_eq(applicable[0].name, "spam")
  assert_eq(applicable[1].name, "ham")
  assert_true(lock.accepts_environment(linux))
  assert_false(lock.accepts_environment(windows))
  // A set-valued marker is evaluated against the extras (and dependency groups)
  // the caller says were requested, which is what a PEP 751 `marker` may test.
  let with_extras = marker_environment_of([("sys_platform", "linux")])
  with_extras.set_names("extras", ["docs"])
  assert_true(lock.is_applicable("eggs", with_extras))
  assert_false(lock.is_applicable("eggs", linux))
  let no_environments = lock_of(lock_document("packages = []\n"))
  assert_true(no_environments.accepts_environment(marker_environment_of([])))
}

///|
test "pylock: is_applicable reports an environment key it was not given" {
  let entry = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\nmarker = \"python_version >= '3.8'\"\n",
  )
  let empty = MarkerEnvironment::new()
  let raised = try {
    ignore(entry.is_applicable(empty))
    false
  } catch {
    UndefinedEnvironmentName(_) => true
    _ => false
  }
  assert_true(raised)
  let given = try {
    ignore(
      entry.is_applicable(marker_environment_of([("python_version", "3.12")])),
    )
    false
  } catch {
    _ => true
  }
  assert_false(given)
}

///|
test "pylock: text that is not TOML is an InvalidToml, not an InvalidPylock" {
  let broken = try {
    ignore(Pylock::parse("lock-version = \n"))
    "<accepted>"
  } catch {
    VersionError::InvalidToml(code, _) => code
    VersionError::InvalidPylock(code, _) => "pylock:\{code}"
    other => "unexpected:\{other.diagnostic()}"
  }
  assert_false(broken == "<accepted>")
  assert_false(broken == "pylock:TOML_INVALID")
  assert_true(lock_error("[[packages]\nname = \"spam\"\n") != "<accepted>")
}

///|
test "pylock: unknown keys are ignored, as a forward-compatible reader must" {
  let text =
    #|lock-version = "1.0"
    #|created-by = "moon-pyversion"
    #|future-key = "from a later minor version"
    #|
    #|[[packages]]
    #|name = "spam"
    #|version = "1.0"
    #|tool = { future = true }
    #|[[packages.attestation-identities]]
    #|environment = "release-pypi"
    #|kind = "GitHub"
    #|[[packages.dependencies]]
    #|name = "eggs"
    #|future-key = 1
    #|[[packages.wheels]]
    #|name = "spam-1.0-py3-none-any.whl"
    #|future-key = 1
    #|
    #|hashes = { sha256 = "abc" }
    #|[tool.moonpyversion]
    #|inputs = ["pyproject.toml"]
  let lock = lock_of(text)
  assert_eq(lock.packages().length(), 1)
  assert_eq(lock.packages()[0].dependencies[0].name, "eggs")
  assert_eq(lock.packages()[0].wheels.length(), 1)
  assert_eq(
    lock.files_for("spam")[0].filename(),
    Some("spam-1.0-py3-none-any.whl"),
  )
}

///|
test "pylock: the settled rules, and the one divergence that remains" {
  // 1. A `version` next to a source tree is rejected: "The version MUST NOT be
  //    included when it cannot be guaranteed to be consistent with the code used
  //    (i.e. when a source tree is used)". This used to be a declared divergence.
  assert_entry_codes([
    (
      "name = \"spam\"\nversion = \"1.0\"\n[packages.directory]\npath = \"../spam\"\n",
      "PACKAGE_VERSION_NOT_ALLOWED",
    ),
  ])
  // 2. `upload-time` is *recorded* verbatim -- `Z` is not rewritten to `+00:00` or
  //    the other way round -- but it now has to be UTC, which is the
  //    specification's own MUST. Both UTC spellings are accepted, a local datetime
  //    and a non-zero offset are not.
  let zulu = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nupload-time = 2025-01-25T11:30:10Z\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(zulu.files[0].upload_time, Some("2025-01-25T11:30:10Z"))
  let offset = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nupload-time = 2025-01-25T11:30:10.164985+00:00\nhashes = { sha256 = \"abc\" }\n",
  )
  assert_eq(
    offset.files[0].upload_time,
    Some("2025-01-25T11:30:10.164985+00:00"),
  )
  assert_codes([
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nupload-time = 2025-01-25T11:30:10-07:00\nhashes = { sha256 = \"abc\" }\n",
      ),
      "FILE_UPLOAD_TIME_NOT_UTC",
    ),
    (
      lock_document(
        "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nupload-time = 2025-01-25T11:30:10\nhashes = { sha256 = \"abc\" }\n",
      ),
      "FILE_UPLOAD_TIME_NOT_UTC",
    ),
  ])
  // 3. Hash algorithm names are compared verbatim. The specification says the keys
  //    SHOULD be lowercase, which is guidance for a writer rather than a rule a
  //    reader can enforce, so no normalization happens -- and this is not a
  //    divergence, it is the specification's own "SHOULD".
  let mixed_case = lock_entry(
    "name = \"spam\"\nversion = \"1.0\"\n[[packages.files]]\nname = \"spam-1.0.tar.gz\"\nhashes = { SHA256 = \"abc123\" }\n",
  )
  assert_eq(mixed_case.files[0].hash_for("SHA256"), Some("abc123"))
  assert_eq(mixed_case.files[0].hash_for("sha256"), None)
  // 4. A name is not required to be normalized -- PEP 685 normalization is a
  //    writer's job -- and an empty marker counts as an absent one.
  let unnormalized = lock_entry(
    "name = \"Zope_Interface\"\nversion = \"5.0\"\nmarker = \"\"\n",
  )
  assert_eq(unnormalized.name, "Zope_Interface")
  assert_true(unnormalized.marker is None)
  assert_true(unnormalized.is_applicable(marker_environment_of([])))
  // 5. The one divergence that remains: a `lock-version` whose minor version this
  //    reader does not implement is rejected, where the specification asks for a
  //    warning. There is no warning channel, and accepting a file whose meaning the
  //    reader cannot vouch for would be worse than rejecting it. Everything else
  //    that used to be listed here is enforced now, and the corpus pins each of
  //    those rules with ordinary records.
  assert_codes([
    (
      "lock-version = \"1.1\"\ncreated-by = \"x\"\npackages = []\n", "LOCK_VERSION_INVALID",
    ),
    (
      "lock-version = \"2.0\"\ncreated-by = \"x\"\npackages = []\n", "LOCK_VERSION_INVALID",
    ),
  ])
}

///|
test "pylock: two entries for one name are both kept" {
  let text =
    #|lock-version = "1.0"
    #|created-by = "moon-pyversion"
    #|
    #|[[packages]]
    #|name = "attrs"
    #|version = "24.2.0"
    #|marker = "python_version < '3.9'"
    #|[[packages.wheels]]
    #|name = "attrs-24.2.0-py3-none-any.whl"
    #|
    #|hashes = { sha256 = "abc" }
    #|[[packages]]
    #|name = "attrs"
    #|version = "25.1.0"
    #|marker = "python_version >= '3.9'"
    #|[[packages.wheels]]
    #|name = "attrs-25.1.0-py3-none-any.whl"
    #|hashes = { sha256 = "abc" }
  let lock = lock_of(text)
  assert_eq(lock.packages().length(), 2)
  assert_eq(lock.packages_named("attrs").length(), 2)
  // Both entries contribute files, in document order: deciding which one applies
  // is the caller's job, and `is_applicable` is the helper for it.
  assert_eq(lock.files_for("attrs").length(), 2)
  assert_eq(
    lock.files_for("attrs")[0].filename(),
    Some("attrs-24.2.0-py3-none-any.whl"),
  )
  assert_eq(
    lock.files_for("attrs")[1].filename(),
    Some("attrs-25.1.0-py3-none-any.whl"),
  )
  let old = marker_environment_of([("python_version", "3.8")])
  let new = marker_environment_of([("python_version", "3.12")])
  assert_eq(
    lock.applicable_packages(old)[0].version.unwrap().to_string(),
    "24.2.0",
  )
  assert_eq(
    lock.applicable_packages(new)[0].version.unwrap().to_string(),
    "25.1.0",
  )
  assert_true(lock.is_applicable("attrs", old))
  assert_true(lock.is_applicable("attrs", new))
}

///|
test "pylock: the position of an error is the entry ordinal" {
  let document = lock_document(
    "\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n\n[[packages]]\nname = \"cattrs\"\nversion = \"24.1.2\"\ndependencies = [{ name = \"cattrs\" }]\n\n[[packages]]\nname = \"numpy\"\n",
  )
  assert_lock_error_at(document, "DEPENDENCY_SELF_REFERENCE", 1)
  let broken_files = lock_document(
    "\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n\n[[packages]]\nname = \"cattrs\"\nversion = \"24.1.2\"\n[[packages.wheels]]\nname = \"cattrs-24.1.2-py3-none-any.whl\"\nhashes = {}\n",
  )
  assert_lock_error_at(broken_files, "FILE_HASHES_EMPTY", 1)
  // A document-level problem is position 0.
  assert_lock_error_at(lock_document(""), "PACKAGES_REQUIRED", 0)
  assert_lock_error_at("lock-version = \"1.1\"\n", "LOCK_VERSION_INVALID", 0)
}
