///|
/// Scenario 1, end to end: read project metadata, then answer "is every locked
/// dependency acceptable, and is this dependency even for me?".
///
/// The report has three parts per document:
///
/// 1. the document itself is parsed and validated, so a broken `METADATA` is
///    reported with its stable error code instead of being half-read;
/// 2. every `Requires-Dist` line is parsed as a PEP 508 requirement, and the
///    marker decides whether the requirement applies to the target environment
///    at all (a Windows-only dependency is not a problem on Linux, it is simply
///    not applicable);
/// 3. every applicable requirement is checked against the locked version with
///    `SpecifierSet::contains`.
///
/// ## Why the inputs are compiled in
///
/// The library depends on `moonbitlang/core` only, and that package has no
/// filesystem API, so a program cannot open `METADATA` or a lock file. Rather
/// than introduce a dependency (or a platform-specific shim) just for the
/// demonstration, this example takes its documents from the `fixtures` package
/// — the same 239 **real** `METADATA` files that the differential corpus uses,
/// taken from the PEP 658 `.metadata` sidecars of real PyPI wheels — and a small
/// `pylock.toml` document written out below. Swapping the two for a file or a
/// network response is the only change an application needs.
///
/// The lock file is not a stand-in table: it is parsed by this library's own
/// `Pylock::parse` (PEP 751), so the example also shows the lock-file half of the
/// picture — which locked projects apply to this environment at all, and which
/// were recorded for another target. A lock written for Windows is not a broken
/// lock on Linux; it is a lock for a different platform, and the report says so
/// instead of calling every entry in it a conflict.
///
/// Everything here is deterministic: no clock, no environment, no I/O. The
/// output is byte identical on wasm, wasm-gc, js and native.
///
/// ```sh
/// moon run examples/metadata-check --target js
/// ```

///|
/// The environment the markers are evaluated against. Deliberately explicit: the
/// library never reads the host process's environment, so a report produced on
/// one machine can be replayed on another and give the same answer.
fn target_environment() -> @pyversion.MarkerEnvironment {
  let environment = @pyversion.MarkerEnvironment::new()
  environment.set("python_version", "3.11")
  environment.set("python_full_version", "3.11.9")
  environment.set("os_name", "posix")
  environment.set("sys_platform", "linux")
  environment.set("platform_release", "6.1.0")
  environment.set("platform_system", "Linux")
  environment.set("platform_version", "#1 SMP")
  environment.set("platform_machine", "x86_64")
  environment.set("platform_python_implementation", "CPython")
  environment.set("implementation_name", "cpython")
  environment.set("implementation_version", "3.11.9")
  // the extra being requested from each distribution; `""` means "no extra"
  environment.set("extra", "test")
  environment
}

///|
/// What the report says about one dependency line.
enum Verdict {
  /// The requirement applies and the locked version satisfies it.
  Satisfied(String)
  /// The requirement applies and the locked version does not satisfy it.
  OutOfRange(String, String, String)
  /// The lock file does not mention the project at all.
  NotLocked(String)
  /// The marker excluded this requirement from the target environment.
  NotApplicable(String)
  /// The line is not a valid PEP 508 requirement.
  Unparsable(String, String)
}

///|
fn Verdict::render(self : Verdict) -> String {
  match self {
    Satisfied(text) => "ok            \{text}"
    OutOfRange(name, requirement, locked) =>
      "OUT OF RANGE  \{name}: locked \{locked}, needs \{requirement}"
    NotLocked(name) => "not locked    \{name}"
    NotApplicable(name) => "not applicable \{name}"
    Unparsable(name, code) => "UNPARSABLE    \{name}: \{code}"
  }
}

///|
/// Whether the verdict is a problem the caller has to act on. `NotApplicable`
/// and `NotLocked` are not: the first is by design, the second is a gap in the
/// lock file rather than a conflict.
fn Verdict::is_problem(self : Verdict) -> Bool {
  match self {
    OutOfRange(_, _, _) | Unparsable(_, _) => true
    Satisfied(_) | NotLocked(_) | NotApplicable(_) => false
  }
}

