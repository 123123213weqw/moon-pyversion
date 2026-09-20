///|
/// The result of joining one requirement, one core-metadata document, one
/// PEP 691 index response and one PEP 751 lock file for a concrete target.
/// Strings are retained for reporting; no file is downloaded or executed.
pub(all) struct PackageAudit {
  project : String
  requirement : String
  applicable : Bool
  metadata_name : String
  metadata_version : String
  index_name : String
  index_files : Int
  ignored_index_files : Int
  yanked_files : Int
  candidates : Array[String]
  selected_file : String?
  selected_version : String?
  lock_versions : Array[String]
  issues : Array[AuditIssue]
} derive(Eq, @debug.Debug)

///|
/// A stable machine-readable finding. `subject` identifies the project,
/// version or filename involved without embedding whole input documents.
pub(all) struct AuditIssue {
  code : String
  subject : String
} derive(Eq, @debug.Debug)

///|
/// Whether the requested dependency needs no action, is reproducibly ready,
/// or is blocked by at least one cross-document inconsistency.
pub(all) enum AuditDisposition {
  NotRequired
  Ready
  Blocked
} derive(Eq, @debug.Debug)

///|
pub fn PackageAudit::disposition(self : PackageAudit) -> AuditDisposition {
  if !self.applicable {
    NotRequired
  } else if self.issues.length() == 0 && self.selected_file is Some(_) {
    Ready
  } else {
    Blocked
  }
}

///|
/// A deterministic human-readable report suitable for CI logs. Documents and
/// URLs are not echoed; the report contains identities, counts and findings.
pub fn PackageAudit::render(self : PackageAudit) -> String {
  let out = StringBuilder()
  out.write_string("project: " + self.project + "\n")
  out.write_string("requirement: " + self.requirement + "\n")
  let disposition = match self.disposition() {
    NotRequired => "not-required"
    Ready => "ready"
    Blocked => "blocked"
  }
  out.write_string("disposition: " + disposition + "\n")
  out.write_string(
    "metadata: " + self.metadata_name + " " + self.metadata_version + "\n",
  )
  out.write_string(
    "index: " +
    self.index_name +
    ", files=" +
    self.index_files.to_string() +
    ", ignored=" +
    self.ignored_index_files.to_string() +
    ", yanked=" +
    self.yanked_files.to_string() +
    "\n",
  )
  out.write_string("candidates: " + self.candidates.length().to_string() + "\n")
  match self.selected_file {
    Some(filename) => out.write_string("selected: " + filename + "\n")
    None => out.write_string("selected: none\n")
  }
  out.write_string("lock-versions:")
  if self.lock_versions.length() == 0 {
    out.write_string(" none\n")
  } else {
    for version in self.lock_versions {
      out.write_string(" " + version)
    }
    out.write_char('\n')
  }
  if self.issues.length() == 0 {
    out.write_string("issues: none\n")
  } else {
    out.write_string("issues: " + self.issues.length().to_string() + "\n")
    for issue in self.issues {
      out.write_string("- " + issue.code + ": " + issue.subject + "\n")
    }
  }
  out.to_string()
}

///|
fn audit_issue(
  issues : Array[AuditIssue],
  code : String,
  subject : String,
) -> Unit {
  for issue in issues {
    if issue.code == code && issue.subject == subject {
      return
    }
  }
  issues.push({ code, subject, })
}

///|
fn requirement_applies(
  requirement : Requirement,
  environment : MarkerEnvironment,
) -> Bool raise {
  match requirement.marker_text {
    None => true
    Some(text) => Marker::parse(text).evaluate(environment)
  }
}

///|
fn metadata_supports_python(metadata : Metadata, python : Version) -> Bool {
  match metadata.requires_python() {
    None => true
    Some(specifier) => specifier.contains(python)
  }
}

///|
fn lock_package_supports_python(
  entry : PylockPackage,
  python : Version,
) -> Bool {
  match entry.requires_python_set() {
    None => true
    Some(specifier) => specifier.contains(python)
  }
}

