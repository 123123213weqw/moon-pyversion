///|
/// Scenario 2, end to end: from a PEP 691 index response to the one file a
/// resolver would install.
///
/// Scenario 1 (`examples/metadata-check`) reads what a project *declares*. This
/// example reads what an index *offers*, and answers the question a resolver
/// asks first: which of these files may I install here, and why not the others?
///
/// The report has five parts:
///
/// 1. the document is parsed and validated (`SimpleIndex::parse`), so a
///    malformed response is reported with a stable code instead of being
///    half-read, and the PEP 700 `versions` member is listed;
/// 2. every `files[]` entry is turned into an installable file
///    (`SimpleIndexFile::to_index_file`), which is where a name that is neither
///    a PEP 427 wheel nor a PEP 625 sdist is refused with `INDEX_UNKNOWN_DIST`;
/// 3. the PEP 592 yank policy is applied *by this example*: the library has no
///    yank policy on purpose -- `IndexFile` carries no yank field, because the
///    caller that read `SimpleIndexFile::yanked` is the one that knows whether
///    a yanked release is acceptable;
/// 4. the requirement is resolved against the target's tags
///    (`resolve_candidates`), and every dropped file is printed with the first
///    rule that dropped it (`explain_rejection`);
/// 5. the same requirement is resolved against a *directory* instead of an
///    index (`LocalIndex::scan` with an injected `DirectoryLister`), which is
///    how a tool resolves from a wheelhouse with no network.
///
/// ## Why the inputs are compiled in
///
/// The library depends on `moonbitlang/core` only. That package has no
/// filesystem package and no HTTP client on the pinned toolchain, and the
/// library deliberately never reads the host environment -- a report has to be
/// replayable. So the index document, the tag list and the directory listing
/// are all written out below; an application replaces `demo_index()` with the
/// body of a response, `target_tags()` with the host's own tag order, and
/// `wheelhouse_lister` with an adapter around whatever listing API it can
/// reach.
///
/// Everything here is deterministic: no clock, no environment, no I/O. The
/// output is byte identical on wasm, wasm-gc, js and native.
///
/// ```sh
/// moon run examples/resolve --target js
/// ```

///|
/// One `files[]` entry next to its PEP 592 state, so the yank policy can run
/// before resolution and the two halves stay together.
struct Converted {
  file : @pyversion.IndexFile
  yanked : @pyversion.SimpleYanked
}

///|
/// The tags of the target, most specific first.
///
/// The order is the order `packaging.tags.sys_tags()` produces, not an
/// invention: these are the twelve tags that any file in `demo_index()` can
/// match, and they sit at positions 0, 19, 20, 35, 54, 70, 89, 385, 404, 420,
/// 439 and 807 of the 818-tag list that `sys_tags()` returns on CPython 3.10.12
/// x86_64 Linux. The subset is closed under the document -- no wheel below has
/// a tag that would sort between two entries here -- so the ranking this
/// example prints is the ranking pip would compute.
///
/// The list is written out rather than computed because the library never
/// inspects the host: `resolve_candidates` takes tags from its caller.
fn target_tags() -> Array[String] {
  [
    "cp310-cp310-linux_x86_64", "cp310-cp310-manylinux_2_17_x86_64", "cp310-cp310-manylinux2014_x86_64",
    "cp310-abi3-linux_x86_64", "cp310-abi3-manylinux_2_17_x86_64", "cp310-none-linux_x86_64",
    "cp310-none-manylinux_2_17_x86_64", "py310-none-linux_x86_64", "py310-none-manylinux_2_17_x86_64",
    "py3-none-linux_x86_64", "py3-none-manylinux_2_17_x86_64", "py3-none-any",
  ]
}

///|
/// The interpreter of the target. `3.10.12` is a version this library parses;
/// the abort is unreachable and documents the assumption.
fn target_python() -> @pyversion.Version {
  @pyversion.Version::parse("3.10.12") catch {
    _ => abort("3.10.12 must parse")
  }
}

