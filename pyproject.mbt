///|
/// A PEP 621 project table read from a parsed `pyproject.toml`: the
/// `[project]` table's requirements plus the packaging facts that drive
/// marker evaluation. This is the bridge between the TOML the caller
/// parsed and the judgment calls the library already knows how to make
/// - it answers "what does this project need, and can this runtime
/// provide it" without a resolver.
#derive(@debug.Debug)
pub(all) struct PyProject {
  /// The normalized project name, when `[project].name` is present.
  name : String?
  /// Every string in `[project].dependencies`, parsed; a malformed
  /// entry aborts the whole read with its text - a half-read project
  /// table would silently understate the requirements.
  dependencies : Array[Requirement]
  /// `[project].requires-python`, parsed; None when absent.
  requires_python : SpecifierSet?
  /// The optional `[project].optional-dependencies` table, each key an
  /// extra name and its value the parsed requirement list.
  optional : Map[String, Array[Requirement]]
  /// Every string in `[build-system].requires`, parsed with the same
  /// refusal discipline as the runtime dependencies; empty when the
  /// table or the key is absent (PEP 517's defaults then apply).
  build_requires : Array[Requirement]
}

///|
pub extend PyProject with @debug.Debug::{to_repr}

///|
/// Read the `[project]` table from a parsed TOML document. Requirements
/// that are merely absent (no dependencies key) read as an empty list;
/// requirements that are present but malformed refuse the whole read,
/// naming the entry - a project whose declared dependency cannot be
/// parsed is a broken project, not a project with fewer dependencies.
pub fn PyProject::from_toml(toml : Toml) -> PyProject raise VersionError {
  let project = match toml.get_table("project") {
    Some(table) => table
    None => raise VersionError::InvalidRequirement("NO_PROJECT_TABLE", 0)
  }
  let name = match project.get_string("name") {
    Some(raw) => Some(canonicalize_name(raw))
    None => None
  }
  // dependencies: every entry must parse or the read refuses.
  let dependencies : Array[Requirement] = []
  match project.get_array("dependencies") {
    None => ()
    Some(items) =>
      for item in items {
        let text = match item {
          TString(value) => value
          _ =>
            raise VersionError::InvalidRequirement("NON_STRING_DEPENDENCY", 0)
        }
        dependencies.push(Requirement::parse(text))
      }
  }
  // requires-python: absent means unconstrained.
  let requires_python = match project.get_string("requires-python") {
    None => None
    Some(text) => Some(SpecifierSet::parse(text))
  }
  // optional-dependencies: each key an extra, each value a list.
  let optional : Map[String, Array[Requirement]] = Map([])
  match project.get("optional-dependencies") {
    None => ()
    Some(TTable(table)) =>
      for (key, value) in table.entries {
        let list : Array[Requirement] = []
        match value {
          TArray(items) =>
            for item in items {
              let text = match item {
                TString(text) => text
                _ =>
                  raise VersionError::InvalidRequirement(
                    "NON_STRING_DEPENDENCY", 0,
                  )
              }
              list.push(Requirement::parse(text))
            }
          _ => raise VersionError::InvalidRequirement("OPTIONAL_NOT_ARRAY", 0)
        }
        optional[key] = list
      }
    Some(_) => raise VersionError::InvalidRequirement("OPTIONAL_NOT_TABLE", 0)
  }
  // build-system.requires: absent table or key reads as empty (PEP 517
  // supplies defaults); present-but-malformed refuses the whole read,
  // naming the offence - a build requirement that cannot be parsed is a
  // broken build table, not a build with fewer requirements.
  let build_requires : Array[Requirement] = []
  match toml.get_table("build-system") {
    None => ()
    Some(build) =>
      match build.get("requires") {
        None => ()
        Some(TArray(items)) =>
          for item in items {
            let text = match item {
              TString(value) => value
              _ =>
                raise VersionError::InvalidRequirement(
                  "NON_STRING_BUILD_REQUIRES", 0,
                )
            }
            build_requires.push(Requirement::parse(text))
          }
        Some(_) =>
          raise VersionError::InvalidRequirement("BUILD_REQUIRES_NOT_ARRAY", 0)
      }
  }
  { name, dependencies, requires_python, optional, build_requires, }
}

///|
/// The full requirement list including one extra's optional
/// dependencies: the dependencies a resolver would consider when the
/// caller asks for `name[extra]`. An extra the project does not declare
/// is refused by name - guessing an empty list would understate what
/// the project needs.
pub fn PyProject::with_extra(
  self : PyProject,
  extra : String,
) -> Array[Requirement] raise VersionError {
  let key = canonicalize_name(extra)
  match self.optional.get(key) {
    Some(list) => {
      let all : Array[Requirement] = []
      for requirement in self.dependencies {
        all.push(requirement)
      }
      for requirement in list {
        all.push(requirement)
      }
      all
    }
    None =>
      raise VersionError::InvalidRequirement("UNDECLARED_EXTRA:" + extra, 0)
  }
}

