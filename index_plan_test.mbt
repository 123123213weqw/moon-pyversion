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
