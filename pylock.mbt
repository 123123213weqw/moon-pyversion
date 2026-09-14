///|
/// PEP 751 lock files: `pylock.toml`.
///
/// A lock file records *what* to install so an installer does not have to
/// resolve anything. This reader takes the whole document as a string and
/// returns a validated `Pylock`; it never touches the filesystem, the network or
/// the clock, and the `[tool]` tables are ignored, as the specification requires
/// of a reader.
///
/// ```moonbit nocheck
/// let lock = Pylock::parse(
///   "lock-version = \"1.0\"\ncreated-by = \"demo\"\n\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n",
/// )
/// lock.packages().length()      // 1
/// lock.packages()[0].name       // "attrs"
/// lock.files_for("attrs")       // []
/// ```
///
/// The structure is the one the accepted PEP 751 and the `pylock.toml`
/// specification define: the required `lock-version` (`"1.0"`) and `[[packages]]`
/// array of tables, the optional `environments`, `requires-python`, `extras`,
/// `dependency-groups`, `default-groups` and `created-by`, and, per package,
/// `name`, `version`, `marker`, `requires-python`, `[[packages.dependencies]]`,
/// `[packages.vcs]`, `[packages.directory]`, `[packages.archive]`,
/// `packages.index`, `[packages.sdist]` and `[[packages.wheels]]`.
///
/// Two spellings from the drafting period are accepted as well, because tooling
/// written against a draft emitted them and because the brief for this module
/// names them: `[[packages.files]]`, a third file list with exactly the record
/// shape of `[[packages.wheels]]`, and a package-level `path`, a local path
/// source form. Neither is written by the accepted specification (`path` exists
/// there as a member of `vcs`, `archive`, `sdist` and `wheels`); both take part
/// in the source-exclusivity rule below like any other source, and neither is
/// ever written back, because this file is a reader only.
///
/// Every rejection is a `VersionError::InvalidPylock(code, ordinal)`, where
/// `code` is a stable upper-snake-case string. The `Int` is a *structural* index
/// rather than a character offset, because the TOML layer has already forgotten
/// positions: it is the ordinal of the offending `[[packages]]` entry (a problem
/// inside `packages[i].dependencies[j]` or `packages[i].wheels[k]` reports `i`),
/// or `0` when the document as a whole is at fault. `index.mbt` uses the same
/// convention for `InvalidIndex`.
///
/// A code is built from the member it names: `<MEMBER>_REQUIRED` for a missing
/// required member, `<MEMBER>_TYPE` for a scalar of the wrong TOML type,
/// `<MEMBER>_NOT_TABLE` / `<MEMBER>_NOT_ARRAY` for a container of the wrong
/// kind, `<MEMBER>_INVALID` for a value the specification's own syntax rejects,
/// and `<MEMBER>_EMPTY` for a present but empty container. `index.mbt` spells a
/// wrong TOML type `<code>_TYPE`; this file keeps that for scalars and adds the
/// two container codes because the members are nested and `VCS_TYPE` alone
/// could not say whether `packages.vcs` or `packages.vcs.type` is at fault.
/// An empty string counts as an absent value, the same rule `metadata.mbt`
/// applies to an empty header value.
///
/// The rule to code mapping is:
///
/// | rule | code |
/// | --- | --- |
/// | 1 `lock-version` | `LOCK_VERSION_REQUIRED`, `LOCK_VERSION_TYPE`, `LOCK_VERSION_INVALID` |
/// | 2 `environments` | `ENVIRONMENTS_NOT_ARRAY`, `ENVIRONMENTS_ENTRY_TYPE`, `ENVIRONMENT_MARKER_INVALID` |
/// | 3 `requires-python` | `REQUIRES_PYTHON_TYPE`, `REQUIRES_PYTHON_INVALID` |
/// | 4 `extras` | `EXTRAS_NOT_ARRAY`, `EXTRAS_ENTRY_TYPE`, `EXTRA_INVALID` |
/// | 5 `dependency-groups` | `DEPENDENCY_GROUPS_NOT_ARRAY`, `DEPENDENCY_GROUPS_ENTRY_TYPE`, `DEPENDENCY_GROUP_INVALID` |
/// | 6 `default-groups` | `DEFAULT_GROUPS_NOT_ARRAY`, `DEFAULT_GROUPS_ENTRY_TYPE`, `DEFAULT_GROUP_INVALID` |
/// | 7 `created-by` | `CREATED_BY_TYPE`; absence is accepted, see below |
/// | 8 `packages` | `PACKAGES_REQUIRED`, `PACKAGES_NOT_ARRAY`, `PACKAGE_NOT_TABLE` |
/// | 9 `packages.name` | `PACKAGE_NAME_REQUIRED`, `PACKAGE_NAME_TYPE`, `PACKAGE_NAME_INVALID` |
/// | 10 `packages.version` | `PACKAGE_VERSION_REQUIRED`, `PACKAGE_VERSION_TYPE`, `PACKAGE_VERSION_INVALID` |
/// | 11 `packages.marker` | `PACKAGE_MARKER_TYPE`, `PACKAGE_MARKER_INVALID` |
/// | 12 `packages.requires-python` | `PACKAGE_REQUIRES_PYTHON_TYPE`, `PACKAGE_REQUIRES_PYTHON_INVALID` |
/// | 13 `[[packages.dependencies]]` | `DEPENDENCIES_NOT_ARRAY`, `DEPENDENCY_NOT_TABLE`, `DEPENDENCY_NAME_REQUIRED`, `DEPENDENCY_NAME_TYPE`, `DEPENDENCY_NAME_INVALID`, `DEPENDENCY_VERSION_TYPE`, `DEPENDENCY_VERSION_INVALID`, `DEPENDENCY_MARKER_TYPE`, `DEPENDENCY_MARKER_INVALID`, `DEPENDENCY_EXTRAS_NOT_ARRAY`, `DEPENDENCY_EXTRAS_ENTRY_TYPE`, `DEPENDENCY_EXTRA_INVALID` |
/// | 14 self reference | `DEPENDENCY_SELF_REFERENCE` |
/// | 15 source exclusivity | `PACKAGE_SOURCE_CONFLICT` |
/// | 16 `[packages.vcs]` | `VCS_NOT_TABLE`, `VCS_TYPE_REQUIRED`, `VCS_TYPE_INVALID`, `VCS_URL_REQUIRED`, `VCS_URL_TYPE`, `VCS_PATH_TYPE`, `VCS_REQUESTED_REVISION_TYPE`, `VCS_COMMIT_ID_REQUIRED`, `VCS_COMMIT_ID_TYPE`, `VCS_SUBDIRECTORY_TYPE` |
/// | 17 `[packages.directory]` | `DIRECTORY_NOT_TABLE`, `DIRECTORY_PATH_REQUIRED`, `DIRECTORY_PATH_TYPE`, `DIRECTORY_EDITABLE_TYPE`, `DIRECTORY_SUBDIRECTORY_TYPE` |
/// | 18 `[packages.archive]` | `ARCHIVE_NOT_TABLE`, `ARCHIVE_URL_REQUIRED`, and the file record codes of rule 20 |
/// | 19 `packages.index`, `packages.path` | `INDEX_TYPE`, `PATH_TYPE` |
/// | 20 `[[packages.files]]`, `[[packages.wheels]]`, `[packages.sdist]` | `FILES_NOT_ARRAY`, `WHEELS_NOT_ARRAY`, `SDIST_NOT_TABLE`, `FILE_NOT_TABLE`, `FILE_NAME_REQUIRED`, `FILE_NAME_TYPE`, `FILE_URL_TYPE`, `FILE_PATH_TYPE`, `FILE_HASHES_NOT_TABLE`, `FILE_HASHES_EMPTY`, `FILE_HASH_TYPE`, `FILE_SIZE_TYPE`, `FILE_SIZE_NEGATIVE`, `FILE_UPLOAD_TIME_TYPE`, `FILE_SUBDIRECTORY_TYPE` |
///
/// What a source is has one rule (rule 15): the mutually exclusive members are
/// `vcs`, `directory`, `archive` and `path` -- a package is a source tree or a
/// direct reference -- and none of them may be combined with a file list
/// (`files`, `sdist`, `wheels`), which is the specification's own rule for
/// `vcs`/`directory`/`archive` against `sdist`/`wheels`. A file list *may* be
/// combined with another file list (`sdist` next to `wheels` is the
/// specification's own example of a package that publishes both), and `index`
/// combines with anything.
///
/// Where this file deliberately differs from the accepted specification, each
/// difference is also marked at the code that implements it:
///
/// - `created-by` is required by the specification; this reader accepts its
///   absence and reports `Pylock::created_by` as `None`, so that a hand-written
///   or partially written lock file is still readable. Every other member is
///   validated as strictly as the specification demands.
/// - `packages.version` is optional in the specification and MUST NOT be present
///   when a source tree is recorded. This reader requires it unless a direct
///   reference (`vcs`, `directory`, `archive`, `path`) is recorded, and accepts a
///   redundant `version` next to one: a version key is what a resolved set is
///   checked against, and the specification's MUST NOT is a locker-side rule.
/// - `packages.name` is written normalized by a locker; this reader accepts any
///   valid project name and compares names with `canonicalize_name`, so
///   `Zope.Interface` is readable and matches `zope-interface`.
/// - `hashes` is required on `archive`, `sdist` and `wheels`; this reader accepts
///   a file record without it (the digest is then simply unknown) but rejects a
///   `hashes` table with no entry, which the specification forbids outright.
/// - `upload-time` must be recorded in UTC and hash algorithm keys SHOULD be
///   lowercase; the reader only checks that `upload-time` is a TOML datetime and
///   records the spelling verbatim, and it compares algorithm names verbatim.
/// - Unknown keys are ignored everywhere: `[tool]`, `[packages.tool]`,
///   `[[packages.attestation-identities]]` and any key a later minor version
///   adds. The specification asks a reader that supports the major version to
///   warn about an unknown key; there is no warning channel here.
/// - `lock-version` is rejected unless it is exactly `"1.0"`. The specification
///   says a reader that supports the major version but not the minor one SHOULD
///   warn; a silent acceptance would be worse than a rejection, so `"1.1"` is
///   `LOCK_VERSION_INVALID`.
/// - Text that is not TOML at all is rejected by `Toml::parse` and surfaces as
///   `VersionError::InvalidToml`, not as `InvalidPylock`: the TOML reader owns
///   that diagnosis and it carries the offset this file cannot.
///
/// What this file does not do, on purpose: it does not read or write files, so
/// the `pylock.toml` / `pylock.<name>.toml` naming convention of the
/// specification is a caller's concern; it does not implement the install
/// algorithm's singularity rule (two entries for one name are kept, and deciding
/// that they narrow down to one entry needs both a target `MarkerEnvironment`
/// and the extras and dependency groups the user asked for, which is what
/// `Pylock::is_applicable`, `Pylock::applicable_packages` and
/// `Pylock::accepts_environment` are for); it records but does not validate
/// `[[packages.attestation-identities]]`; and it does not model
/// `packages.extras` / `packages.dependency-groups`, which PEP 751 mentions once
/// in its marker discussion but never defines a type or a requiredness for. A
/// serializer is not provided either.
const PYLOCK_LOCK_VERSION : String = "1.0"

