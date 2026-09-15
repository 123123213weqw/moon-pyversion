///|
/// A reproducible cross-artifact audit. The METADATA document is a real PyPI
/// PEP 658 sidecar from the checked-in corpus; the index and lock are small,
/// explicit scenario inputs that make the expected selection inspectable.
fn main {
  let mut metadata = ""
  for (name, document) in @fixtures.metadata_pypi_cases {
    if name == "flask-0.12.5" {
      metadata = document
    }
  }
  if metadata.is_empty() {
    abort("checked-in Flask metadata fixture is missing")
  }
  let index = "{\"meta\":{\"api-version\":\"1.1\"},\"name\":\"Flask\",\"files\":[{\"filename\":\"Flask-0.12.5-py3-none-any.whl\",\"url\":\"https://files.pythonhosted.org/example.whl\",\"hashes\":{\"sha256\":\"0123456789abcdef\"},\"requires-python\":\">=2.6\"},{\"filename\":\"Flask-1.0-py3-none-any.whl\",\"url\":\"https://files.pythonhosted.org/yanked.whl\",\"hashes\":{\"sha256\":\"fedcba9876543210\"},\"yanked\":\"scenario exclusion\"}]}"
  let lock = "lock-version = \"1.0\"\ncreated-by = \"moon-pyversion-audit\"\n[[packages]]\nname = \"Flask\"\nversion = \"0.12.5\"\nwheels = [{name = \"Flask-0.12.5-py3-none-any.whl\", url = \"https://files.pythonhosted.org/example.whl\", hashes = {sha256 = \"0123456789abcdef\"}}]\n"
  let environment = @pyversion.MarkerEnvironment::new()
  environment.set("python_version", "3.11")
  environment.set("python_full_version", "3.11.9")
  environment.set("sys_platform", "linux")
  let report = @pyversion.audit_package(
    "Flask==0.12.5",
    metadata,
    index,
    lock,
    environment,
    "3.11.9",
    ["py3-none-any"],
  ) catch {
    error => abort("audit input rejected: " + error.to_string())
  }
  println(report.render())
  if report.disposition() != @pyversion.Ready {
    abort("scenario must be ready")
  }
}
