///|
/// TEMPORARY STUB, replaced by the generator under tools/fetch_pylock_corpus.py.
pub let pylock_environment : Array[(String, String)] = [
  ("sys_platform", "linux"),
  ("python_version", "3.11"),
  ("extra", ""),
]

///|
pub let pylock_environment_sets : Array[(String, Array[String])] = [
  ("extras", []), ("dependency_groups", []),
]

///|
pub let pylock_cases : Array[(String, String, String)] = [
  ("01_minimal", "lock-version = \"1.0\"\ncreated-by = \"moon-pyversion\"\n\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n", "-"),
  ("02_vcs", "lock-version = \"1.0\"\ncreated-by = \"stub\"\n\n[[packages]]\nname = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"0f1e2d3c\"\n", "-"),
  ("03_deps_and_wheels", "lock-version = \"1.0\"\nenvironments = [\"sys_platform == 'linux'\"]\nrequires-python = \">=3.9\"\nextras = [\"docs\"]\ndependency-groups = [\"test\"]\ndefault-groups = [\"test\"]\ncreated-by = \"stub\"\n\n[[packages]]\nname = \"cattrs\"\nversion = \"24.1.2\"\nrequires-python = \">=3.8\"\ndependencies = [{ name = \"attrs\", version = \"25.1.0\", extras = [\"dev\"] }, { name = \"typing-extensions\", marker = \"python_version < '3.9'\" }]\n[[packages.wheels]]\nname = \"cattrs-24.1.2-py3-none-any.whl\"\nurl = \"https://example.invalid/cattrs-24.1.2-py3-none-any.whl\"\nh=1\n[packages.sdist]\nname = \"cattrs-24.1.2.tar.gz\"\nupload-time = 2025-01-25T11:30:10.164985+00:00\n[packages.sdist.hashes]\nsha256 = \"aa1b2c3d\"\n", "-"),
]

///|
pub let pylock_bad_cases : Array[(String, String)] = [
  ("90_version_missing", "lock-version = \"1.0\"\ncreated-by = \"stub\"\n\n[[packages]]\nname = \"attrs\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/x.git\"\ncommit-id = \"abc\"\n[packages.directory]\npath = \"../x\"\n"),
]

///|
pub let pylock_pypi_cases : Array[(String, String, String)] = []

///|
pub let pylock_divergences : Array[(String, Bool)] = []

///|
pub let pylock_divergence_cases : Array[(String, String)] = []