///|
/// Which member of a package a `PylockFile` came from. The lists keep the
/// specification's own spellings apart so a caller can tell a wheel from an
/// sdist from an archive without re-reading the document.
pub(all) enum PylockFileKind {
  /// A `[[packages.files]]` entry, the draft spelling this module also accepts.
  FilesEntry
  /// A `[[packages.wheels]]` entry.
  WheelFile
  /// The `[packages.sdist]` table.
  SdistFile
  /// The `[packages.archive]` table.
  ArchiveFile
} derive(Eq, @debug.Debug)

///|
/// The TOML key a file record was read from: `"files"`, `"wheels"`, `"sdist"` or
/// `"archive"`.
pub fn PylockFileKind::key(self : PylockFileKind) -> String {
  match self {
    FilesEntry => "files"
    WheelFile => "wheels"
    SdistFile => "sdist"
    ArchiveFile => "archive"
  }
}

///|
/// One distribution file of a package: an entry of `[[packages.files]]`, an entry
/// of `[[packages.wheels]]`, or the `[packages.sdist]` / `[packages.archive]`
/// table. All of them share one record shape in the specification, so they share
/// one type here.
///
/// `name`, `url` and `path` are all optional; `PylockFile::filename` resolves the
/// name the specification allows to be inferred from the last component of `url`
/// or `path`. `hashes` keeps document order and is empty when the member is
/// absent. `upload_time` is the datetime's source spelling, because no date
/// arithmetic happens anywhere in this library.
pub(all) struct PylockFile {
  /// `name`, as written; `Some` only when the member is present and non-empty.
  name : String?
  /// `url`, opaque and unresolved.
  url : String?
  /// `path`, as written, POSIX-style as the specification asks.
  path : String?
  /// `hashes`, as `(algorithm, value)` pairs in document order.
  hashes : Array[(String, String)]
  /// `size` in bytes.
  size : Int64?
  /// `upload-time`, the TOML datetime's source spelling.
  upload_time : String?
  /// `subdirectory`, for `archive` (and `vcs`/`directory`, which have their own
  /// tables).
  subdirectory : String?
  /// The member this record was read from.
  kind : PylockFileKind
} derive(Eq, @debug.Debug)