///|
fn same_version(a : Version, b : Version) -> Bool {
  Version::compare(a, b) == 0
}

///|
/// Audit a package decision across four Python packaging artifacts.
///
/// The function is deliberately a join, not a resolver or installer:
///
/// - `requirement_text` supplies the requested project, constraints and marker;
/// - `metadata_text` supplies the distribution identity and Requires-Python;
/// - `index_json` supplies downloadable filenames, yank state and hashes;
/// - `pylock_toml` supplies the versions locked for the target environment;
/// - `environment`, `python_text` and `tags` describe the target explicitly.
///
/// Parsing errors are raised by the existing typed parsers. Successfully parsed
/// but mutually inconsistent artifacts return stable `AuditIssue` entries.
/// Yanked files are excluded unless `allow_yanked` is true. The selected file
/// must advertise a sha256 digest, match a file and digest in the one applicable
/// lock entry, and agree with the supplied metadata version for `Ready`.
pub fn audit_package(
  requirement_text : String,
  metadata_text : String,
  index_json : String,
  pylock_toml : String,
  environment : MarkerEnvironment,
  python_text : String,
  tags : Array[String],
  allow_yanked? : Bool = false,
) -> PackageAudit raise {
  let lock = Pylock::parse(pylock_toml)
  audit_package_with_lock(
    requirement_text, metadata_text, index_json, lock, environment, python_text,
    tags, allow_yanked,
  )
}

