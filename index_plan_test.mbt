///|
fn demo_index_1() -> String {
  let b = StringBuilder()
  b.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b.write_string(
    "{\"filename\": \"demo-1.0-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-1.0.tar.gz\", \"url\": \"u2\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-2.0-py3-none-any.whl\", \"url\": \"u3\", \"hashes\": {\"sha256\": \"abc\"}, \"requires-python\": \">=3.11\"},",
  )
  b.write_string(
    "{\"filename\": \"demo-0.9-py3-none-any.whl\", \"url\": \"u4\", \"hashes\": {\"sha256\": \"abc\"}, \"yanked\": \"bad build\"},",
  )
  b.write_string(
    "{\"filename\": \"demo-1.5rc1-py3-none-any.whl\", \"url\": \"u5\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"definitely-not-a-dist.txt\", \"url\": \"u6\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b.write_string("]}")
  b.to_string()
}

///|
fn demo_index_2() -> String {
  let b = StringBuilder()
  b.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b.write_string(
    "{\"filename\": \"demo-1.0-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-1.5rc1-py3-none-any.whl\", \"url\": \"u2\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-2.0-py3-none-any.whl\", \"url\": \"u3\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b.write_string("]}")
  b.to_string()
}

///|
test "select_candidates runs every gate with named exclusions" {
  let index = @moon_pyversion.SimpleIndex::parse(demo_index_1())
  let (kept, excluded) = @moon_pyversion.select_candidates(
    index,
    Some("3.9.1"),
    None,
  )
  // Default prerelease policy: a final release exists, so the rc1 is
  // excluded and named.
  let has_rc = kept.exists(c => c.version.to_string() == "1.5rc1")
  assert_eq(has_rc, false)
  let py_block = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.PythonIncompatible(_, _) => true
      _ => false
    }
  })
  assert_eq(py_block, true)
  let yank_block = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.Yanked(reason) => reason == "bad build"
      _ => false
    }
  })
  assert_eq(yank_block, true)
  let junk = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.UnparseableVersion(_) => true
      _ => false
    }
  })
  assert_eq(junk, true)
  let pre = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.Prerelease(_) => true
      _ => false
    }
  })
  assert_eq(pre, true)
  // The wheel and the sdist of 1.0 both survive.
  assert_eq(kept.length(), 2)
}

///|
test "select_candidates honors constraints and forced prereleases" {
  let index = @moon_pyversion.SimpleIndex::parse(demo_index_2())
  let spec = @moon_pyversion.SpecifierSet::parse("<2")
  let (kept, excluded) = @moon_pyversion.select_candidates(
    index,
    None,
    Some(spec),
  )
  // <2 keeps 1.0 (final) and excludes 2.0 (range) and 1.5rc1 (policy).
  assert_eq(kept.length(), 1)
  let out = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.OutOfRange(_) => true
      _ => false
    }
  })
  assert_eq(out, true)
  let (kept2, _) = @moon_pyversion.select_candidates(
    index,
    None,
    None,
    prereleases=Some(true),
  )
  assert_eq(kept2.length(), 3)
}

///|
fn sdist_mix_index() -> String {
  let b = StringBuilder()
  b.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b.write_string(
    "{\"filename\": \"demo-1.0.tar.gz\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-2.0-py3-none-any.whl\", \"url\": \"u2\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-3.0.zip\", \"url\": \"u3\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-3.0-py3-none-any.whl\", \"url\": \"u4\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b.write_string("]}")
  b.to_string()
}