///|
/// The digest advertised for `algorithm` (for example `"sha256"`), or `None`.
/// Algorithm names are compared verbatim, the same rule `SimpleIndexFile` uses.
pub fn PylockFile::hash_for(self : PylockFile, algorithm : String) -> String? {
  let mut found : String? = None
  for i = 0; i < self.hashes.length(); i = i + 1 {
    if self.hashes[i].0 == algorithm {
      found = Some(self.hashes[i].1)
    }
  }
  found
}

///|
/// The file name of the record: `name` when it is set, otherwise the last
/// component of `url`, otherwise the last component of `path`. `None` only when
/// the record names no file, which rule 20 allows for `sdist` and `wheels` (an
/// installer is then expected to find the file through `index`) and never for a
/// record that has neither `url` nor `path` either.
pub fn PylockFile::filename(self : PylockFile) -> String? {
  match self.name {
    Some(name) => Some(name)
    None =>
      match self.url {
        Some(url) => last_path_component(url)
        None =>
          match self.path {
            Some(path) => last_path_component(path)
            None => None
          }
      }
  }
}

///|
/// The last component of a URL or a POSIX-style path, with any `?query` or
/// `#fragment` removed, or `None` when nothing is left. No other URL handling
/// happens anywhere in this library: `url` is an opaque string.
fn last_path_component(text : String) -> String? {
  let mut start = 0
  for i = 0; i < text.length(); i = i + 1 {
    // `/`
    if text[i].to_int() == 47 {
      start = i + 1
    }
  }
  let tail = text[start:text.length()]
  let mut stop = tail.length()
  for i = 0; i < tail.length(); i = i + 1 {
    if i < stop {
      let code = tail[i].to_int()
      // `#` or `?`
      if code == 35 || code == 63 {
        stop = i
      }
    }
  }
  if stop == 0 {
    None
  } else {
    Some(tail[0:stop].to_owned())
  }
}

///|
/// `[packages.vcs]`: a source tree in version control.
///
/// `vcs_type` is one of the registered types (`git`, `hg`, `bzr`, `svn`),
/// `commit_id` is required because the specification wants an immutable revision,
/// and at least one of `url` and `path` says where the repository is.
pub(all) struct PylockVcs {
  /// `packages.vcs.type`, one of `git hg bzr svn`.
  vcs_type : String
  /// `packages.vcs.url`.
  url : String?
  /// `packages.vcs.path`, a local source tree.
  path : String?
  /// `packages.vcs.requested-revision`, informational; it is never used to check
  /// anything out.
  requested_revision : String?
  /// `packages.vcs.commit-id`, the immutable revision to install.
  commit_id : String
  /// `packages.vcs.subdirectory`, relative to the root of the source tree.
  subdirectory : String?
} derive(Eq, @debug.Debug)

///|
/// `[packages.directory]`: a source tree on the local filesystem. `editable`
/// records what the lock time was, and the specification lets an installer
/// ignore it.
pub(all) struct PylockDirectory {
  /// `packages.directory.path`, relative to the lock file when it is relative.
  path : String
  /// `packages.directory.editable`, defaulted to `false`.
  editable : Bool
  /// `packages.directory.subdirectory`.
  subdirectory : String?
} derive(Eq, @debug.Debug)

///|
/// One entry of `[[packages.dependencies]]`.
///
/// PEP 751 defines the entry as the minimum information that identifies another
/// `[[packages]]` entry by a key-by-key comparison -- `name` alone, or `name`
/// plus `version`, or `name` plus a source -- and says a tool MUST NOT use it for
/// installation; it is an audit record. `marker` and `extras` are not members the
/// specification's dependency entry defines at all, but the brief for this module
/// records them, so they are read and validated like any other marker and name
/// list. Unknown keys of an entry are ignored.
pub(all) struct PylockDependency {
  /// `name`, as written but checked against the PEP 508 name syntax.
  name : String
  /// `version`, the identity of the entry this dependency points at.
  version : Version?
  /// `marker`, as written.
  marker : String?
  /// `extras`, as written and in document order.
  extras : Array[String]
} derive(Eq, @debug.Debug)

///|
/// One entry of `[[packages]]`: a distribution that *may* be installed, possibly
/// one of several entries for the same name that different environments select
/// between. Read `marker` through `PylockPackage::is_applicable` rather than
/// evaluating it by hand.
pub(all) struct PylockPackage {
  /// `name`, exactly as written; `canonicalize_name` makes spellings comparable.
  name : String
  /// `version`, parsed as PEP 440, absent for a source tree.
  version : Version?
  /// `marker`, as written; `None` means the entry always applies.
  marker : String?
  /// `requires-python`, the raw specifier set; `requires_python_set` parses it,
  /// and it was already validated by the parser.
  requires_python : String?
  /// `[[packages.dependencies]]`, in document order.
  dependencies : Array[PylockDependency]
  /// `[[packages.files]]`, in document order.
  files : Array[PylockFile]
  /// `[[packages.wheels]]`, in document order.
  wheels : Array[PylockFile]
  /// `[packages.sdist]`.
  sdist : PylockFile?
  /// `[packages.archive]`.
  archive : PylockFile?
  /// `[packages.vcs]`.
  vcs : PylockVcs?
  /// `[packages.directory]`.
  directory : PylockDirectory?
  /// `packages.index`, the base URL of the index the files were found on.
  index : String?
  /// `packages.path`, the draft local path source form.
  path : String?
} derive(Eq, @debug.Debug)