///|
fn audit_package_with_lock(
  requirement_text : String,
  metadata_text : String,
  index_json : String,
  lock : Pylock,
  environment : MarkerEnvironment,
  python_text : String,
  tags : Array[String],
  allow_yanked : Bool,
) -> PackageAudit raise {
  let requirement = Requirement::parse(requirement_text)
  let metadata = Metadata::parse(metadata_text)
  let index = SimpleIndex::parse(index_json)
  let python = Version::parse(python_text)
  let project = canonicalize_name(requirement.name)
  let issues : Array[AuditIssue] = []
  let applicable = requirement_applies(requirement, environment)

  if canonicalize_name(metadata.name) != project {
    audit_issue(issues, "METADATA_NAME_MISMATCH", metadata.name)
  }
  if canonicalize_name(index.name()) != project {
    audit_issue(issues, "INDEX_NAME_MISMATCH", index.name())
  }
  if !metadata_supports_python(metadata, python) {
    audit_issue(issues, "METADATA_REQUIRES_PYTHON", python_text)
  }
  if !lock.supports_python(python) {
    audit_issue(issues, "LOCK_REQUIRES_PYTHON", python_text)
  }
  if !lock.accepts_environment(environment) {
    audit_issue(issues, "LOCK_ENVIRONMENT_MISMATCH", project)
  }
  if requirement.url is Some(_) {
    audit_issue(issues, "DIRECT_URL_NOT_INDEXED", project)
  }

  let index_files : Array[IndexFile] = []
  let retained_sources : Array[SimpleIndexFile] = []
  let mut ignored_index_files = 0
  let mut yanked_files = 0
  for source in index.files() {
    let excluded_yanked = source.yanked is Yanked(_) && !allow_yanked
    if excluded_yanked {
      yanked_files = yanked_files + 1
    } else {
      try {
        index_files.push(source.to_index_file())
        retained_sources.push(source)
      } catch {
        _ => ignored_index_files = ignored_index_files + 1
      }
    }
  }

  let candidates = if applicable && requirement.url is None {
    resolve_candidates(index_files, requirement, tags, Some(python))
  } else {
    []
  }
  let candidate_names : Array[String] = []
  for candidate in candidates {
    candidate_names.push(candidate.filename)
  }
  let applicable_locked : Array[PylockPackage] = []
  for entry in lock.packages_named(project) {
    if entry.is_applicable(environment) &&
      lock_package_supports_python(entry, python) {
      applicable_locked.push(entry)
    }
  }
  // A lock is a selection, not permission to silently upgrade to the highest
  // version in the index. Keep the resolver's order within the locked version.
  let mut selected : IndexFile? = None
  if candidates.length() > 0 {
    if applicable_locked.length() == 1 {
      match applicable_locked[0].version {
        Some(locked_version) =>
          for candidate in candidates {
            if selected is None &&
              same_version(candidate.version, locked_version) {
              selected = Some(candidate)
            }
          }
        None => ()
      }
    }
    // Retain the best available candidate for diagnostics when the lock has
    // no matching version; it still cannot make the audit Ready.
    if selected is None {
      selected = Some(candidates[0])
    }
  }
  if applicable && selected is None {
    audit_issue(issues, "CANDIDATE_MISSING", project)
  }

  let selected_file : String? = match selected {
    None => None
    Some(file) => Some(file.filename)
  }
  let selected_version : String? = match selected {
    None => None
    Some(file) => Some(file.version.to_string())
  }
  match selected {
    Some(file) => {
      let mut has_sha256 = false
      for source in retained_sources {
        if source.filename == file.filename &&
          source.hash_for("sha256") is Some(_) {
          has_sha256 = true
        }
      }
      if !has_sha256 {
        audit_issue(issues, "SELECTED_SHA256_MISSING", file.filename)
      }
      if !same_version(metadata.version, file.version) {
        audit_issue(
          issues,
          "METADATA_SELECTION_MISMATCH",
          metadata.version.to_string() + " != " + file.version.to_string(),
        )
      }
    }
    None => ()
  }

  let lock_versions : Array[String] = []
  for entry in applicable_locked {
    match entry.version {
      Some(version) => {
        lock_versions.push(version.to_string())
        if !requirement.specifier.contains(version) {
          audit_issue(
            issues,
            "LOCK_REQUIREMENT_MISMATCH",
            entry.name + "==" + version.to_string(),
          )
        }
      }
      None => audit_issue(issues, "LOCK_VERSION_MISSING", entry.name)
    }
  }
  if applicable && applicable_locked.length() == 0 {
    audit_issue(issues, "LOCK_ENTRY_MISSING", project)
  } else if applicable_locked.length() > 1 {
    audit_issue(issues, "LOCK_ENTRY_AMBIGUOUS", project)
  }
  match selected {
    Some(file) if applicable_locked.length() == 1 => {
      let locked = applicable_locked[0]
      match locked.version {
        Some(version) =>
          if !same_version(file.version, version) {
            audit_issue(
              issues,
              "LOCK_SELECTION_MISMATCH",
              version.to_string() + " != " + file.version.to_string(),
            )
          }
        None => ()
      }
      let mut index_digest : String? = None
      for source in retained_sources {
        if source.filename == file.filename {
          index_digest = source.hash_for("sha256")
        }
      }
      let mut matched_file = false
      for locked_file in locked.all_files() {
        if locked_file.filename() == Some(file.filename) {
          matched_file = true
          match (index_digest, locked_file.hash_for("sha256")) {
            (Some(index_hash), Some(lock_hash)) =>
              if index_hash.to_lower() != lock_hash.to_lower() {
                audit_issue(issues, "LOCK_SHA256_MISMATCH", file.filename)
              }
            (Some(_), None) =>
              audit_issue(issues, "LOCK_SHA256_MISSING", file.filename)
            _ => ()
          }
        }
      }
      if !matched_file {
        audit_issue(issues, "LOCK_FILE_MISSING", file.filename)
      }
    }
    _ => ()
  }

  {
    project,
    // A direct URL may contain credentials. The report must not echo it even
    // when the input is rejected as outside the index/lock audit model.
    requirement: if requirement.url is Some(_) {
      project + " @ [redacted]"
    } else {
      requirement.to_string()
    },
    applicable,
    metadata_name: metadata.name,
    metadata_version: metadata.version.to_string(),
    index_name: index.name(),
    index_files: index.files().length(),
    ignored_index_files,
    yanked_files,
    candidates: candidate_names,
    selected_file,
    selected_version,
    lock_versions,
    issues,
  }
}