///|
/// The default keeps every surviving file, wheels and sdists alike; with
/// `prefer_wheels` the sdists of versions a surviving wheel also carries
/// fall behind it and are named, while a version with no wheel keeps its
/// sdist - the source-only fallback.
test "prefer_wheels drops sdists a wheel covers and keeps the sdist fallback" {
  let index = @moon_pyversion.SimpleIndex::parse(sdist_mix_index())
  // Default: both files of every version survive.
  let (kept, _) = @moon_pyversion.select_candidates(index, None, None)
  assert_eq(kept.length(), 4)
  // Prefer wheels: 1.0 has no wheel, so its sdist survives; 3.0 has a
  // wheel, so its other sdist spelling (.zip) falls behind it.
  let (kept_wheels, excluded) = @moon_pyversion.select_candidates(
    index,
    None,
    None,
    prefer_wheels=true,
  )
  assert_eq(kept_wheels.length(), 3)
  assert_eq(kept_wheels[0].file.filename, "demo-1.0.tar.gz")
  assert_eq(kept_wheels[1].file.filename, "demo-2.0-py3-none-any.whl")
  assert_eq(kept_wheels[2].file.filename, "demo-3.0-py3-none-any.whl")
  let dropped = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.WheelAvailable(version) => version == "3.0"
      _ => false
    }
  })
  assert_eq(dropped, true)
  assert_eq(excluded.length(), 1)
}

///|
/// PEP 440 equality decides "same version", so a 1.0 sdist falls behind a
/// 1.0.0 wheel - and the exclusion names the version the sdist itself
/// spells. A sdist-only index loses nothing: the fallback is the answer.
test "prefer_wheels compares versions by PEP 440 equality" {
  let b = StringBuilder()
  b.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b.write_string(
    "{\"filename\": \"demo-1.0.0-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}},",
  )
  b.write_string(
    "{\"filename\": \"demo-1.0.tar.gz\", \"url\": \"u2\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b.write_string("]}")
  let index = @moon_pyversion.SimpleIndex::parse(b.to_string())
  let (kept, excluded) = @moon_pyversion.select_candidates(
    index,
    None,
    None,
    prefer_wheels=true,
  )
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].file.filename, "demo-1.0.0-py3-none-any.whl")
  let dropped = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.WheelAvailable(version) => version == "1.0"
      _ => false
    }
  })
  assert_eq(dropped, true)
  // Source-only project: no wheel exists, so the sdist is the candidate.
  let b2 = StringBuilder()
  b2.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b2.write_string(
    "{\"filename\": \"demo-1.0.tar.gz\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b2.write_string("]}")
  let index2 = @moon_pyversion.SimpleIndex::parse(b2.to_string())
  let (kept2, excluded2) = @moon_pyversion.select_candidates(
    index2,
    None,
    None,
    prefer_wheels=true,
  )
  assert_eq(kept2.length(), 1)
  assert_eq(kept2[0].file.filename, "demo-1.0.tar.gz")
  assert_eq(excluded2.length(), 0)
}

///|
/// The preference applies after every other gate, so a wheel that is
/// yanked does not beat a healthy sdist of the same version - the sdist
/// stays the candidate.
test "prefer_wheels only prefers wheels that survived the other gates" {
  let b = StringBuilder()
  b.write_string("{\"name\": \"demo\", \"version\": \"1.0\", \"files\": [")
  b.write_string(
    "{\"filename\": \"demo-1.0-py3-none-any.whl\", \"url\": \"u1\", \"hashes\": {\"sha256\": \"abc\"}, \"yanked\": \"bad build\"},",
  )
  b.write_string(
    "{\"filename\": \"demo-1.0.tar.gz\", \"url\": \"u2\", \"hashes\": {\"sha256\": \"abc\"}}",
  )
  b.write_string("]}")
  let index = @moon_pyversion.SimpleIndex::parse(b.to_string())
  let (kept, excluded) = @moon_pyversion.select_candidates(
    index,
    None,
    None,
    prefer_wheels=true,
  )
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].file.filename, "demo-1.0.tar.gz")
  let yank = excluded.exists(pair => {
    match pair.1 {
      @moon_pyversion.Yanked(_) => true
      _ => false
    }
  })
  assert_eq(yank, true)
  assert_eq(excluded.length(), 1)
}