///|
/// Every file record of the entry, in a fixed order: `files`, then `sdist`, then
/// `wheels`, then `archive`. Empty when the package records no file.
pub fn PylockPackage::all_files(self : PylockPackage) -> Array[PylockFile] {
  let out : Array[PylockFile] = []
  for file in self.files {
    out.push(file)
  }
  match self.sdist {
    Some(file) => out.push(file)
    None => ()
  }
  for file in self.wheels {
    out.push(file)
  }
  match self.archive {
    Some(file) => out.push(file)
    None => ()
  }
  out
}

///|
/// True when the entry records a source tree (`vcs` or `directory`), which is the
/// case the specification allows to have no `version`.
pub fn PylockPackage::is_source_tree(self : PylockPackage) -> Bool {
  self.vcs is Some(_) || self.directory is Some(_)
}

///|
/// True when the entry records a direct reference: a source tree, an archive or a
/// local path. Those are the entries whose `version` is optional here.
pub fn PylockPackage::is_direct_reference(self : PylockPackage) -> Bool {
  self.is_source_tree() || self.archive is Some(_) || self.path is Some(_)
}

///|
/// `requires-python` as a parsed specifier set, or `None` when the member is
/// absent. The text was validated when the document was parsed, so the `None` of
/// a failed parse cannot happen; a `None` member is also `None`.
pub fn PylockPackage::requires_python_set(
  self : PylockPackage,
) -> SpecifierSet? {
  match self.requires_python {
    None => None
    Some(text) => Some(SpecifierSet::parse(text)) catch { _ => None }
  }
}

///|
/// True when the entry applies to `environment`: it has no `marker`, or its
/// marker evaluates to true there.
///
/// The marker is re-parsed on every call, which is cheap, deterministic and
/// keeps the caller's spelling on the value. `MarkerError` is raised exactly
/// where `Marker::evaluate` raises it, so an environment that is missing a key
/// one of the markers mentions is reported instead of being guessed at.
pub fn PylockPackage::is_applicable(
  self : PylockPackage,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  match self.marker {
    Some(text) => marker_accepts(text, environment)
    None => true
  }
}

///|
/// A validated `pylock.toml` document. The fields are private; read them through
/// the accessors, so the spelling of every member lives in one place.
pub struct Pylock {
  lock_version : String
  environments : Array[String]
  requires_python : String?
  extras : Array[String]
  dependency_groups : Array[String]
  default_groups : Array[String]
  created_by : String?
  packages : Array[PylockPackage]
} derive(Eq, @debug.Debug)

///|
/// `lock-version`, always `"1.0"`: this reader implements no other version.
pub fn Pylock::lock_version(self : Pylock) -> String {
  self.lock_version
}

///|
/// `environments`: the marker expressions the lock file is compatible with, in
/// document order. Empty means "no restriction", which is also what an absent
/// member means (rule 2 does not give the member a default of its own).
pub fn Pylock::environments(self : Pylock) -> Array[String] {
  self.environments
}

///|
/// `requires-python`, the raw specifier set, or `None`.
pub fn Pylock::requires_python(self : Pylock) -> String? {
  self.requires_python
}

///|
/// `requires-python` as a parsed specifier set, or `None` when the member is
/// absent (or, which rule 3 makes impossible, unparseable).
pub fn Pylock::requires_python_set(self : Pylock) -> SpecifierSet? {
  match self.requires_python {
    None => None
    Some(text) => Some(SpecifierSet::parse(text)) catch { _ => None }
  }
}

///|
/// True when `version` satisfies this lock file's `requires-python`. A lock file
/// without `requires-python` supports every version.
pub fn Pylock::supports_python(self : Pylock, version : Version) -> Bool {
  match self.requires_python_set() {
    Some(specifier) => specifier.contains(version)
    None => true
  }
}

///|
/// `extras`, in document order; empty when the member is absent.
pub fn Pylock::extras(self : Pylock) -> Array[String] {
  self.extras
}

///|
/// `dependency-groups`, in document order; empty when the member is absent.
pub fn Pylock::dependency_groups(self : Pylock) -> Array[String] {
  self.dependency_groups
}

///|
/// `default-groups`, in document order; empty when the member is absent. These
/// are the keys a `MarkerEnvironment` should carry as `dependency_groups` for
/// the default install.
pub fn Pylock::default_groups(self : Pylock) -> Array[String] {
  self.default_groups
}

///|
/// `created-by`, or `None` when the member is absent. The specification requires
/// the member; see the module doc for why its absence is accepted here.
pub fn Pylock::created_by(self : Pylock) -> String? {
  self.created_by
}

///|
/// `[[packages]]`, in document order. The same name may appear more than once
/// with different markers and versions, which is how a lock file covers several
/// environments; the install-time rule that they narrow down to one entry is not
/// this reader's job.
pub fn Pylock::packages(self : Pylock) -> Array[PylockPackage] {
  self.packages
}

///|
/// Every entry whose name matches `name` after `canonicalize_name`, in document
/// order. An unknown name yields an empty array.
pub fn Pylock::packages_named(
  self : Pylock,
  name : String,
) -> Array[PylockPackage] {
  let target = canonicalize_name(name)
  let out : Array[PylockPackage] = []
  for entry in self.packages {
    if canonicalize_name(entry.name) == target {
      out.push(entry)
    }
  }
  out
}

///|
/// Every file record of every entry for `name`, in document order, each entry
/// contributing the order of `PylockPackage::all_files`. This is the lookup an
/// audit wants: `files_for("attrs")` finds the wheels of an entry spelled
/// `Attrs` too, and an unknown name yields an empty array.
pub fn Pylock::files_for(self : Pylock, name : String) -> Array[PylockFile] {
  let out : Array[PylockFile] = []
  for entry in self.packages_named(name) {
    for file in entry.all_files() {
      out.push(file)
    }
  }
  out
}