///|
/// Classify one `Requires-Dist` value against a lock table and an environment.
fn classify(
  raw : String,
  lock : Array[(String, String)],
  environment : @pyversion.MarkerEnvironment,
) -> Verdict {
  let requirement = @pyversion.Requirement::parse(raw) catch {
    @pyversion.VersionError::InvalidRequirement(code, _) =>
      return Unparsable(raw, code)
    _ => return Unparsable(raw, "INVALID_REQUIREMENT")
  }
  let key = @pyversion.canonicalize_name(requirement.name)
  // The marker decides applicability. A marker the environment cannot answer
  // (an undefined key) is reported as not applicable rather than guessed at.
  match requirement.marker_text {
    None => ()
    Some(text) => {
      let marker = @pyversion.Marker::parse(text) catch {
        _ => return Unparsable(raw, "INVALID_MARKER")
      }
      // An environment that cannot answer the marker reports "not applicable"
      // rather than guessing: the report is about a concrete target.
      let applies = marker.evaluate(environment) catch { _ => false }
      if !applies {
        return NotApplicable(key)
      }
    }
  }
  match lookup(lock, key) {
    None => NotLocked(key)
    Some(locked) => {
      let version = @pyversion.Version::parse(locked) catch {
        _ => return NotLocked(key)
      }
      let wanted = requirement.specifier.to_string()
      // An empty specifier means "any version", which is what `foo` without a
      // constraint means in PEP 508.
      let spelled = if wanted.is_empty() { "(any version)" } else { wanted }
      if requirement.specifier.contains(version) {
        Satisfied("\{key} \{locked} \{spelled}")
      } else {
        OutOfRange(key, spelled, locked)
      }
    }
  }
}

