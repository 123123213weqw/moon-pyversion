///|
test "from_toml reads the PEP 621 table with refusal discipline" {
  let doc = @moon_pyversion.Toml::parse(
    "[project]\nname = \"Demo-Project\"\nrequires-python = \">=3.9\"\ndependencies = [\"foo>=1.0,<2\", \"bar~=1.4; python_version >= '3.8'\"]\n[project.optional-dependencies]\ncsv = [\"baz==1.0\"]\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  // Name is canonicalized.
  let name = match project.name {
    Some(n) => n
    None => "missing"
  }
  assert_eq(name, "demo-project")
  // Base dependencies parsed with markers intact.
  assert_eq(project.dependencies.length(), 2)
  // requires-python present and parsed.
  let has_spec = match project.requires_python {
    Some(_) => true
    None => false
  }
  assert_eq(has_spec, true)
  // The extra is keyed canonical.
  let extra_list = match project.optional.get("csv") {
    Some(list) => list
    None => []
  }
  assert_eq(extra_list.length(), 1)
  // A malformed dependency refuses the whole read, naming the entry.
  let broken = Some(
    @moon_pyversion.Toml::parse(
      "[project]\nname = \"x\"\ndependencies = [\"foo >>=\" ]\n",
    ),
  ) catch {
    _ => None
  }
  let refused = match broken {
    None => true
    Some(doc2) =>
      match
        (Some(@moon_pyversion.PyProject::from_toml(doc2)) catch { _ => None }) {
        None => true
        Some(_) => false
      }
  }
  assert_eq(refused, true)
  // No [project] table: named refusal.
  let no_table = Some(@moon_pyversion.Toml::parse("[tool.other]\nkey = 1\n")) catch {
    _ => None
  }
  let refused2 = match no_table {
    None => true
    Some(doc3) =>
      match
        (Some(@moon_pyversion.PyProject::from_toml(doc3)) catch { _ => None }) {
        None => true
        Some(_) => false
      }
  }
  assert_eq(refused2, true)
}

///|
test "with_extra appends the declared extra, refuses the undeclared" {
  let doc = @moon_pyversion.Toml::parse(
    "[project]\nname = \"demo\"\ndependencies = [\"foo>=1.0\"]\n[project.optional-dependencies]\ncsv = [\"baz==1.0\"]\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  let with_csv = project.with_extra("CSV")
  assert_eq(with_csv.length(), 2)
  let undeclared = Some(project.with_extra("nope")) catch { _ => None }
  let refused = match undeclared {
    None => true
    Some(_) => false
  }
  assert_eq(refused, true)
}

///|
test "check_runtime names blockers across python gate and dependencies" {
  let doc = @moon_pyversion.Toml::parse(
    "[project]\nname = \"demo\"\nrequires-python = \">=3.11\"\ndependencies = [\"foo>=1.0,<2\", \"bar==1.0\"]\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  fn table(
    foo : String,
    bar : String,
  ) -> ((String) -> @moon_pyversion.Version?) raise {
    let v_foo = @moon_pyversion.Version::parse(foo)
    let v_bar = @moon_pyversion.Version::parse(bar)
    fn(name : String) -> @moon_pyversion.Version? {
      if name == "foo" {
        Some(v_foo)
      } else if name == "bar" {
        Some(v_bar)
      } else {
        None
      }
    }
  }
  // A satisfied runtime: python in range, both candidates in range.
  let ok = project.check_runtime(
    "3.11.4",
    "cpython",
    "linux",
    "x86_64",
    table("1.5", "1.0"),
  )
  let no_failures = match ok {
    None => true
    Some(_) => false
  }
  assert_eq(no_failures, true)
  // Old python: the requires-python gate is named first.
  let old_python = project.check_runtime(
    "3.9.1",
    "cpython",
    "linux",
    "x86_64",
    table("1.5", "1.0"),
  )
  let first_reason = match old_python {
    None => ""
    Some(items) => items[0].reason
  }
  assert_eq(first_reason, "python 3.9.1 not in >=3.11")
  // Candidate out of range: the dependency is the named blocker.
  let bad_foo = project.check_runtime(
    "3.11.4",
    "cpython",
    "linux",
    "x86_64",
    table("2.5", "1.0"),
  )
  let blocker = match bad_foo {
    None => ""
    Some(items) => items[0].requirement
  }
  assert_eq(blocker, "foo<2,>=1.0")
}