///|
/// A synthetic PEP 691 response for one project.
///
/// The digests are placeholders -- nothing here downloads a file, so no digest
/// is verified; `SimpleIndexFile::hash_for` is asked for one anyway, to show
/// that the member is kept as published. The document covers every rule the
/// resolver has:
///
/// - `1.1.0` is excluded by the requirement's own `!=`;
/// - `1.2.0rc1` and `1.4.0` are **yanked** (PEP 592), both under a reason
///   string, which is the spelling PEP 592 recommends; `0.9.0` spells the
///   `false` that PEP 592 also allows, and the two other files omit the member
///   entirely, which PEP 592 reads as "not yanked";
/// - `1.3.0b1` is a prerelease that PEP 440's automatic policy drops while a
///   final release matches;
/// - `2.0.0` exists twice with `Requires-Python: >=3.12`, which the 3.10 target
///   fails, and once as a `cp311` wheel, which the target's tags reject;
/// - `1.2.1` exists as a `cp310` wheel and as a pure-Python wheel, so the tag
///   ranking decides between two files of the *same* version;
/// - `1.2.0` exists as a wheel and as an sdist, so the wheel-before-sdist
///   tie-break is exercised;
/// - `other_thing-1.0.0` belongs to another project -- PEP 691 would not put
///   it in this document, and it is here to show that the resolver refuses it
///   by name, which is the rule that matters when a caller hands it files from
///   several sources at once (a wheelhouse, a second index, a mirror);
/// - `demo_light-0.8.0.tar.bz2` is not a distribution file at all (PEP 625
///   allows `.tar.gz` and `.zip`), so `to_index_file` refuses it.
///
/// One entry also carries the PEP 658 `core-metadata` member, which PEP 691
/// requires clients to ignore: this library ignores it too and reports the
/// absence of the sidecar rather than guessing at it.
fn demo_index() -> String {
  let lines : Array[String] = [
    "{", "  \"meta\": { \"api-version\": \"1.1\" },", "  \"name\": \"demo_light\",",
    "  \"versions\": [\"0.9.0\", \"1.0.0\", \"1.1.0\", \"1.2.0rc1\", \"1.2.0\",",
    "               \"1.2.1\", \"1.3.0b1\", \"1.4.0\", \"2.0.0\"],", "  \"files\": [",
    "    {\"filename\": \"demo_light-0.9.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-0.9.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"0e00\"}, \"requires-python\": \">=3.7\", \"yanked\": false},",
    "    {\"filename\": \"demo_light-1.0.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.0.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"1e00\"}, \"requires-python\": \">=3.7\"},",
    "    {\"filename\": \"demo_light-1.1.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.1.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"2e00\"}, \"requires-python\": \">=3.8\"},",
    "    {\"filename\": \"demo_light-1.2.0rc1-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.2.0rc1-py3-none-any.whl\", \"hashes\": {\"sha256\": \"3e00\"}, \"requires-python\": \">=3.8\", \"yanked\": \"wheel was built from the wrong commit\"},",
    "    {\"filename\": \"demo_light-1.2.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.2.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"4e00\"}, \"requires-python\": \">=3.9\"},",
    "    {\"filename\": \"demo_light-1.2.0.tar.gz\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.2.0.tar.gz\", \"hashes\": {\"sha256\": \"5e00\"}, \"requires-python\": \">=3.9\", \"size\": 41234, \"upload-time\": \"2024-03-01T09:15:00Z\"},",
    "    {\"filename\": \"demo_light-1.2.1-cp310-cp310-manylinux_2_17_x86_64.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.2.1-cp310-cp310-manylinux_2_17_x86_64.whl\", \"hashes\": {\"sha256\": \"6e00\"}, \"requires-python\": \">=3.9\"},",
    "    {\"filename\": \"demo_light-1.2.1-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.2.1-py3-none-any.whl\", \"hashes\": {\"sha256\": \"7e00\"}, \"requires-python\": \">=3.9\", \"core-metadata\": {\"sha256\": \"7e00\"}},",
    "    {\"filename\": \"demo_light-1.3.0b1-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.3.0b1-py3-none-any.whl\", \"hashes\": {\"sha256\": \"8e00\"}, \"requires-python\": \">=3.9\"},",
    "    {\"filename\": \"demo_light-1.4.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-1.4.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"9e00\"}, \"requires-python\": \">=3.9\", \"yanked\": \"the 1.4.0 wheels were built with the wrong ABI tag\"},",
    "    {\"filename\": \"demo_light-2.0.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-2.0.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"ae00\"}, \"requires-python\": \">=3.12\"},",
    "    {\"filename\": \"demo_light-2.0.0-cp311-cp311-manylinux_2_17_x86_64.whl\", \"url\": \"https://files.example.invalid/demo_light/demo_light-2.0.0-cp311-cp311-manylinux_2_17_x86_64.whl\", \"hashes\": {\"sha256\": \"be00\"}, \"requires-python\": \">=3.8\"},",
    "    {\"filename\": \"other_thing-1.0.0-py3-none-any.whl\", \"url\": \"https://files.example.invalid/other_thing/other_thing-1.0.0-py3-none-any.whl\", \"hashes\": {\"sha256\": \"ce00\"}, \"requires-python\": \">=3.7\"},",
    "    {\"filename\": \"demo_light-0.8.0.tar.bz2\", \"url\": \"https://files.example.invalid/demo_light/demo_light-0.8.0.tar.bz2\", \"hashes\": {\"sha256\": \"de00\"}}",
    "  ]", "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// `text` padded on the right with spaces to `width`, or unchanged when it is
/// already at least that wide. `String::length` counts code points, which is
/// what a fixed-width column needs for the ASCII names here.
fn pad(text : String, width : Int) -> String {
  let mut out = text
  let mut width_left = width - text.length()
  while width_left > 0 {
    out = out + " "
    width_left = width_left - 1
  }
  out
}

///|
/// `entry` as an installable file, or the stable code that says why it is not
/// one. `to_index_file` raises `INDEX_UNKNOWN_DIST` for an entry that is
/// neither a wheel nor an sdist; this keeps the code instead of the message, so
/// the report stays machine readable.
fn convert_entry(
  entry : @pyversion.SimpleIndexFile,
) -> (@pyversion.IndexFile?, String) {
  let file = entry.to_index_file() catch {
    @pyversion.VersionError::InvalidIndex(code, _) => return (None, code)
    _ => return (None, "INVALID_INDEX")
  }
  (Some(file), "")
}

///|
/// Every `files[]` entry, split into the ones the resolver may consider and the
/// ones that are not distribution files at all.
fn convert(
  index : @pyversion.SimpleIndex,
) -> (Array[Converted], Array[(String, String)]) {
  let converted : Array[Converted] = []
  let unconvertible : Array[(String, String)] = []
  for entry in index.files() {
    let (file, code) = convert_entry(entry)
    match file {
      None => unconvertible.push((entry.filename, code))
      Some(parsed) => converted.push({ file: parsed, yanked: entry.yanked, })
    }
  }
  (converted, unconvertible)
}

///|
/// The first tag of `file` that the target supports, or `None` for an sdist and
/// for a wheel that matches nothing. The result is checked against `supported`
/// in order, so it is also the file's rank among the target's tags.
fn matched_tag(
  file : @pyversion.IndexFile,
  supported : Array[String],
) -> String? {
  let mut best : String? = None
  let mut best_rank = supported.length()
  for tag in file.tags() {
    for rank = 0; rank < supported.length(); rank = rank + 1 {
      if supported[rank] == tag && rank < best_rank {
        best_rank = rank
        best = Some(tag)
      }
    }
  }
  best
}

///|
/// `"wheel"` or `"sdist"`, the two kinds `IndexFileKind` has.
fn kind_name(file : @pyversion.IndexFile) -> String {
  match file.kind {
    WheelFile => "wheel"
    SdistFile => "sdist"
  }
}

///|
/// The rules `explain_rejection` can report, in the order it applies them. The
/// strings are the library's stable API, and the order is what makes the report
/// explainable: `name` is checked before `version`, so another project's file
/// is never blamed on its version.
fn rejection_rules() -> Array[String] {
  ["name", "version", "prerelease", "requires-python", "tags"]
}

///|
/// How many rejections have `reason`, and one filename that has it.
fn count_reason(
  rejections : Array[(String, String)],
  reason : String,
) -> (Int, String?) {
  let mut count = 0
  let mut first : String? = None
  for entry in rejections {
    if entry.1 == reason {
      count = count + 1
      if first is None {
        first = Some(entry.0)
      }
    }
  }
  (count, first)
}

///|
/// One PEP 592 policy, written here rather than in the library: prefer files
/// that are not yanked, and fall back to the yanked ones only when a project
/// has nothing else, which is what pip's `CandidateEvaluator` does by putting
/// its yank flag ahead of the version in the sort key.
///
/// Returns the pool to resolve against and the `(filename, reason)` of every
/// file the policy dropped.
fn apply_yank_policy(
  files : Array[Converted],
) -> (Array[Converted], Array[(String, String)]) {
  let unyanked : Array[Converted] = []
  let dropped : Array[(String, String)] = []
  for entry in files {
    match entry.yanked {
      NotYanked => unyanked.push(entry)
      Yanked(reason) => {
        let text = if reason.is_empty() {
          "PEP 592 boolean true, no reason given"
        } else {
          reason
        }
        dropped.push((entry.file.filename, text))
      }
    }
  }
  if unyanked.is_empty() {
    (files, dropped)
  } else {
    (unyanked, dropped)
  }
}

///|
/// The `IndexFile` projections of a converted array, in order.
fn map_files(entries : Array[Converted]) -> Array[@pyversion.IndexFile] {
  let out : Array[@pyversion.IndexFile] = []
  for entry in entries {
    out.push(entry.file)
  }
  out
}

///|
/// Resolve one requirement against the converted index and print the report:
/// the yank policy, what was rejected and why, the candidate order, and the
/// pick.
fn report_requirement(
  converted : Array[Converted],
  tags : Array[String],
  python : @pyversion.Version,
  raw : String,
) -> Unit {
  println("== requirement  \{raw}")
  let requirement = @pyversion.Requirement::parse(raw) catch {
    error => {
      println("   INVALID REQUIREMENT: \{error.diagnostic()}")
      return
    }
  }
  let project = @pyversion.canonicalize_name(requirement.name)
  let mine : Array[Converted] = []
  let foreign : Array[String] = []
  for entry in converted {
    if entry.file.name == project {
      mine.push(entry)
    } else {
      foreign.push(entry.file.filename)
    }
  }
  // The pool is every file the document offers, not just this project's slice:
  // `resolve_candidates` checks the name first, so a caller that concatenates
  // several sources gets the wrong project refused instead of silently
  // installed. PEP 691 would not mix two projects in one document; a caller
  // that fans out over indexes has to assume it might.
  let (pool_entries, dropped) = apply_yank_policy(converted)
  println(
    "   \{mine.length()} file(s) of \{project}, \{foreign.length()} of another project, \{pool_entries.length()} offered to the resolver",
  )
  for entry in dropped {
    println("   yanked, dropped: \{entry.0}")
    println("      reason: \{entry.1}")
  }
  let pool = map_files(pool_entries)
  let rejected = @pyversion.explain_rejection(
    pool,
    requirement,
    tags,
    Some(python),
  )
  let candidates = @pyversion.resolve_candidates(
    pool,
    requirement,
    tags,
    Some(python),
  )
  println("   rejected \{rejected.length()} of \{pool.length()}:")
  for rule in rejection_rules() {
    let (count, first) = count_reason(rejected, rule)
    if count > 0 {
      println(
        "      \{pad(rule, 17)}\{pad(count.to_string(), 3)}   e.g. \{first.unwrap()}",
      )
    }
  }
  println("   candidates \{candidates.length()}, best first:")
  for candidate in candidates {
    let rank = match matched_tag(candidate, tags) {
      None => "no tag (an sdist)"
      Some(tag) => tag
    }
    println(
      "      \{pad(candidate.version.to_string(), 9)}\{pad(kind_name(candidate), 7)}\{pad(rank, 40)}\{candidate.filename}",
    )
  }
  match @pyversion.select_best(pool, requirement, tags, Some(python)) {
    None =>
      println("   -> no candidate: every file fails the requirement itself")
    Some(file) => {
      println("   -> selected  \{file.filename}")
      // The same files with no yank policy, to show that the policy is what
      // decided -- and that dropping it changes the answer.
      match
        @pyversion.select_best(
          map_files(converted),
          requirement,
          tags,
          Some(python),
        ) {
        Some(other) =>
          if other.filename != file.filename {
            println(
              "      with no yank policy it would be \{other.filename} (PEP 592 state ignored)",
            )
          }
        None => ()
      }
    }
  }
  println("")
}

///|
/// The entries of the wheelhouse `wheelhouse_lister` answers with: five
/// distribution files of the project, plus two names that `LocalIndex::scan`
/// must ignore. There is no `1.4.0` yank state here, because a directory has
/// nowhere to record one -- which is the point of the contrast with the index
/// run above.
fn wheelhouse_entries() -> Array[String] {
  [
    "demo_light-1.2.1-py3-none-any.whl", "demo_light-1.4.0-py3-none-any.whl", "demo_light-1.3.0b1-py3-none-any.whl",
    "demo_light-1.2.0-py3-none-any.whl", "demo_light-1.2.0.tar.gz", "README.txt",
    "demo_light-1.2.1-py3-none-any.whl.sha256",
  ]
}

///|
/// The injected `DirectoryLister`: `moonbitlang/core` on the pinned toolchain
/// has no filesystem package, so this module cannot list a directory itself and
/// takes a function of this shape instead. A host with a filesystem passes an
/// adapter around its own `read_dir`, and the resolver code above is unchanged.
fn wheelhouse_lister(
  directory : String,
) -> Array[String] raise @pyversion.VersionError {
  if directory != "/srv/wheels" {
    raise @pyversion.VersionError::InvalidIndex("INDEX_NO_FS", 0)
  }
  wheelhouse_entries()
}

///|
/// The code the *default* lister produces, so the example can print what a
/// caller that forgot to inject one sees. `LocalIndex::scan` documents the
/// default as raising rather than returning an empty index, because "no
/// filesystem" and "no wheels" must not look alike.
fn default_lister_code() -> String {
  let _ = @pyversion.LocalIndex::scan("/srv/wheels") catch {
    error => return error.diagnostic()
  }
  "(scan unexpectedly succeeded)"
}

///|
/// The offline half of the report: the same requirement against a directory.
fn report_directory(tags : Array[String], python : @pyversion.Version) -> Unit {
  println("== the same requirement in a wheelhouse (no index, no network)")
  let scanned = @pyversion.LocalIndex::scan(
    "/srv/wheels",
    lister=wheelhouse_lister,
  ) catch {
    error => {
      println("   scan failed: \{error.diagnostic()}")
      return
    }
  }
  println(
    "   /srv/wheels: \{wheelhouse_entries().length()} entries, \{scanned.files.length()} distribution file(s), \{wheelhouse_entries().length() - scanned.files.length()} ignored",
  )
  let packages = scanned.packages().join(", ")
  println("   packages: \{packages}")
  let files = scanned.files_for("Demo.Light")
  println(
    "   files_for(\"Demo.Light\") -> \{files.length()} file(s) (PEP 503 normalization)",
  )
  let requirement = @pyversion.Requirement::parse("demo-light>=1.0,!=1.1.0") catch {
    error => {
      println("   INVALID REQUIREMENT: \{error.diagnostic()}")
      return
    }
  }
  let rejected = @pyversion.explain_rejection(
    files,
    requirement,
    tags,
    Some(python),
  )
  println("   rejected \{rejected.length()} of \{files.length()}:")
  for rule in rejection_rules() {
    let (count, first) = count_reason(rejected, rule)
    if count > 0 {
      println(
        "      \{pad(rule, 17)}\{pad(count.to_string(), 3)}   e.g. \{first.unwrap()}",
      )
    }
  }
  let candidates = @pyversion.resolve_candidates(
    files,
    requirement,
    tags,
    Some(python),
  )
  println("   candidates \{candidates.length()}, best first:")
  for candidate in candidates {
    let rank = match matched_tag(candidate, tags) {
      None => "no tag (an sdist)"
      Some(tag) => tag
    }
    println(
      "      \{pad(candidate.version.to_string(), 9)}\{pad(kind_name(candidate), 7)}\{pad(rank, 40)}\{candidate.filename}",
    )
  }
  match @pyversion.select_best(files, requirement, tags, Some(python)) {
    None => println("   -> no candidate in the directory")
    Some(file) => println("   -> selected  \{file.filename}")
  }
  println(
    "   note: a directory carries no PEP 592 state, so the yanked 1.4.0 wins here",
  )
  println("   default lister: \{default_lister_code()}")
  println("")
}

///|
/// The header: what the document is, and the members of one entry that a
/// resolver reads but this example does not otherwise use.
fn report_header(
  index : @pyversion.SimpleIndex,
  converted : Array[Converted],
  unconvertible : Array[(String, String)],
) -> Unit {
  let api = match index.api_version() {
    None => "(absent)"
    Some(version) => version
  }
  println("== an index response")
  println(
    "   \{index.name()}, api-version \{api}: \{index.files().length()} entries, \{converted.length()} installable, \{unconvertible.length()} not a distribution file",
  )
  let versions = index.versions().join(" ")
  println("   versions (PEP 700): \{versions}")
  for entry in unconvertible {
    println("   \{entry.0}: \{entry.1}")
  }
  for entry in index.files() {
    if entry.filename == "demo_light-1.2.0.tar.gz" {
      let digest = match entry.hash_for("sha256") {
        None => "(none published)"
        Some(value) => value
      }
      let specifiers = match entry.requires_python {
        None => "(absent)"
        Some(text) => text
      }
      let size = match entry.size {
        None => "(absent)"
        Some(value) => value.to_string()
      }
      let uploaded = match entry.upload_time {
        None => "(absent)"
        Some(value) => value
      }
      println("   \{entry.filename}:")
      println("      sha256 \{digest}")
      println(
        "      requires-python \{specifiers}, size \{size}, uploaded \{uploaded}",
      )
    }
  }
  println("")
}

///|
fn report(index : @pyversion.SimpleIndex) -> Unit {
  let tags = target_tags()
  let python = target_python()
  let (converted, unconvertible) = convert(index)
  report_header(index, converted, unconvertible)
  println(
    "target: CPython \{python.to_string()}, x86_64 linux, \{tags.length()} tags, most specific first",
  )
  println("")
  for
    raw in ["demo-light>=1.0,!=1.1.0", "demo-light==1.3.0b1", "demo-light>=3.0"] {
    report_requirement(converted, tags, python, raw)
  }
  report_directory(tags, python)
}

///|
fn main {
  match
    (Some(@pyversion.SimpleIndex::parse(demo_index())) catch { _ => None }) {
    None => println("the compiled-in index document does not parse")
    Some(index) => report(index)
  }
}