///|
/// The locked version of `name`, or `None` when the lock does not mention it.
fn lookup(lock : Array[(String, String)], name : String) -> String? {
  for entry in lock {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Report one metadata document: the document itself, then one line per
/// dependency, then a one-line summary. Returns the number of problems so the
/// caller can decide on an exit status.
fn report(
  name : String,
  document : String,
  lock : Array[(String, String)],
) -> Int {
  println("== \{name}")
  let metadata = @pyversion.Metadata::parse(document) catch {
    error => {
      println("   INVALID METADATA: \{error.diagnostic()}")
      return 1
    }
  }
  println(
    "   \{metadata.name} \{metadata.version.to_string()} (metadata \{metadata.metadata_version})",
  )
  match metadata.requires_python() {
    None => println("   requires-python: (none)")
    Some(specifiers) => {
      let interpreter = @pyversion.Version::parse("3.11.9") catch {
        _ => abort("3.11.9 must parse")
      }
      let allowed = specifiers.contains(interpreter)
      println(
        "   requires-python: \{specifiers.to_string()} -> \{if allowed { "3.11.9 is allowed" } else { "3.11.9 is NOT allowed" }}",
      )
    }
  }
  let warnings = metadata.diagnostics()
  if !warnings.is_empty() {
    for warning in warnings {
      println("   note: \{warning}")
    }
  }
  let problems : Array[Verdict] = []
  let requirements = metadata.requirements()
  let parsed = requirements.length()
  for raw in metadata.requires_dist {
    let verdict = classify(raw, lock, target_environment())
    println("   \{verdict.render()}")
    if verdict.is_problem() {
      problems.push(verdict)
    }
  }
  println(
    "   -> \{parsed}/\{metadata.requires_dist.length()} lines parsed, \{problems.length()} problem(s)",
  )
  problems.length()
}

///|
/// The lock file this report reads, as a `pylock.toml` document (PEP 751). It is
/// written out rather than fetched so the output is reproducible; the pinned
/// versions are the ones the report explains -- one that satisfies its
/// requirement, one that does not, one project that is only required on another
/// platform -- and the file records the target it was locked for through
/// `environments` and a per-package `marker`.
fn lock_document() -> String {
  let lines : Array[String] = [
    "lock-version = \"1.0\"",
    "environments = [\"sys_platform == 'linux'\"]",
    "extras = [\"test\"]",
    "dependency-groups = [\"docs\", \"lint\"]",
    "default-groups = [\"docs\"]",
    "created-by = \"moon-pyversion metadata-check\"",
    "",
    "[[packages]]",
    "name = \"requests\"",
    "version = \"2.31.0\"",
    "",
    "[[packages]]",
    "name = \"werkzeug\"",
    "version = \"2.0.0\"",
    "",
    "[[packages]]",
    "name = \"jinja2\"",
    "version = \"3.1.4\"",
    "",
    "[[packages]]",
    "name = \"click\"",
    "version = \"8.1.7\"",
    "",
    "[[packages]]",
    "name = \"pytest\"",
    "version = \"8.3.5\"",
    "",
    "[[packages]]",
    "name = \"markupsafe\"",
    "version = \"2.1.5\"",
    "",
    "[[packages]]",
    "name = \"itsdangerous\"",
    "version = \"2.2.0\"",
    "",
    "[[packages]]",
    "name = \"blinker\"",
    "version = \"1.8.2\"",
    "",
    "[[packages]]",
    "name = \"colorama\"",
    "version = \"0.4.6\"",
    "marker = \"sys_platform == 'win32'\"",
    "",
    "[[packages]]",
    "name = \"demo-linux-only\"",
    "version = \"1.0.0\"",
    "marker = \"sys_platform == 'linux' and python_version >= '3.8'\"",
    "",
  ]
  lines.join("\n")
}

///|
/// The locked projects that apply to `environment`, as `(normalized name,
/// version)`, in document order, plus the number of entries the lock records for
/// another target.
///
/// The document is parsed with `Pylock::parse`, and applicability is the lock's
/// own question: an entry recorded for another platform is *not applicable*
/// here, which is why it is not reported as a missing or conflicting
/// requirement. An entry without a marker applies everywhere.
fn applicable_lock(
  document : String,
  environment : @pyversion.MarkerEnvironment,
) -> (Array[(String, String)], Int) {
  let lock = @pyversion.Pylock::parse(document) catch {
    _ => abort("the lock document this example compiles in must parse")
  }
  let table : Array[(String, String)] = []
  let mut skipped = 0
  for entry in lock.packages() {
    let applies = entry.is_applicable(environment) catch { _ => false }
    match entry.version {
      Some(version) =>
        if applies {
          table.push((
            @pyversion.canonicalize_name(entry.name),
            version.to_string(),
          ))
        } else {
          skipped = skipped + 1
        }
      None => ()
    }
  }
  (table, skipped)
}

///|
/// The documents the report runs on, named explicitly so the output is fixed.
/// All four are real `METADATA` files taken from PyPI wheels, and each one shows
/// a different part of the report:
///
/// - `flask-0.12.5` requires `werkzeug<1.0,>=0.7`, which the lock's 2.0.0 does
///   not satisfy: a real out-of-range conflict;
/// - `alembic-1.5.8` declares
///   `Requires-Python: !=3.0.*,...,>=2.7`, which the target interpreter 3.11.9
///   satisfies, so the interpreter check runs and passes;
/// - `requests-2.24.0` declares `Metadata-Version: 2.0`, which is not a version
///   the core metadata specification defines, so the document is rejected with a
///   stable code (the reference implementation rejects it too);
/// - `kubernetes-10.0.0` carries markers for other platforms, so some of its
///   requirements are reported as not applicable rather than as problems.
fn selected_documents() -> Array[(String, String)] {
  let chosen : Array[String] = [
    "flask-0.12.5", "alembic-1.5.8", "requests-2.24.0", "kubernetes-10.0.0",
  ]
  let out : Array[(String, String)] = []
  for wanted in chosen {
    for entry in @fixtures.metadata_pypi_cases {
      if entry.0 == wanted {
        out.push(entry)
      }
    }
  }
  if out.is_empty() {
    // The corpus always has these; if it does not, report on the curated case
    // that carries every field rather than printing nothing.
    for entry in @fixtures.metadata_cases {
      if entry.0 == "03_all_fields" {
        out.push(entry)
      }
    }
  }
  out
}

///|
fn main {
  let environment = target_environment()
  let lock_file = lock_document()
  let (lock, for_another_target) = applicable_lock(lock_file, environment)
  let documents = selected_documents()
  let parsed = @pyversion.Pylock::parse(lock_file) catch {
    _ => abort("the lock document this example compiles in must parse")
  }
  println(
    "lock file: pylock.toml, lock-version \{parsed.lock_version()}, \{parsed.packages().length()} entries, \{lock.length()} for this target, \{for_another_target} for another; target: linux, CPython 3.11.9",
  )
  let targets = parsed.environments().join(", ")
  println(
    "   lock targets: \{targets}; extras the lock covers: \{parsed.extras().length()}, dependency groups: \{parsed.dependency_groups().length()}",
  )
  println("")
  let mut problems = 0
  for entry in documents {
    problems = problems + report(entry.0, entry.1, lock)
    println("")
  }
  println(
    "\{documents.length()} metadata document(s), \{problems} problem(s) against the lock file",
  )
}