///|
/// Every dependency record of every entry for `name`, in document order and
/// without deduplication: two entries for one name contribute two lists, because
/// they are two different resolutions.
pub fn Pylock::dependencies_of(
  self : Pylock,
  name : String,
) -> Array[PylockDependency] {
  let out : Array[PylockDependency] = []
  for entry in self.packages_named(name) {
    for dependency in entry.dependencies {
      out.push(dependency)
    }
  }
  out
}

///|
/// True when at least one entry for `name` applies to `environment`; false when
/// no entry has that name. Entries for other names are not considered.
pub fn Pylock::is_applicable(
  self : Pylock,
  name : String,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  for entry in self.packages_named(name) {
    if entry.is_applicable(environment) {
      return true
    }
  }
  false
}

///|
/// Every entry that applies to `environment`, in document order.
pub fn Pylock::applicable_packages(
  self : Pylock,
  environment : MarkerEnvironment,
) -> Array[PylockPackage] raise MarkerError {
  let out : Array[PylockPackage] = []
  for entry in self.packages {
    if entry.is_applicable(environment) {
      out.push(entry)
    }
  }
  out
}

///|
/// True when `environment` is one the lock file claims to support: the
/// specification's `environments` check, which is satisfied when the member is
/// absent and when at least one of its marker expressions holds.
pub fn Pylock::accepts_environment(
  self : Pylock,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  for text in self.environments {
    if marker_accepts(text, environment) {
      return true
    }
  }
  self.environments.length() == 0
}

///|
/// An `InvalidPylock` whose position is a *structural* index -- the ordinal of the
/// offending `[[packages]]` entry, or `0` for a document-level problem -- not a
/// byte offset, which the TOML layer has already forgotten.
fn pylock_error(code : String, ordinal : Int) -> VersionError {
  VersionError::InvalidPylock(code, ordinal)
}

///|
/// Evaluate a marker's text against `environment`.
///
/// The text was validated by `Pylock::parse`, so the parse cannot fail; the
/// fallback keeps this helper total instead of adding a second error channel to
/// the accessors. A caller that hands a marker to `Marker::parse` directly still
/// gets the real diagnosis.
fn marker_accepts(
  text : String,
  environment : MarkerEnvironment,
) -> Bool raise MarkerError {
  let parsed : Marker? = Some(Marker::parse(text)) catch { _ => None }
  match parsed {
    Some(marker) => marker.evaluate(environment)
    None => false
  }
}

///|
/// An optional string member: absent (or empty, see the module doc) is `None`, a
/// string is `Some`, and a value of any other type is `code`.
fn optional_text(
  table : Toml,
  key : String,
  code : String,
  ordinal : Int,
) -> String? raise VersionError {
  match table.get(key) {
    None => None
    Some(TString(value)) => if value.is_empty() { None } else { Some(value) }
    Some(_) => raise pylock_error(code, ordinal)
  }
}

///|
/// An optional array of strings: absent is `[]`, an entry of another type is
/// `entry_code`, and a value that is not an array at all is `type_code`.
fn string_list(
  table : Toml,
  key : String,
  type_code : String,
  entry_code : String,
  ordinal : Int,
) -> Array[String] raise VersionError {
  match table.get(key) {
    None => []
    Some(TArray(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          TString(value) => out.push(value)
          _ => raise pylock_error(entry_code, ordinal)
        }
      }
      out
    }
    Some(_) => raise pylock_error(type_code, ordinal)
  }
}

///|
/// A required sub-table: a value of another type, including a missing one, is
/// `code`.
fn require_table(
  table : Toml,
  key : String,
  code : String,
  ordinal : Int,
) -> Toml raise VersionError {
  match table.get(key) {
    Some(TTable(value)) => value
    _ => raise pylock_error(code, ordinal)
  }
}

///|
/// Validate a marker expression, mapping every failure to `code`. A marker text
/// the marker module rejects is rejected here, so `packages.marker`,
/// `environments` and a dependency's `marker` cannot hold a typo such as
/// `python_versoin >= "3.8"`.
fn validate_marker(
  text : String,
  code : String,
  ordinal : Int,
) -> Unit raise VersionError {
  ignore(Marker::parse(text)) catch {
    _ => raise pylock_error(code, ordinal)
  }
}

///|
/// Validate a version specifier set, mapping every failure to `code`. An empty
/// string is a valid set that constrains nothing, which is why a present but empty
/// `requires-python` is accepted.
fn validate_specifier(
  text : String,
  code : String,
  ordinal : Int,
) -> Unit raise VersionError {
  ignore(SpecifierSet::parse(text)) catch {
    _ => raise pylock_error(code, ordinal)
  }
}

///|
/// Validate a project or extra name with the PEP 508 syntax the requirement
/// reader uses, mapping a rejection to `code`.
fn validate_name(
  text : String,
  code : String,
  ordinal : Int,
) -> Unit raise VersionError {
  if !is_valid_requirement_name(text) {
    raise pylock_error(code, ordinal)
  }
}

///|
/// The `hashes` table of a file record: absent is `[]` (see the module doc), a
/// table is its `(algorithm, value)` pairs in document order, a table with no
/// entry is `FILE_HASHES_EMPTY` -- the specification's "MUST contain at least one
/// entry" -- and anything else is `FILE_HASHES_NOT_TABLE` or `FILE_HASH_TYPE`.
fn parse_hashes(
  table : Toml,
  ordinal : Int,
) -> Array[(String, String)] raise VersionError {
  match table.get("hashes") {
    None => []
    Some(TTable(hashes)) => {
      if hashes.entries.length() == 0 {
        raise pylock_error("FILE_HASHES_EMPTY", ordinal)
      }
      let out : Array[(String, String)] = []
      for entry in hashes.entries {
        match entry.1 {
          TString(value) => out.push((entry.0, value))
          _ => raise pylock_error("FILE_HASH_TYPE", ordinal)
        }
      }
      out
    }
    Some(_) => raise pylock_error("FILE_HASHES_NOT_TABLE", ordinal)
  }
}