///|
/// The build-side judgment: does this runtime satisfy every
/// `[build-system].requires` entry's version constraint and marker? The
/// same named failures all_satisfied_by reports, over the PEP 517 build
/// dependencies instead of the runtime ones. There is no python gate here:
/// `[build-system]` declares no `requires-python`, so the build tools'
/// own markers (sys_platform, os_name, python_version...) carry all the
/// environment decisions. None means every build requirement is
/// satisfied by the candidates the lookup provides.
pub fn PyProject::check_build_requires(
  self : PyProject,
  python_full_version : String,
  implementation_name : String,
  platform_system : String,
  platform_machine : String,
  candidates : (String) -> Version?,
) -> Array[RequirementFailure]? raise VersionError {
  let environment = MarkerEnvironment::from_runtime(
    python_full_version, implementation_name, platform_system, platform_machine,
  )
  all_satisfied_by(self.build_requires, candidates, environment)
}

///|
/// The project-level check this library exists to answer: does this
/// runtime satisfy the project's python constraint (when declared) and
/// every base dependency's version constraint and marker? The same
/// named failures all_satisfied_by reports, with one addition first in
/// the list when the runtime's python version falls outside
/// `requires-python` - the constraint that governs whether the project
/// may be installed at all.
pub fn PyProject::check_runtime(
  self : PyProject,
  python_full_version : String,
  implementation_name : String,
  platform_system : String,
  platform_machine : String,
  candidates : (String) -> Version?,
) -> Array[RequirementFailure]? raise VersionError {
  let environment = MarkerEnvironment::from_runtime(
    python_full_version, implementation_name, platform_system, platform_machine,
  )
  let failures : Array[RequirementFailure] = []
  // requires-python first: it gates the whole project.
  match self.requires_python {
    None => ()
    Some(spec) => {
      let python = Version::parse(python_full_version)
      if !spec.contains(python) {
        failures.push({
          requirement: "requires-python " + spec.to_string(),
          reason: "python " +
          python_full_version +
          " not in " +
          spec.to_string(),
        })
      }
    }
  }
  // Then every dependency, with the same named-failure discipline.
  match all_satisfied_by(self.dependencies, candidates, environment) {
    None => ()
    Some(items) =>
      for item in items {
        failures.push(item)
      }
  }
  if failures.is_empty() {
    None
  } else {
    Some(failures)
  }
}

///|
/// The end-to-end answer: does this runtime support installing this
/// project, and where would each dependency come from? Runs
/// check_runtime for the go/no-go and the python gate, then - for each
/// dependency whose project has an index - select_candidates to find
/// the viable files on this runtime. The candidate lookup that
/// check_runtime receives is the index-backed one: a dependency with
/// no index simply fails with "no candidate for X" exactly as before;
/// a dependency whose index has no viable file fails with the
/// select_candidates exclusions rendered as reasons. This is the
/// micro-pip: pyproject.toml plus a set of PEP 691 indexes in, a
/// named-failure list or a green light out.
pub fn PyProject::plan_install(
  self : PyProject,
  indexes : Map[String, SimpleIndex],
  python_full_version : String,
  implementation_name : String,
  platform_system : String,
  platform_machine : String,
) -> Array[RequirementFailure]? raise VersionError {
  // The candidate lookup: the newest viable version per project from
  // its index, gated by select_candidates on the same runtime.
  // The lookup for check_runtime must be non-raising; select_candidates
  // raises on a malformed index, which plan_install propagates directly
  // by pre-computing the best version per indexed project.
  let best_versions : Map[String, Version] = Map([])
  for name in indexes.keys() {
    let (candidates, _) = select_candidates(
      indexes[name],
      Some(python_full_version),
      None,
    )
    let mut best : Version? = None
    for candidate in candidates {
      match best {
        None => best = Some(candidate.version)
        Some(current) =>
          if Version::compare(candidate.version, current) > 0 {
            best = Some(candidate.version)
          }
      }
    }
    match best {
      None => ()
      Some(v) => best_versions[name] = v
    }
  }
  fn resolve(name : String) -> Version? {
    best_versions.get(name)
  }
  let failures = self.check_runtime(
    python_full_version, implementation_name, platform_system, platform_machine,
    resolve,
  )
  match failures {
    None => None
    Some(items) =>
      // A "no candidate for X" failure where X has an index means the
      // index had nothing viable - refine the reason with the count
      // the caller can act on (zero candidates after gates).
      Some(
        items.map(item => {
          if item.reason.has_prefix("no candidate for ") == false {
            item
          } else {
            let name = item.reason
              .strip_prefix("no candidate for ")
              .unwrap()
              .to_owned()
            match indexes.get(name) {
              None => item
              Some(_) => {
                let (_, excluded) = select_candidates(
                  indexes.get(name).unwrap(),
                  Some(python_full_version),
                  None,
                )
                if excluded.is_empty() {
                  item
                } else {
                  {
                    requirement: item.requirement,
                    reason: "no viable file for " +
                    name +
                    " (" +
                    excluded.length().to_string() +
                    " excluded)",
                  }
                }
              }
            }
          }
        }),
      )
  }
}
