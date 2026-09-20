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
  demo_lock_file(version, version, "aa")
}

///|
fn demo_lock_file(
  version : String,
  file_version : String,
  hash : String,
) -> String {
  "lock-version = \"1.0\"\n" +
  "environments = [\"sys_platform == 'linux'\"]\n" +
  "requires-python = \">=3.9\"\n" +
  "created-by = \"audit-test\"\n" +
  "[[packages]]\nname = \"demo-pkg\"\nversion = \"" +
  version +
  "\"\nwheels = [{name = \"demo_pkg-" +
  file_version +
  "-py3-none-any.whl\", url = \"https://example.invalid/demo.whl\", hashes = {sha256 = \"" +
  hash +
  "\"}}]\n"
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
test "package audit selects the locked version even when the index has a newer one" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.1"),
    demo_index(),
    demo_lock("1.1"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Ready)
  assert_eq(report.selected_file, Some("demo_pkg-1.1-py3-none-any.whl"))
  assert_eq(report.issues, [])
}

///|
test "package audit reports metadata drift from the locked selection" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
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
      subject: "1.2 != 1.1",
    }),
  )
}

///|
test "package audit refuses a lock file with a different digest" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock_file("1.2", "1.2", "different"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "LOCK_SHA256_MISMATCH",
      subject: "demo_pkg-1.2-py3-none-any.whl",
    }),
  )
}

///|
test "package audit refuses a selected file absent from the lock" {
  let report = audit_package(
    "demo-pkg>=1,<2",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock_file("1.2", "1.1", "aa"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_true(
    report.issues.contains(AuditIssue::{
      code: "LOCK_FILE_MISSING",
      subject: "demo_pkg-1.2-py3-none-any.whl",
    }),
  )
}

///|
fn bundle_lock() -> String {
  demo_lock("1.2") +
  "[[packages]]\nname = \"other-pkg\"\nversion = \"2.0\"\nwheels = [{name = \"other_pkg-2.0-py3-none-any.whl\", url = \"https://example.invalid/other.whl\", hashes = {sha256 = \"bb\"}}]\n"
}

///|
fn other_audit_input() -> AuditInput {
  {
    requirement_text: "Other_Pkg==2.0",
    metadata_text: "Metadata-Version: 2.4\nName: other-pkg\nVersion: 2.0\n",
    index_json: "{\"meta\":{\"api-version\":\"1.1\"},\"name\":\"other-pkg\",\"files\":[{\"filename\":\"other_pkg-2.0-py3-none-any.whl\",\"url\":\"https://example.invalid/other.whl\",\"hashes\":{\"sha256\":\"BB\"}}]}",
  }
}

///|
fn demo_audit_input() -> AuditInput {
  {
    requirement_text: "Demo_Pkg>=1,<2",
    metadata_text: demo_metadata("1.2"),
    index_json: demo_index(),
  }
}

///|
test "bundle audits two projects against one lock and accepts hex case" {
  let bundle = audit_bundle(
    [demo_audit_input(), other_audit_input()],
    bundle_lock(),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
    require_lock_coverage=true,
  )
  assert_eq(bundle.disposition(), Ready)
  assert_eq(bundle.counts(), (2, 0, 0))
  assert_eq(bundle.issues, [])
  assert_true(bundle.render().contains("bundle: 2 package(s), ready=2"))
}

///|
test "bundle reports a duplicate canonical project input" {
  let bundle = audit_bundle(
    [demo_audit_input(), demo_audit_input()],
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(bundle.disposition(), Blocked)
  assert_eq(bundle.counts(), (2, 0, 0))
  assert_eq(bundle.issues, [
    AuditIssue::{ code: "DUPLICATE_PROJECT_INPUT", subject: "demo-pkg", },
  ])
}

///|
test "bundle full coverage reports a lock entry without an input" {
  let bundle = audit_bundle(
    [demo_audit_input()],
    bundle_lock(),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
    require_lock_coverage=true,
  )
  assert_eq(bundle.disposition(), Blocked)
  assert_eq(bundle.issues, [
    AuditIssue::{ code: "LOCK_ENTRY_UNAUDITED", subject: "other-pkg", },
  ])
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
test "package audit redacts credentials in a direct URL requirement" {
  let report = audit_package(
    "demo-pkg @ https://example.invalid/demo.whl?token=secret",
    demo_metadata("1.2"),
    demo_index(),
    demo_lock("1.2"),
    audit_environment(),
    "3.11.9",
    ["py3-none-any"],
  )
  assert_eq(report.disposition(), Blocked)
  assert_eq(report.requirement, "demo-pkg @ [redacted]")
  assert_true(!report.render().contains("secret"))
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