///|
/// The `size` of a file record: absent is `None`, an integer is `Some`, a negative
/// integer is `FILE_SIZE_NEGATIVE` (a file cannot have one), and anything else is
/// `FILE_SIZE_TYPE`. The width is TOML's own `Int64`, because a wheel may be
/// larger than the `Int` a backend is happy to hold.
fn parse_size(table : Toml, ordinal : Int) -> Int64? raise VersionError {
  match table.get("size") {
    None => None
    Some(TInt(value)) =>
      if value < 0 {
        raise pylock_error("FILE_SIZE_NEGATIVE", ordinal)
      } else {
        Some(value)
      }
    Some(_) => raise pylock_error("FILE_SIZE_TYPE", ordinal)
  }
}

///|
/// The `upload-time` of a file record: absent is `None`, a TOML datetime is its
/// source spelling, and anything else -- a string included -- is
/// `FILE_UPLOAD_TIME_TYPE`. The specification's UTC rule is not checked here; the
/// spelling is what a caller gets, so an installation tool can apply its own rule.
fn parse_upload_time(table : Toml, ordinal : Int) -> String? raise VersionError {
  match table.get("upload-time") {
    None => None
    Some(TDatetime(text)) => Some(text)
    Some(_) => raise pylock_error("FILE_UPLOAD_TIME_TYPE", ordinal)
  }
}

///|
/// One file record, read from `files[i]`, `wheels[i]`, `sdist` or `archive`. The
/// record needs a name it can be found under: `name`, or a `url`/`path` whose last
/// component provides it, otherwise `FILE_NAME_REQUIRED`.
fn parse_file(
  table : Toml,
  kind : PylockFileKind,
  ordinal : Int,
) -> PylockFile raise VersionError {
  let name = optional_text(table, "name", "FILE_NAME_TYPE", ordinal)
  let url = optional_text(table, "url", "FILE_URL_TYPE", ordinal)
  let path = optional_text(table, "path", "FILE_PATH_TYPE", ordinal)
  if name is None && url is None && path is None {
    raise pylock_error("FILE_NAME_REQUIRED", ordinal)
  }
  let hashes = parse_hashes(table, ordinal)
  let size = parse_size(table, ordinal)
  let upload_time = parse_upload_time(table, ordinal)
  let subdirectory = optional_text(
    table, "subdirectory", "FILE_SUBDIRECTORY_TYPE", ordinal,
  )
  { name, url, path, hashes, size, upload_time, subdirectory, kind, }
}

///|
/// A `[[packages.files]]` or `[[packages.wheels]]` array: every element has to be a
/// table, and an element of another type is `FILE_NOT_TABLE`.
fn parse_file_list(
  items : Array[TomlValue],
  kind : PylockFileKind,
  ordinal : Int,
) -> Array[PylockFile] raise VersionError {
  let out : Array[PylockFile] = []
  for item in items {
    match item {
      TTable(value) => out.push(parse_file(value, kind, ordinal))
      _ => raise pylock_error("FILE_NOT_TABLE", ordinal)
    }
  }
  out
}

///|
/// `[packages.vcs]`: `type` must be a registered VCS, `commit-id` is required, and
/// one of `url` and `path` has to say where the repository is.
fn parse_vcs(table : Toml, ordinal : Int) -> PylockVcs raise VersionError {
  let vcs = require_table(table, "vcs", "VCS_NOT_TABLE", ordinal)
  let vcs_type = match vcs.get("type") {
    Some(TString(value)) if !value.is_empty() => value
    Some(TString(_)) | None => raise pylock_error("VCS_TYPE_REQUIRED", ordinal)
    Some(_) => raise pylock_error("VCS_TYPE_INVALID", ordinal)
  }
  match vcs_type {
    "git" | "hg" | "bzr" | "svn" => ()
    _ => raise pylock_error("VCS_TYPE_INVALID", ordinal)
  }
  let url = optional_text(vcs, "url", "VCS_URL_TYPE", ordinal)
  let path = optional_text(vcs, "path", "VCS_PATH_TYPE", ordinal)
  if url is None && path is None {
    raise pylock_error("VCS_URL_REQUIRED", ordinal)
  }
  let requested_revision = optional_text(
    vcs, "requested-revision", "VCS_REQUESTED_REVISION_TYPE", ordinal,
  )
  let commit_id = match
    optional_text(vcs, "commit-id", "VCS_COMMIT_ID_TYPE", ordinal) {
    Some(value) => value
    None => raise pylock_error("VCS_COMMIT_ID_REQUIRED", ordinal)
  }
  let subdirectory = optional_text(
    vcs, "subdirectory", "VCS_SUBDIRECTORY_TYPE", ordinal,
  )
  { vcs_type, url, path, requested_revision, commit_id, subdirectory, }
}

///|
/// `[packages.directory]`: `path` is required (a source tree has to be somewhere)
/// and `editable` defaults to `false`.
fn parse_directory(
  table : Toml,
  ordinal : Int,
) -> PylockDirectory raise VersionError {
  let directory = require_table(
    table, "directory", "DIRECTORY_NOT_TABLE", ordinal,
  )
  let path = match
    optional_text(directory, "path", "DIRECTORY_PATH_TYPE", ordinal) {
    Some(value) => value
    None => raise pylock_error("DIRECTORY_PATH_REQUIRED", ordinal)
  }
  let editable = match directory.get("editable") {
    None => false
    Some(TBool(value)) => value
    Some(_) => raise pylock_error("DIRECTORY_EDITABLE_TYPE", ordinal)
  }
  let subdirectory = optional_text(
    directory, "subdirectory", "DIRECTORY_SUBDIRECTORY_TYPE", ordinal,
  )
  { path, editable, subdirectory, }
}

///|
/// `[packages.archive]`: the same record shape as a wheel, plus the rule that a
/// direct reference to an archive has to say where the archive is (its `url` or
/// its `path`), because nothing else in the document can name it.
fn parse_archive(table : Toml, ordinal : Int) -> PylockFile raise VersionError {
  let archive = require_table(table, "archive", "ARCHIVE_NOT_TABLE", ordinal)
  let file = parse_file(archive, ArchiveFile, ordinal)
  if file.url is None && file.path is None {
    raise pylock_error("ARCHIVE_URL_REQUIRED", ordinal)
  }
  file
}

