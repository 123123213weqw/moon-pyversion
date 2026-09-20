///|
/// A two-project offline mirror audit. Both METADATA and PEP 691 responses
/// come from the checked-in PyPI corpus; only the PEP 751 lock is a small,
/// explicit scenario input. The wheel names and sha256 values in that lock
/// are copied from the committed index responses, not invented hashes.
fn main {
  let mut flask_metadata = ""
  let mut jinja_metadata = ""
  for (name, document) in @fixtures.metadata_pypi_cases {
    if name == "flask-0.12.5" {
      flask_metadata = document
    } else if name == "jinja2-2.10.1" {
      jinja_metadata = document
    }
  }
  let mut flask_index = ""
  let mut jinja_index = ""
  for (name, document, _projection) in @fixtures.index_pypi_cases {
    if name == "flask" {
      flask_index = document
    } else if name == "jinja2" {
      jinja_index = document
    }
  }
  if flask_metadata.is_empty() ||
    jinja_metadata.is_empty() ||
    flask_index.is_empty() ||
    jinja_index.is_empty() {
    abort("checked-in PyPI fixtures for the bundle are missing")
  }
  let lock = "lock-version = \"1.0\"\ncreated-by = \"bundle-audit-example\"\n" +
    "[[packages]]\nname = \"Flask\"\nversion = \"0.12.5\"\n" +
    "wheels = [{name = \"Flask-0.12.5-py2.py3-none-any.whl\", url = \"https://files.pythonhosted.org/example/flask.whl\", hashes = {sha256 = \"2c710d1d42317c802c43000daa16de9de6026146b344ab3376cbc6d18846b863\"}}]\n" +
    "[[packages]]\nname = \"Jinja2\"\nversion = \"2.10.1\"\n" +
    "wheels = [{name = \"Jinja2-2.10.1-py2.py3-none-any.whl\", url = \"https://files.pythonhosted.org/example/jinja2.whl\", hashes = {sha256 = \"14dd6caf1527abb21f08f86c784eac40853ba93edb79552aa1e4b8aef1b61c7b\"}}]\n"
  let environment = @pyversion.MarkerEnvironment::new()
  environment.set("python_version", "3.11")
  environment.set("python_full_version", "3.11.9")
  environment.set("sys_platform", "linux")
  let report = @pyversion.audit_bundle(
    [
      @pyversion.AuditInput::{
        requirement_text: "Flask==0.12.5",
        metadata_text: flask_metadata,
        index_json: flask_index,
      },
      @pyversion.AuditInput::{
        requirement_text: "Jinja2>=2.4",
        metadata_text: jinja_metadata,
        index_json: jinja_index,
      },
    ],
    lock,
    environment,
    "3.11.9",
    ["py3-none-any"],
    require_lock_coverage=true,
  ) catch {
    error => {
      println("bundle input rejected: " + error.to_string())
      abort("bundle input rejected")
    }
  }
  println(report.render())
  if report.disposition() != @pyversion.Ready {
    abort("two-package mirror audit must be ready")
  }
}
