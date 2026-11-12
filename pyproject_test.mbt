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

///|
fn build_index(
  name : String,
  files_json : String,
) -> @moon_pyversion.SimpleIndex raise {
  let doc = "{\"name\": \"" +
    name +
    "\", \"version\": \"1.0\", \"files\": " +
    files_json +
    "}"
  @moon_pyversion.SimpleIndex::parse(doc)
}

///|
test "plan_install is the micro-pip end to end" {
  let doc = @moon_pyversion.Toml::parse(
    "[project]\nname = \"demo\"\nrequires-python = \">=3.11\"\ndependencies = [\"foo>=1.0,<2\"]\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  // A good index: foo 1.5 wheel viable on this runtime.
  let foo_index = build_index(
    "foo", "[{\"filename\": \"foo-1.5-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"a\"}}]",
  )
  let indexes : Map[String, @moon_pyversion.SimpleIndex] = Map([])
  indexes["foo"] = foo_index
  // All green: python gate passes, foo 1.5 from the index passes.
  let plan = project.plan_install(
    indexes, "3.11.4", "cpython", "linux", "x86_64",
  )
  let all_ok = match plan {
    None => true
    Some(_) => false
  }
  assert_eq(all_ok, true)
  // Bad index: only a yanked file - no viable candidate, named.
  let bad_index = build_index(
    "foo", "[{\"filename\": \"foo-1.5-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"a\"}, \"yanked\": \"recall\"}]",
  )
  let bad_map : Map[String, @moon_pyversion.SimpleIndex] = Map([])
  bad_map["foo"] = bad_index
  let blocked = project.plan_install(
    bad_map, "3.11.4", "cpython", "linux", "x86_64",
  )
  let reason = match blocked {
    None => ""
    Some(items) => items[0].reason
  }
  // "no candidate" refined to "no viable file" when the index exists.
  assert_eq(reason.has_prefix("no viable file for foo"), true)
  // Missing index entirely: the plain no-candidate reason.
  let empty : Map[String, @moon_pyversion.SimpleIndex] = Map([])
  let missing = project.plan_install(
    empty, "3.11.4", "cpython", "linux", "x86_64",
  )
  let reason2 = match missing {
    None => ""
    Some(items) => items[0].reason
  }
  assert_eq(reason2, "no candidate for foo")
}

///|
test "from_toml reads build-system requires with refusal discipline" {
  let doc = @moon_pyversion.Toml::parse(
    "[build-system]\nrequires = [\"setuptools>=61.0\", \"wheel; os_name == 'nt'\"]\n[project]\nname = \"demo\"\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  assert_eq(project.build_requires.length(), 2)
  assert_eq(project.build_requires[0].name, "setuptools")
  assert_eq(project.build_requires[0].specifier.to_string(), ">=61.0")
  let marker = match project.build_requires[1].marker_text {
    Some(text) => text
    None => "missing"
  }
  assert_eq(marker, "os_name == 'nt'")
  // No [build-system] table: PEP 517's defaults apply, the list is empty.
  let bare = @moon_pyversion.PyProject::from_toml(
    @moon_pyversion.Toml::parse("[project]\nname = \"demo\"\n"),
  )
  assert_eq(bare.build_requires.length(), 0)
  // Table present, key absent: still empty.
  let no_key = @moon_pyversion.PyProject::from_toml(
    @moon_pyversion.Toml::parse(
      "[build-system]\nbuild-backend = \"setuptools.build_meta\"\n[project]\nname = \"demo\"\n",
    ),
  )
  assert_eq(no_key.build_requires.length(), 0)
  // requires is not an array: named refusal.
  ignore(
    @moon_pyversion.PyProject::from_toml(
      @moon_pyversion.Toml::parse(
        "[build-system]\nrequires = \"setuptools\"\n[project]\nname = \"demo\"\n",
      ),
    ),
  ) catch {
    @moon_pyversion.VersionError::InvalidRequirement(code, _) =>
      assert_eq(code, "BUILD_REQUIRES_NOT_ARRAY")
    other => abort("unexpected error \{other}")
  }
  // A non-string entry: its own named refusal.
  ignore(
    @moon_pyversion.PyProject::from_toml(
      @moon_pyversion.Toml::parse(
        "[build-system]\nrequires = [1]\n[project]\nname = \"demo\"\n",
      ),
    ),
  ) catch {
    @moon_pyversion.VersionError::InvalidRequirement(code, _) =>
      assert_eq(code, "NON_STRING_BUILD_REQUIRES")
    other => abort("unexpected error \{other}")
  }
  // A malformed requirement string refuses the whole read, as with the
  // runtime dependencies.
  let broken = Some(
    @moon_pyversion.PyProject::from_toml(
      @moon_pyversion.Toml::parse(
        "[build-system]\nrequires = [\"setuptools >>=\"]\n[project]\nname = \"demo\"\n",
      ),
    ),
  ) catch {
    _ => None
  }
  let refused = match broken {
    None => true
    Some(_) => false
  }
  assert_eq(refused, true)
}

///|
test "check_build_requires names blockers in the build table" {
  let doc = @moon_pyversion.Toml::parse(
    "[build-system]\nrequires = [\"setuptools>=64\", \"cython; python_version >= '3.11'\"]\n[project]\nname = \"demo\"\n",
  )
  let project = @moon_pyversion.PyProject::from_toml(doc)
  fn table(
    setuptools : String,
    cython : String,
  ) -> ((String) -> @moon_pyversion.Version?) raise {
    let v_setuptools = @moon_pyversion.Version::parse(setuptools)
    let v_cython = @moon_pyversion.Version::parse(cython)
    fn(name : String) -> @moon_pyversion.Version? {
      if name == "setuptools" {
        Some(v_setuptools)
      } else if name == "cython" {
        Some(v_cython)
      } else {
        None
      }
    }
  }
  // A satisfied build environment: setuptools in range, cython's marker on.
  let ok = project.check_build_requires(
    "3.11.4",
    "cpython",
    "linux",
    "x86_64",
    table("68.0", "3.0"),
  )
  let no_failures = match ok {
    None => true
    Some(_) => false
  }
  assert_eq(no_failures, true)
  // setuptools out of range: the named blocker with its constraint.
  let old = project.check_build_requires(
    "3.11.4",
    "cpython",
    "linux",
    "x86_64",
    table("61.0", "3.0"),
  )
  let blocker = match old {
    None => ("", "")
    Some(items) => (items[0].requirement, items[0].reason)
  }
  assert_eq(blocker.0, "setuptools>=64")
  assert_eq(blocker.1, "version not in >=64")
  // An older runtime switches cython's marker off: the named blocker.
  let marker_off = project.check_build_requires(
    "3.9.1",
    "cpython",
    "linux",
    "x86_64",
    table("68.0", "3.0"),
  )
  let marker_blocker = match marker_off {
    None => ("", "")
    Some(items) => (items[0].requirement, items[0].reason)
  }
  assert_eq(marker_blocker.0, "cython; python_version >= '3.11'")
  assert_eq(marker_blocker.1, "marker false: python_version >= '3.11'")
}