///|
/// One `[[packages.dependencies]]` entry.
///
/// `name` is required and has to be a valid project name; `version`, `marker` and
/// `extras` are read when present and validated like their counterparts
/// elsewhere. Rule 14 is enforced last: an entry that points at the package it
/// belongs to is `DEPENDENCY_SELF_REFERENCE`, which no resolution needs and which
/// is how a pruning bug in a locker shows up. A dependency whose `version` names a
/// *different* version of the same name is left alone, because the name may appear
/// in `[[packages]]` more than once.
fn parse_dependency(
  table : Toml,
  package_name : String,
  package_version : Version?,
  ordinal : Int,
) -> PylockDependency raise VersionError {
  let name = match table.get("name") {
    Some(TString(value)) if !value.is_empty() => value
    Some(TString(_)) | None =>
      raise pylock_error("DEPENDENCY_NAME_REQUIRED", ordinal)
    Some(_) => raise pylock_error("DEPENDENCY_NAME_TYPE", ordinal)
  }
  validate_name(name, "DEPENDENCY_NAME_INVALID", ordinal)
  let version = match table.get("version") {
    Some(TString(value)) if !value.is_empty() =>
      Some(Version::parse(value)) catch {
        _ => raise pylock_error("DEPENDENCY_VERSION_INVALID", ordinal)
      }
    Some(TString(_)) | None => None
    Some(_) => raise pylock_error("DEPENDENCY_VERSION_TYPE", ordinal)
  }
  let marker = optional_text(table, "marker", "DEPENDENCY_MARKER_TYPE", ordinal)
  match marker {
    Some(text) => validate_marker(text, "DEPENDENCY_MARKER_INVALID", ordinal)
    None => ()
  }
  let extras = string_list(
    table, "extras", "DEPENDENCY_EXTRAS_NOT_ARRAY", "DEPENDENCY_EXTRAS_ENTRY_TYPE",
    ordinal,
  )
  for extra in extras {
    validate_name(extra, "DEPENDENCY_EXTRA_INVALID", ordinal)
  }
  let self_reference = if canonicalize_name(name) !=
    canonicalize_name(package_name) {
    false
  } else {
    match version {
      None => true
      Some(dependency_version) =>
        match package_version {
          None => true
          Some(package_version) =>
            Version::compare(dependency_version, package_version) == 0
        }
    }
  }
  if self_reference {
    raise pylock_error("DEPENDENCY_SELF_REFERENCE", ordinal)
  }
  { name, version, marker, extras, }
}

///|
/// The source members of a package, in the order rule 15's conflict is checked in:
/// the direct references first, then the file lists. This is a function rather
/// than a `const` because this toolchain only allows immutable primitives as
/// constants and an `Array` is not one.
fn source_keys() -> Array[String] {
  ["vcs", "directory", "archive", "path", "files", "wheels", "sdist"]
}

///|
/// True when `key` is a member of the package table with a value (an empty string
/// counts as absent, per the module doc).
fn has_member(table : Toml, key : String) -> Bool {
  match table.get(key) {
    None => false
    Some(TString(value)) => !value.is_empty()
    Some(_) => true
  }
}

///|
/// Enforce rule 15 before anything else in the entry is interpreted, so the
/// conflict a document reports does not depend on the order its members happen to
/// be written in. Two direct references, or a direct reference next to a file
/// list, conflict.
fn check_sources(table : Toml, ordinal : Int) -> Unit raise VersionError {
  let mut direct = 0
  let mut lists = 0
  for key in source_keys() {
    if has_member(table, key) {
      match key {
        "vcs" | "directory" | "archive" | "path" => direct = direct + 1
        _ => lists = lists + 1
      }
    }
  }
  if direct > 1 || (direct > 0 && lists > 0) {
    raise pylock_error("PACKAGE_SOURCE_CONFLICT", ordinal)
  }
}

///|
/// One `[[packages]]` entry.
///
/// The checks run in a fixed order so the error a broken entry reports is
/// deterministic: `name` (rule 9), the source conflict (rule 15), `version`
/// (rule 10), `marker` (rule 11), `requires-python` (rule 12), the dependencies
/// (rules 13 and 14), and then the source members in the order `vcs`,
/// `directory`, `archive`, `files`, `wheels`, `sdist`, `index`, `path`.
fn parse_package(
  table : Toml,
  ordinal : Int,
) -> PylockPackage raise VersionError {
  let name = match table.get("name") {
    Some(TString(value)) if !value.is_empty() => value
    Some(TString(_)) | None =>
      raise pylock_error("PACKAGE_NAME_REQUIRED", ordinal)
    Some(_) => raise pylock_error("PACKAGE_NAME_TYPE", ordinal)
  }
  validate_name(name, "PACKAGE_NAME_INVALID", ordinal)
  check_sources(table, ordinal)
  let direct_reference = has_member(table, "vcs") ||
    has_member(table, "directory") ||
    has_member(table, "archive") ||
    has_member(table, "path")
  let version = match table.get("version") {
    Some(TString(value)) if !value.is_empty() =>
      Some(Version::parse(value)) catch {
        _ => raise pylock_error("PACKAGE_VERSION_INVALID", ordinal)
      }
    Some(TString(_)) | None =>
      if direct_reference {
        None
      } else {
        raise pylock_error("PACKAGE_VERSION_REQUIRED", ordinal)
      }
    Some(_) => raise pylock_error("PACKAGE_VERSION_TYPE", ordinal)
  }
  let marker = optional_text(table, "marker", "PACKAGE_MARKER_TYPE", ordinal)
  match marker {
    Some(text) => validate_marker(text, "PACKAGE_MARKER_INVALID", ordinal)
    None => ()
  }
  let requires_python = optional_text(
    table, "requires-python", "PACKAGE_REQUIRES_PYTHON_TYPE", ordinal,
  )
  match requires_python {
    Some(text) =>
      validate_specifier(text, "PACKAGE_REQUIRES_PYTHON_INVALID", ordinal)
    None => ()
  }
  let dependencies = match table.get("dependencies") {
    None => []
    Some(TArray(items)) => {
      let out : Array[PylockDependency] = []
      for item in items {
        match item {
          TTable(value) =>
            out.push(parse_dependency(value, name, version, ordinal))
          _ => raise pylock_error("DEPENDENCY_NOT_TABLE", ordinal)
        }
      }
      out
    }
    Some(_) => raise pylock_error("DEPENDENCIES_NOT_ARRAY", ordinal)
  }
  let vcs = match table.get("vcs") {
    None => None
    Some(TTable(_)) => Some(parse_vcs(table, ordinal))
    Some(_) => raise pylock_error("VCS_NOT_TABLE", ordinal)
  }
  let directory = match table.get("directory") {
    None => None
    Some(TTable(_)) => Some(parse_directory(table, ordinal))
    Some(_) => raise pylock_error("DIRECTORY_NOT_TABLE", ordinal)
  }
  let archive = match table.get("archive") {
    None => None
    Some(TTable(_)) => Some(parse_archive(table, ordinal))
    Some(_) => raise pylock_error("ARCHIVE_NOT_TABLE", ordinal)
  }
  let files = match table.get("files") {
    None => []
    Some(TArray(items)) => parse_file_list(items, FilesEntry, ordinal)
    Some(_) => raise pylock_error("FILES_NOT_ARRAY", ordinal)
  }
  let wheels = match table.get("wheels") {
    None => []
    Some(TArray(items)) => parse_file_list(items, WheelFile, ordinal)
    Some(_) => raise pylock_error("WHEELS_NOT_ARRAY", ordinal)
  }
  let sdist = match table.get("sdist") {
    None => None
    Some(TTable(value)) => Some(parse_file(value, SdistFile, ordinal))
    Some(_) => raise pylock_error("SDIST_NOT_TABLE", ordinal)
  }
  let index = optional_text(table, "index", "INDEX_TYPE", ordinal)
  let path = optional_text(table, "path", "PATH_TYPE", ordinal)
  {
    name,
    version,
    marker,
    requires_python,
    dependencies,
    files,
    wheels,
    sdist,
    archive,
    vcs,
    directory,
    index,
    path,
  }
}

