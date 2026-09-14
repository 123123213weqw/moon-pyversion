///|
fn audit_environment() -> MarkerEnvironment {
  let environment = MarkerEnvironment::new()
  environment.set("python_version", "3.11")
  environment.set("python_full_version", "3.11.9")
  environment.set("sys_platform", "linux")
  environment
}

///|
fn demo_metadata(version : String) -> String {
  "Metadata-Version: 2.4\nName: Demo_Pkg\nVersion: " +
  version +
  "\nRequires-Python: >=3.9\nLicense-Expression: MIT\n"
}

///|
fn demo_index(with_hash? : Bool = true) -> String {
  let hash = if with_hash { "\"sha256\":\"aa\"" } else { "" }
  "{\"meta\":{\"api-version\":\"1.1\"},\"name\":\"demo-pkg\",\"files\":[" +
  "{\"filename\":\"demo_pkg-1.1-py3-none-any.whl\",\"url\":\"https://example.invalid/1.1.whl\",\"hashes\":{" +
  hash +
  "},\"requires-python\":\">=3.9\"}," +
  "{\"filename\":\"demo_pkg-1.2-py3-none-any.whl\",\"url\":\"https://example.invalid/1.2.whl\",\"hashes\":{" +
  hash +
  "},\"requires-python\":\">=3.9\"}," +
  "{\"filename\":\"demo_pkg-1.3-py3-none-any.whl\",\"url\":\"https://example.invalid/1.3.whl\",\"hashes\":{\"sha256\":\"cc\"},\"yanked\":\"broken\"}]," +
  "\"versions\":[\"1.1\",\"1.2\",\"1.3\"]}"
}

///|
fn demo_lock(version : String) -> String {
  "lock-version = \"1.0\"\n" +
  "environments = [\"sys_platform == 'linux'\"]\n" +
  "requires-python = \">=3.9\"\n" +
  "created-by = \"audit-test\"\n" +
  "[[packages]]\nname = \"demo-pkg\"\nversion = \"" +
  version +
  "\"\nwheels = [{name = \"demo_pkg-" +
  version +
  "-py3-none-any.whl\", url = \"https://example.invalid/demo.whl\", hashes = {sha256 = \"aa\"}}]\n"
}

///|
test "package audit joins metadata index lock and target into one ready decision" {
  let report = audit_package(
    "Demo_Pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Ready)
  assert_eq(report.project, "demo-pkg")
  assert_eq(report.index_files, 3)
  assert_eq(report.yanked_files, 1)
  assert_eq(report.candidates.length(), 2)
  assert_eq(report.selected_file, Some("demo_pkg-1.2-py3-none-any.whl"))
  assert_eq(report.lock_versions, ["1.2"])
  assert_eq(report.issues, [])
  assert_true(report.render().contains("disposition: ready"))
  assert_true(report.render().contains("selected: demo_pkg-1.2"))
}

///|
test "package audit reports cross-document version drift" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.1"),
    demo_index(),
    demo_lock("1.1"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "METADATA_SELECTION_MISMATCH",
      subject: "1.1 != 1.2",
    }),
  )
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "LOCK_SELECTION_MISMATCH",
      subject: "1.1 != 1.2",
    }),
  )
}

///|
test "package audit requires a selected sha256 digest" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(with_hash=false),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "SELECTED_SHA256_MISSING",
      subject: "demo_pkg-1.2-py3-none-any.whl",
    }),
  )
}

///|
test "a requirement excluded by its marker is not required" {
  let report = audit_package(
    "demo-pkg>=1; sys_platform == 'win32'",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), NotRequired)
  assert_eq(report.applicable, false)
  assert_eq(report.selected_file, None)
}

///|
test "package audit refuses a target with no compatible wheel tag" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["cp311-cp311-win_amd64"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "CANDIDATE_MISSING",
      subject: "demo-pkg",
    }),
  )
}

///|
test "direct URL requirement is kept outside index selection" {
  let report = audit_package(
    "demo-pkg @ https://example.invalid/demo.whl",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "DIRECT_URL_NOT_INDEXED",
      subject: "demo-pkg",
    }),
  )
  assert_eq(report.selected_file, None)
}

///|
test "multiple applicable lock entries are reported as ambiguous" {
  let second = "[[packages]]\nname = \"demo-pkg\"\nversion = \"1.1\"\nwheels = [{name = \"demo_pkg-1.1-py3-none-any.whl\", url = \"https://example.invalid/1.1.whl\", hashes = {sha256 = \"bb\"}}]\n"
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2") + second,
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "LOCK_ENTRY_AMBIGUOUS",
      subject: "demo-pkg",
    }),
  )
  assert_eq(report.lock_versions, ["1.2", "1.1"])
}

///|
test "real PyPI Flask metadata participates in an end-to-end audit" {
  let mut flask = ""
  for (name, document) in @fixtures.metadata_pypi_cases {
    if name == "flask-0.12.5" {
      flask = document
    }
  }
  assert_true(!flask.is_empty())
  let index = "{\"meta\":{\"api-version\":\"1.1\"},\"name\":\"Flask\",\"files\":[{\"filename\":\"Flask-0.12.5-py3-none-any.whl\",\"url\":\"https://files.pythonhosted.org/example.whl\",\"hashes\":{\"sha256\":\"0123456789abcdef\"},\"requires-python\":\">=2.6\"}]}"
  let lock = "lock-version = \"1.0\"\ncreated-by = \"audit-test\"\n[[packages]]\nname = \"Flask\"\nversion = \"0.12.5\"\nwheels = [{name = \"Flask-0.12.5-py3-none-any.whl\", url = \"https://files.pythonhosted.org/example.whl\", hashes = {sha256 = \"0123456789abcdef\"}}]\n"
  let report = audit_package(
    "Flask==0.12.5",
    flask,
    index,
    lock,
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Ready)
  assert_eq(report.metadata_name, "Flask")
  assert_eq(report.selected_version, Some("0.12.5"))
  assert_eq(report.issues, [])
}
