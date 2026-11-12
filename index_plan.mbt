///|
/// The version inside a wheel or sdist filename; the file-kind decides
/// which parser. Neither is a filename - refused.
fn version_from_filename(filename : String) -> Version raise VersionError {
  if filename.has_suffix(".whl") {
    parse_wheel_filename(filename).version
  } else if filename.has_suffix(".tar.gz") || filename.has_suffix(".zip") {
    parse_sdist_filename(filename).version
  } else {
    raise VersionError::InvalidFilename("UNKNOWN_DIST_EXTENSION", 0)
  }
}

///|
/// One viable installation target picked from a PEP 691 simple index:
/// the file entry, its parsed version, and how it survived every gate.
#derive(@debug.Debug)
pub(all) struct IndexCandidate {
  file : SimpleIndexFile
  version : Version
}

///|
pub extend IndexCandidate with @debug.Debug::{to_repr}

///|
pub extend IndexExclusion with @debug.Debug::{to_repr}

///|
/// Why a file entry did not become a candidate. Each refusal names the
/// entry and the reason, the same discipline as the requirement side.
#derive(@debug.Debug)
pub(all) enum IndexExclusion {
  /// The filename's version does not parse.
  UnparseableVersion(String)
  /// The entry is yanked (value is the reason text when given).
  Yanked(String)
  /// requires-python is present and the runtime is outside it.
  PythonIncompatible(String, String)
  /// The version is outside the caller's constraint.
  OutOfRange(String)
  /// A prerelease outside the prerelease policy.
  Prerelease(String)
}

///|
/// Select installation candidates from a simple index: the pip-side
/// counterpart of the requirement judgment. Every file entry's version
/// is parsed from its filename; yanked entries, entries whose
/// requires-python excludes the given python, and versions outside the
/// constraint (when one is given) are excluded with the reason kept -
/// the answer is the candidates in index order plus every exclusion,
/// so the caller can show both what to install and what was passed
/// over and why. The prerelease policy defaults to preferring final
/// releases but falling back to prereleases when no final release
/// survives the other gates, exactly pip's default.
pub fn select_candidates(
  index : SimpleIndex,
  python : String?,
  constraints : SpecifierSet?,
  prereleases~ : Bool? = None,
) -> (Array[IndexCandidate], Array[(String, IndexExclusion)]) raise VersionError {
  let candidates : Array[IndexCandidate] = []
  let exclusions : Array[(String, IndexExclusion)] = []
  let python_version = match python {
    None => None
    Some(text) => Some(Version::parse(text))
  }
  for i = 0; i < index.files.length(); i = i + 1 {
    let file = index.files[i]
    let filename = file.filename
    // The version from the filename; a bad name excludes, not aborts -
    // a real index has junk in it and the junk must be visible.
    let parsed = Some(version_from_filename(filename)) catch { _ => None }
    let version = match parsed {
      None => {
        exclusions.push((filename, UnparseableVersion(filename)))
        continue
      }
      Some(v) => v
    }
    // Yanked.
    match file.yanked {
      NotYanked => ()
      Yanked(reason) => {
        exclusions.push((filename, Yanked(reason)))
        continue
      }
    }
    // requires-python.
    match (file.requires_python, python_version) {
      (None, _) => ()
      (Some(spec_text), Some(py)) => {
        let spec = SpecifierSet::parse(spec_text)
        if !spec.contains(py) {
          exclusions.push(
            (filename, PythonIncompatible(spec_text, py.to_string())),
          )
          continue
        }
      }
      (Some(_), None) => ()
    }
    // Caller constraint.
    match constraints {
      None => ()
      Some(spec) =>
        if !spec.contains(version) {
          exclusions.push((filename, OutOfRange(spec.to_string())))
          continue
        }
    }
    candidates.push({ file, version, })
  }
  // Prerelease policy: default prefers finals, falls back to prereleases
  // when no final survives.
  let allow_pre = prereleases.unwrap_or(false)
  let has_final = candidates.exists(c => !version_is_prerelease(c.version))
  let want_prereleases = allow_pre || !has_final
  let kept : Array[IndexCandidate] = []
  for candidate in candidates {
    if version_is_prerelease(candidate.version) && !want_prereleases {
      exclusions.push(
        (candidate.file.filename, Prerelease(candidate.version.to_string())),
      )
    } else {
      kept.push(candidate)
    }
  }
  (kept, exclusions)
}