///|
/// Parse and validate a `pylock.toml` document.
///
/// The checks run in a fixed order, so a broken document reports the same error
/// every time: the top-level members in the specification's own order
/// (rules 1 to 7), then `packages` (rule 8) and each entry in document order
/// (rules 9 to 20). Text that is not TOML is rejected by `Toml::parse` with
/// `VersionError::InvalidToml` before any pylock rule runs.
///
/// ```moonbit nocheck
/// let lock = Pylock::parse(
///   "lock-version = \"1.0\"\ncreated-by = \"demo\"\n\n[[packages]]\nname = \"attrs\"\nversion = \"25.1.0\"\n[[packages.wheels]]\nname = \"attrs-25.1.0-py3-none-any.whl\"\nhashes = { sha256 = \"c75a69e2\" }\n",
/// )
/// lock.files_for("attrs")[0].filename()   // Some("attrs-25.1.0-py3-none-any.whl")
/// ```
pub fn Pylock::parse(text : String) -> Pylock raise VersionError {
  let document = Toml::parse(text)
  // Rule 1: lock-version is required, and the file format version this reader
  // implements is the only one it accepts.
  let lock_version = match document.get("lock-version") {
    Some(TString(value)) if !value.is_empty() => value
    Some(TString(_)) | None => raise pylock_error("LOCK_VERSION_REQUIRED", 0)
    Some(_) => raise pylock_error("LOCK_VERSION_TYPE", 0)
  }
  if lock_version != PYLOCK_LOCK_VERSION {
    raise pylock_error("LOCK_VERSION_INVALID", 0)
  }
  // Rule 2: environments are PEP 508 markers, and PEP 751 adds `extras` and
  // `dependency_groups` to the vocabulary for them, which `markers.mbt` already
  // knows.
  let environments = string_list(
    document, "environments", "ENVIRONMENTS_NOT_ARRAY", "ENVIRONMENTS_ENTRY_TYPE",
    0,
  )
  for marker_text in environments {
    validate_marker(marker_text, "ENVIRONMENT_MARKER_INVALID", 0)
  }
  // Rule 3.
  let requires_python = optional_text(
    document, "requires-python", "REQUIRES_PYTHON_TYPE", 0,
  )
  match requires_python {
    Some(value) => validate_specifier(value, "REQUIRES_PYTHON_INVALID", 0)
    None => ()
  }
  // Rule 4.
  let extras = string_list(
    document, "extras", "EXTRAS_NOT_ARRAY", "EXTRAS_ENTRY_TYPE", 0,
  )
  for extra in extras {
    validate_name(extra, "EXTRA_INVALID", 0)
  }
  // Rule 5.
  let dependency_groups = string_list(
    document, "dependency-groups", "DEPENDENCY_GROUPS_NOT_ARRAY", "DEPENDENCY_GROUPS_ENTRY_TYPE",
    0,
  )
  for group in dependency_groups {
    validate_name(group, "DEPENDENCY_GROUP_INVALID", 0)
  }
  // Rule 6.
  let default_groups = string_list(
    document, "default-groups", "DEFAULT_GROUPS_NOT_ARRAY", "DEFAULT_GROUPS_ENTRY_TYPE",
    0,
  )
  for group in default_groups {
    validate_name(group, "DEFAULT_GROUP_INVALID", 0)
  }
  // Rule 7. The specification requires created-by; see the module doc for why its
  // absence is accepted.
  let created_by = optional_text(document, "created-by", "CREATED_BY_TYPE", 0)
  // Rule 8.
  let packages = match document.get("packages") {
    None => raise pylock_error("PACKAGES_REQUIRED", 0)
    Some(TArray(items)) => {
      let out : Array[PylockPackage] = []
      for i = 0; i < items.length(); i = i + 1 {
        match items[i] {
          TTable(value) => out.push(parse_package(value, i))
          _ => raise pylock_error("PACKAGE_NOT_TABLE", i)
        }
      }
      out
    }
    Some(_) => raise pylock_error("PACKAGES_NOT_ARRAY", 0)
  }
  {
    lock_version,
    environments,
    requires_python,
    extras,
    dependency_groups,
    default_groups,
    created_by,
    packages,
  }
}