///|
/// One explicit project request and its two externally supplied artifacts.
/// The shared PEP 751 lock and target environment are passed to `audit_bundle`.
pub(all) struct AuditInput {
  requirement_text : String
  metadata_text : String
  index_json : String
} derive(Eq, @debug.Debug)

///|
/// An ordered set of package audits against one lock and one target. This is
/// intentionally not a dependency resolver: it audits exactly the inputs the
/// caller supplies and does not infer or fetch missing transitive projects.
pub(all) struct AuditBundle {
  reports : Array[PackageAudit]
  issues : Array[AuditIssue]
} derive(Eq, @debug.Debug)

///|
pub fn AuditBundle::disposition(self : AuditBundle) -> AuditDisposition {
  if self.issues.length() > 0 {
    return Blocked
  }
  let mut has_ready = false
  for report in self.reports {
    match report.disposition() {
      Blocked => return Blocked
      Ready => has_ready = true
      NotRequired => ()
    }
  }
  if has_ready {
    Ready
  } else {
    NotRequired
  }
}

///|
pub fn AuditBundle::counts(self : AuditBundle) -> (Int, Int, Int) {
  let mut ready = 0
  let mut blocked = 0
  let mut not_required = 0
  for report in self.reports {
    match report.disposition() {
      Ready => ready = ready + 1
      Blocked => blocked = blocked + 1
      NotRequired => not_required = not_required + 1
    }
  }
  (ready, blocked, not_required)
}

///|
pub fn AuditBundle::render(self : AuditBundle) -> String {
  let (ready, blocked, not_required) = self.counts()
  let out = StringBuilder()
  out.write_string(
    "bundle: " +
    self.reports.length().to_string() +
    " package(s), ready=" +
    ready.to_string() +
    ", blocked=" +
    blocked.to_string() +
    ", not-required=" +
    not_required.to_string() +
    "\n",
  )
  for issue in self.issues {
    out.write_string(
      "bundle-issue: " + issue.code + ": " + issue.subject + "\n",
    )
  }
  for report in self.reports {
    out.write_string("\n" + report.render())
  }
  out.to_string()
}

///|
/// Audit a caller-supplied bundle against one lock and one explicit target.
/// The lock is parsed once, then each input receives an independent package
/// report in caller order. Duplicate project inputs are reported at bundle
/// level, because two independently supplied index/metadata pairs for one
/// canonical project make the overall decision ambiguous.
///
/// With `require_lock_coverage=true`, every applicable, Python-compatible lock
/// entry must have an input. This is useful when the caller claims to provide a
/// complete offline mirror; leave it false for partial audits. No network I/O,
/// recursive dependency solving or content hashing occurs here.
pub fn audit_bundle(
  inputs : Array[AuditInput],
  pylock_toml : String,
  environment : MarkerEnvironment,
  python_text : String,
  tags : Array[String],
  allow_yanked? : Bool = false,
  require_lock_coverage? : Bool = false,
) -> AuditBundle raise {
  let lock = Pylock::parse(pylock_toml)
  let python = Version::parse(python_text)
  let reports : Array[PackageAudit] = []
  let issues : Array[AuditIssue] = []
  for input in inputs {
    let report = audit_package_with_lock(
      input.requirement_text,
      input.metadata_text,
      input.index_json,
      lock,
      environment,
      python_text,
      tags,
      allow_yanked,
    )
    for previous in reports {
      if previous.project == report.project {
        audit_issue(issues, "DUPLICATE_PROJECT_INPUT", report.project)
      }
    }
    reports.push(report)
  }
  if require_lock_coverage {
    for entry in lock.applicable_packages(environment) {
      if lock_package_supports_python(entry, python) {
        let name = canonicalize_name(entry.name)
        let mut found = false
        for report in reports {
          if report.project == name && report.applicable {
            found = true
          }
        }
        if !found {
          audit_issue(issues, "LOCK_ENTRY_UNAUDITED", name)
        }
      }
    }
  }
  { reports, issues, }
}
