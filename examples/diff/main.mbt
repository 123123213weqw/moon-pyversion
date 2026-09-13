///|
/// Deterministic corpus emitter for the independent PyPA `packaging` oracle
/// implemented in `tools/diff_packaging.py`.
///
/// Records are tab separated, one per line, and always start with the corpus
/// source (`curated`, `generated`, `mutated` or `pypi`):
///
/// - `<source>\tparse\t<raw>\t<ok|bad>\t<normalized form or ->`
/// - `<source>\tspec\t<raw>\t<ok|bad>`
/// - `<source>\tcmp\t<left>\t<right>\t<-1|0|1>`
/// - `<source>\tcontains\t<mode>\t<spec>\t<version>\t<true|false>`
/// - `<source>\tfilter\t<mode>\t<spec>\t<candidates as a|b>\t<accepted as c|d>`
/// - `<source>\torder\t<input as a|b>\t<ascending as b|a>`
///
/// `mode` is `auto` (the library default policy), `any` (prereleases forced
/// on) or `none` (prereleases forced off); the oracle maps them onto
/// `None`, `True` and `False`.
///
/// The corpus has four sources: a curated list, versions and specifiers
/// sampled from the PEP 440 grammar, mutated strings that are usually
/// illegal, and the real-world PyPI fixture in the `fixtures` package
/// (`fixtures/pypi_corpus.mbt`). Nothing here reads the clock, the
/// environment or the network, and the generator is a wrapping 64-bit LCG
/// with a constant seed, so the output is byte identical on wasm,
/// wasm-gc, js and native; `tools/target_parity.py` checks that claim.
struct Rng {
  mut state : UInt64
}

///|
fn Rng::new(seed : UInt64) -> Rng {
  { state: seed }
}

///|
fn Rng::next(self : Rng) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state >> 33
}

///|
fn Rng::below(self : Rng, bound : Int) -> Int {
  (self.next() % bound.to_uint64()).to_int()
}

///|
fn Rng::pick(self : Rng, options : Array[String]) -> String {
  options[self.below(options.length())]
}

///|
fn Rng::pick_char(self : Rng, options : Array[Char]) -> Char {
  options[self.below(options.length())]
}

///|
fn random_number(rng : Rng) -> String {
  let choices : Array[String] = [
    "0", "1", "2", "3", "5", "7", "10", "12", "007", "012", "000",
  ]
  rng.pick(choices)
}

///|
fn random_pre(rng : Rng) -> String {
  let labels : Array[String] = [
    "a", "b", "rc", "alpha", "beta", "c", "pre", "preview", "A", "B", "RC", "ALPHA",
  ]
  let seps : Array[String] = ["", ".", "-", "_"]
  let sb = StringBuilder()
  sb.write_string(rng.pick(seps))
  sb.write_string(rng.pick(labels))
  if rng.below(5) > 0 {
    sb.write_string(rng.pick(seps))
    sb.write_string(rng.below(6).to_string())
  }
  sb.to_string()
}

///|
fn random_post(rng : Rng) -> String {
  if rng.below(3) == 0 {
    "-" + rng.below(9).to_string()
  } else {
    let labels : Array[String] = ["post", "rev", "r", "POST", "Rev"]
    let seps : Array[String] = ["", ".", "-", "_"]
    let sb = StringBuilder()
    sb.write_string(rng.pick(seps))
    sb.write_string(rng.pick(labels))
    if rng.below(4) > 0 {
      sb.write_string(rng.pick(seps))
      sb.write_string(rng.below(9).to_string())
    }
    sb.to_string()
  }
}

///|
fn random_dev(rng : Rng) -> String {
  let labels : Array[String] = ["dev", "DEV", "Dev"]
  let seps : Array[String] = ["", ".", "-", "_"]
  let sb = StringBuilder()
  sb.write_string(rng.pick(seps))
  sb.write_string(rng.pick(labels))
  if rng.below(4) > 0 {
    sb.write_string(rng.pick(seps))
    sb.write_string(rng.below(9).to_string())
  }
  sb.to_string()
}

///|
fn random_local(rng : Rng) -> String {
  let segments : Array[String] = [
    "abc", "ABC", "1", "007", "a1", "Z9", "42x", "x",
  ]
  let seps : Array[String] = [".", "-", "_"]
  let sb = StringBuilder()
  sb.write_string("+")
  let count = 1 + rng.below(3)
  for i = 0; i < count; i = i + 1 {
    if i > 0 {
      sb.write_string(rng.pick(seps))
    }
    sb.write_string(rng.pick(segments))
  }
  sb.to_string()
}

///|
fn decorate(rng : Rng, body : String) -> String {
  match rng.below(6) {
    0 => "v" + body
    1 => "V" + body
    2 => " " + body
    3 => body + " "
    4 => " " + body + " "
    _ => body
  }
}

///|
/// Build a PEP 440 version. Ordered specifier operands must not carry a local
/// label, so callers that need one pass `with_local = false`.
fn random_version(rng : Rng, with_local : Bool) -> String {
  let sb = StringBuilder()
  if rng.below(8) == 0 {
    sb.write_string(rng.below(3).to_string())
    sb.write_string("!")
  }
  let segments = 1 + rng.below(4)
  for i = 0; i < segments; i = i + 1 {
    if i > 0 {
      sb.write_string(".")
    }
    sb.write_string(random_number(rng))
  }
  if rng.below(3) == 0 {
    sb.write_string(random_pre(rng))
  }
  if rng.below(3) == 0 {
    sb.write_string(random_post(rng))
  }
  if rng.below(4) == 0 {
    sb.write_string(random_dev(rng))
  }
  if with_local && rng.below(3) == 0 {
    sb.write_string(random_local(rng))
  }
  decorate(rng, sb.to_string())
}

///|
/// `~=` needs at least two release segments and rejects local labels.
fn random_compatible_operand(rng : Rng) -> String {
  let sb = StringBuilder()
  let segments = 2 + rng.below(3)
  for i = 0; i < segments; i = i + 1 {
    if i > 0 {
      sb.write_string(".")
    }
    sb.write_string(random_number(rng))
  }
  if rng.below(4) == 0 {
    sb.write_string(random_pre(rng))
  }
  decorate(rng, sb.to_string())
}

///|
fn random_wildcard_operand(rng : Rng) -> String {
  let sb = StringBuilder()
  let segments = 1 + rng.below(3)
  for i = 0; i < segments; i = i + 1 {
    if i > 0 {
      sb.write_string(".")
    }
    sb.write_string(random_number(rng))
  }
  sb.write_string(".*")
  decorate(rng, sb.to_string())
}

///|
fn random_clause(rng : Rng) -> String {
  let ops : Array[String] = ["==", "!=", "<", "<=", ">", ">=", "~=", "==="]
  let op = rng.pick(ops)
  if op == "==" || op == "!=" {
    match rng.below(4) {
      0 => op + random_wildcard_operand(rng)
      1 => op + random_version(rng, true)
      _ => op + random_version(rng, false)
    }
  } else if op == "===" {
    op + random_version(rng, true)
  } else if op == "~=" {
    op + random_compatible_operand(rng)
  } else {
    op + random_version(rng, false)
  }
}

///|
fn random_specifier(rng : Rng) -> String {
  let sb = StringBuilder()
  let clauses = 1 + rng.below(3)
  for i = 0; i < clauses; i = i + 1 {
    if i > 0 {
      sb.write_string(",")
      if rng.below(2) == 0 {
        sb.write_string(" ")
      }
    }
    sb.write_string(random_clause(rng))
  }
  sb.to_string()
}

///|
/// Replace, delete or insert one character. Most results are illegal, which is
/// what the `parse` and `spec` records need to exercise.
fn mutate(rng : Rng, source : String) -> String {
  let pool : Array[Char] = [
    '!', '+', '-', '.', '_', '*', '0', '9', 'a', 'z', ' ', 'v',
  ]
  let chars = source.to_array()
  if chars.length() == 0 {
    return String::from_array([rng.pick_char(pool)])
  }
  let at = rng.below(chars.length())
  let replacement = rng.pick_char(pool)
  match rng.below(3) {
    0 => {
      let out = chars.copy()
      out[at] = replacement
      String::from_array(out)
    }
    1 => {
      let out : Array[Char] = []
      for i = 0; i < chars.length(); i = i + 1 {
        if i != at {
          out.push(chars[i])
        }
      }
      String::from_array(out)
    }
    _ => {
      let out : Array[Char] = []
      for i = 0; i < chars.length(); i = i + 1 {
        if i == at {
          out.push(replacement)
        }
        out.push(chars[i])
      }
      String::from_array(out)
    }
  }
}

///|
fn curated_versions() -> Array[String] {
  [
    // Plain releases, epochs, prefixes and ASCII padding.
    "0", "0.0", "0.9", "1", "1.0", "1.0.0", "1.0.0.0", "1.0.0.0.0", "01.002.0003",
    "1.02.3", "v1.0", "V1.2.3", " 1.0", "1.0 ", " 1.0 ", "0!1.0", "1!1.0", "2!0.1",
    "1!1.0.0", "1!1.0a1.post2.dev3+local.1",
    // Pre releases, including every documented alias.
     "1.0a", "1.0a1", "1.0a1.dev1", "1.0a1.post1", "1.0a2.dev1", "1.0a2.post1.dev1",
    "1.0a1-5", "1.0b1", "1.0b1.dev1", "1.0rc", "1.0rc1", "1.0rc1.post1", "1.0alpha1",
    "1.0beta2", "1.0c3", "1.0pre4", "1.0preview5", "1.0ALPHA1", "1.0RC1", "1.0B1",
    // Post and dev releases, implicit and explicit.
     "1.0.dev0", "1.0.dev", "1.0.dev1", "1.0.dev2", "2.0.dev0", "1.0.dev1+abc", "1.0.post",
    "1.0.post0", "1.0.post0.dev1", "1.0.post1", "1.0.post1.dev1", "1.0.post2", "1.0.post456.dev34",
    "1.0-1", "1.0-2", "1.0rev3", "1.0r4", "1.0post1", "1.0REV2", "1.0a1.post2.dev3",
    // Local versions.
     "1.0+abc", "1.0+ABC", "1.0+1", "1.0+007", "1.0+abc.1", "1.0+abc-def_5", "1.0a1+local",
    "1.0.post1+2.3",
    // Neighbours used by the ordering checks.
     "1.1a1", "1.1", "1.1.post1", "1.2", "1.4.1", "2.0a1", "2.0", "2.0.post1", "1.0.1",
    "1.0.2", "1.0.10", "1.0.post1+abc", "1.0a1.post1.dev1+abc",
  ]
}

///|
fn curated_specifiers() -> Array[String] {
  [
    "", " ", "==1.0", "==1.0.*", "!=1.0", "!=1.0.*", "!=1.0a1", "<1.0", "<=1.0",
    ">1.0", ">=1.0", "~=1.0", "~=1.0.0", "~=1.4.2", "~=2.2", "~=1!1.0", "~=01.02",
    "===1.0", "===1.0+ABC", "===1.0.0", ">=1.0,!=1.1.*,<2.0", "<=1.0,>=0.9", ">=1.0,<2.0",
    ">1.0a1", "<1.0a1", ">=1.0a1", ">1.0.dev1", "<1.0.dev1", "<1.0.post1", ">1.0.post1",
    ">=1.0.post1", "<=1.0.post1", "==0!1.0", "==1!1.0", "!=1!1.0", "==1.0+abc", "!=1.0+abc",
    "==1.0.post1.dev1", "==1.0-1", "==1.0a1.dev1", ">=1.0.0.0", "==2.0.*", "!=2.0.*",
    "==1.0.*,!=1.0.5", ">=1.0rc1,<1.0", "!=1.0.0,!=1.0.1", "==1.0.*,>=1.0",
  ]
}

///|
fn junk_versions() -> Array[String] {
  [
    "", " ", "  ", "v", "V", "!", "!1.0", "1!2!", "1.0!", "1..0", ".1.0", "1.0.",
    "1.0-", "1.0+", "1.0++abc", "1.0+abc+def", "1.0+abc!def", "1.0+ab cd", "1.0a1a2",
    "1.0.post1.post2", "1.0.dev1.dev2", "1.0a1.dev1.post1", "1.0post1.dev1", "1.0dev1a1",
    "v 1.0", "1 .0", "1.0 .1", "-1.0", "1.-0", "1.0.-1", "1.0a1.0", "1.0+1.0a", "1.0a1post",
    "1.0rc1rc2", "1.0b1b2", "1!1!1.0", "0!0!1.0", "vv1.0", "1.0vv", "1.0_", "1.0a1.",
    "1.0+abc.", "1.0+_abc", "1.0+-abc", "1.0+.abc", "1.0+abc..def", "1.0+abc/def",
    "1.0?", "1.0a1.0b1", "1.0dev", "01.02.03.04.05.06.07.08.09.10.11.12",
  ]
}

///|
fn junk_specifiers() -> Array[String] {
  [
    ",", ",,", "=", "=>", "<>", "~", "<", ">", "==", ">=", "!=", "~=", "===", "~=1",
    "==1.0.*.*", ">=1.0.*", "<1.0.*", "~=1.0.*", ">1.0+abc", "<1.0+abc", ">=1.0+abc",
    "<=1.0+abc", "~=1.0+abc", "==1.0 <2.0", "1.0", "v1.0", "==1.0;", "!=1.0.x", "==1.0.*x",
    ">=1.0,,", "==1.0.*,", "==1!1.0.*", "==1.0.*+abc", "~=", "==a.b.c", "==1.0b",
    "!=v1.0", ">=1.0 <=2.0", "==1.0+abc+def", "==1.0.0.0.0.0.0.0.*", "!1.0", "==*",
    "==.*", "==1.*.0",
  ]
}

///|
fn emit_parse(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string(source)
  sb.write_string("\tparse\t")
  sb.write_string(raw)
  sb.write_string("\t")
  let parsed = parse_opt(raw)
  match parsed {
    Some(v) => {
      sb.write_string("ok\t")
      sb.write_string(@pyversion.Version::to_string(v))
    }
    None => sb.write_string("bad\t-")
  }
  sb.write_string("\n")
}

///|
fn emit_spec(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string(source)
  sb.write_string("\tspec\t")
  sb.write_string(raw)
  sb.write_string("\t")
  let ok = try {
    ignore(@pyversion.SpecifierSet::parse(raw))
    true
  } catch {
    _ => false
  }
  sb.write_string(if ok { "ok" } else { "bad" })
  sb.write_string("\n")
}

///|
fn parse_opt(raw : String) -> @pyversion.Version? {
  Some(@pyversion.Version::parse(raw)) catch {
    _ => None
  }
}

///|
fn spec_opt(raw : String) -> @pyversion.SpecifierSet? {
  Some(@pyversion.SpecifierSet::parse(raw)) catch {
    _ => None
  }
}

///|
/// Skip inputs this library rejects: they are already covered by `parse`
/// records, and the oracle must not be asked to compare a bogus side twice.
fn emit_cmp(
  source : String,
  sb : StringBuilder,
  left : String,
  right : String,
) -> Unit {
  let l = parse_opt(left)
  let r = parse_opt(right)
  match (l, r) {
    (Some(a), Some(b)) => {
      let c = @pyversion.Version::compare(a, b)
      let sign = if c < 0 { "-1" } else if c > 0 { "1" } else { "0" }
      sb.write_string("\{source}\tcmp\t\{left}\t\{right}\t\{sign}\n")
    }
    _ => ()
  }
}

///|
fn mode_name(mode : Int) -> String {
  if mode == 0 {
    "auto"
  } else if mode == 1 {
    "any"
  } else {
    "none"
  }
}

///|
fn mode_setting(mode : Int) -> Bool? {
  if mode == 0 {
    None
  } else if mode == 1 {
    Some(true)
  } else {
    Some(false)
  }
}

///|
fn emit_contains(
  source : String,
  sb : StringBuilder,
  spec_raw : String,
  version_raw : String,
) -> Unit {
  let spec = spec_opt(spec_raw)
  let version = parse_opt(version_raw)
  match (spec, version) {
    (Some(s), Some(v)) =>
      for mode = 0; mode < 3; mode = mode + 1 {
        let hit = s.contains(v, prereleases=mode_setting(mode))
        sb.write_string(
          "\{source}\tcontains\t\{mode_name(mode)}\t\{spec_raw}\t\{version_raw}\t\{hit}\n",
        )
      }
    _ => ()
  }
}

///|
fn emit_filter(
  source : String,
  sb : StringBuilder,
  spec_raw : String,
  candidates : Array[String],
) -> Unit {
  let spec = spec_opt(spec_raw)
  match spec {
    Some(s) => {
      let versions : Array[@pyversion.Version] = []
      let used : Array[String] = []
      for raw in candidates {
        match parse_opt(raw) {
          Some(v) => {
            versions.push(v)
            used.push(raw)
          }
          None => ()
        }
      }
      if used.length() > 0 {
        for mode = 0; mode < 3; mode = mode + 1 {
          let accepted = @pyversion.SpecifierSet::filter(
            versions,
            s,
            prereleases=mode_setting(mode),
          )
          let out : Array[String] = []
          for v in accepted {
            out.push(@pyversion.Version::to_string(v))
          }
          sb.write_string(
            "\{source}\tfilter\t\{mode_name(mode)}\t\{spec_raw}\t\{used.join("|")}\t\{out.join("|")}\n",
          )
        }
      }
    }
    None => ()
  }
}

///|
fn emit_order(
  source : String,
  sb : StringBuilder,
  inputs : Array[String],
) -> Unit {
  let versions : Array[@pyversion.Version] = []
  let used : Array[String] = []
  for raw in inputs {
    match parse_opt(raw) {
      Some(v) => {
        versions.push(v)
        used.push(raw)
      }
      None => ()
    }
  }
  if used.length() > 1 {
    let sorted = versions.copy()
    sorted.sort()
    let rendered : Array[String] = []
    for v in sorted {
      rendered.push(@pyversion.Version::to_string(v))
    }
    sb.write_string(
      "\{source}\torder\t\{used.join("|")}\t\{rendered.join("|")}\n",
    )
  }
}

///|
fn sample_every(items : Array[String], limit : Int) -> Array[String] {
  let out : Array[String] = []
  let total = items.length()
  if total <= limit {
    for item in items {
      out.push(item)
    }
  } else {
    let stride = total / limit + 1
    let mut i = 0
    while i < total && out.length() < limit {
      out.push(items[i])
      i = i + stride
    }
  }
  out
}

///|
fn sample_versions(
  rng : Rng,
  items : Array[String],
  count : Int,
) -> Array[String] {
  let out : Array[String] = []
  if items.length() == 0 {
    return out
  }
  for i = 0; i < count; i = i + 1 {
    out.push(items[rng.below(items.length())])
  }
  out
}

///|
fn parse_wheel_opt(raw : String) -> @pyversion.WheelFilename? {
  Some(@pyversion.parse_wheel_filename(raw)) catch {
    _ => None
  }
}

///|
fn parse_sdist_opt(raw : String) -> @pyversion.SdistFilename? {
  Some(@pyversion.parse_sdist_filename(raw)) catch {
    _ => None
  }
}

///|
fn curated_names() -> Array[String] {
  [
    "Flask", "flask", "importlib_metadata", "importlib-metadata", "zope.interface",
    "Foo.Bar-Baz", "Foo__Bar", "a.-_b", "requests", "Django", "oslo.concurrency",
    "UPPER", "Mixed_Case.Name", "x", "-foo-", "--", "-", "", "foo!", "a..b", "a--b",
    "a-_-.b", "123", "_", ".", "importlib.metadata",
  ]
}

///|
fn curated_version_keys() -> Array[String] {
  [
    "1.0.0", "1.0", "0", "0.0", "0.0.0", "1.4.0.0.0", "1.0.0.post0", "1.0.0.dev0",
    "1.0.0a1", "1!1.0.0", "1.0.0+abc", "1.0.0.post1.dev2", "v1.2.3", "01.02.03",
    "1.0.0+ABC", "2!0.0.0", "1.0rc1", "1.0.0-1", "1.0.0.post", "1.0.0.dev", "1.0.0a",
    "1.0.0.0.0.0", "0.0+abc", "1!0.0", "foo bar baz", "", "1.0.", "1..0", "1.0 ",
    " 1.0", "1.0.0.post0.dev0",
  ]
}

///|
fn curated_filenames() -> Array[String] {
  [
    // valid wheels: build tags, local versions, escaped names, compressed tags
    "flask-3.0.3-py3-none-any.whl", "flask-3.0.3-1-py3-none-any.whl", "foo_bar-1.0-py3-none-any.whl",
    "foo-1.0-py2.py3-none-any.whl", "foo-1.0-cp39.cp310-abi3-manylinux1_x86_64.whl",
    "numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl", "torch-2.4.0+cu121-cp311-cp311-linux_x86_64.whl",
    "Zope.Interface-5.4.0-cp311-cp311-linux_x86_64.whl", "foo-1.0-1abc-py3-none-any.whl",
    "foo-01.02-py3-none-any.whl",
    // invalid wheels
     "foo-1.0-py3-none-any.zip", "foo-1.0-py3-none.whl", "foo-.whl", "a-b-c.whl",
    "foo-1.0-py3-none-any-extra-part.whl", "foo__bar-1.0-py3-none-any.whl", "foo-bar-1.0-py3-none-any.whl",
    "-1.0-py3-none-any.whl", "foo$bar-1.0-py3-none-any.whl", "foo-1.0-abc-py3-none-any.whl",
    "foo-1.0-2py-none-any.whl", "foo-1.0-py3--any.whl", "foo-1.0-py3.none-any.whl",
    "foo-1.0-1.5-py3-none-any.whl", "foo-1.0-py3-none-any.whl.whl",
    // valid sdists
     "flask-3.0.3.tar.gz", "flask-3.0.3.zip", "foo-bar-1.0.tar.gz", "Zope.Interface-5.4.0.tar.gz",
    "torch-2.4.0+cu121.tar.gz", "a-1.0.tar.gz",
    // invalid sdists
     "foo-1.0.tar.bz2", "foo.tar.gz", "-1.0.tar.gz", "foo-abc.tar.gz", "foo-1.0.whl",
    ".tar.gz", "foo-.tar.gz",
    // neither extension
     "README.md", "foo", "tar.gz", ".whl", "3.0.3", "foo-1.0", "any",
  ]
}

///|
/// `canon` records carry a fixed field count so the harness can check arity
/// without knowing the sub kind: names use `-` for the unused extra field.
fn emit_canon_name(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string(
    "\{source}\tcanon\tname\t\{raw}\t\{@pyversion.canonicalize_name(raw)}\t-\n",
  )
}

///|
fn emit_canon_version(
  source : String,
  sb : StringBuilder,
  raw : String,
) -> Unit {
  sb.write_string(
    "\{source}\tcanon\tversion\t\{raw}\t\{@pyversion.canonicalize_version(raw)}\t\{@pyversion.canonicalize_version(raw, strip_trailing_zero=false)}\n",
  )
}

///|
/// Filenames are dispatched by extension, the way a caller would: `.whl` to the
/// wheel parser, `.tar.gz` and `.zip` to the sdist parser, and anything else to
/// both, where the record reports agreement only if neither parser accepts it.
fn emit_file(source : String, sb : StringBuilder, raw : String) -> Unit {
  if raw.has_suffix(".whl") {
    sb.write_string("\{source}\tfile\twheel\t\{raw}\t")
    match parse_wheel_opt(raw) {
      Some(w) => {
        let build = match w.build {
          Some((number, rest)) => "\{number}:\{rest}"
          None => "-"
        }
        sb.write_string(
          "ok\t\{w.name}\t\{@pyversion.Version::to_string(w.version)}\t\{build}\t\{w.tags.join("|")}\n",
        )
      }
      None => sb.write_string("bad\t-\t-\t-\t-\n")
    }
  } else if raw.has_suffix(".tar.gz") || raw.has_suffix(".zip") {
    sb.write_string("\{source}\tfile\tsdist\t\{raw}\t")
    match parse_sdist_opt(raw) {
      Some(s) =>
        sb.write_string(
          "ok\t\{s.name}\t\{@pyversion.Version::to_string(s.version)}\t-\t-\n",
        )
      None => sb.write_string("bad\t-\t-\t-\t-\n")
    }
  } else {
    let accepted = parse_wheel_opt(raw) is Some(_) ||
      parse_sdist_opt(raw) is Some(_)
    sb.write_string(
      "\{source}\tfile\tother\t\{raw}\t\{if accepted { "ok" } else { "bad" }}\t-\t-\t-\t-\n",
    )
  }
}

///|
fn filename_pool() -> Array[Char] {
  ['!', '+', '-', '.', '_', '0', '9', 'a', 'z', 'w', 'h', 'l', ' ']
}

///|
fn mutate_filename(rng : Rng, source : String) -> String {
  let pool = filename_pool()
  let chars = source.to_array()
  if chars.length() == 0 {
    return String::from_array([rng.pick_char(pool)])
  }
  let at = rng.below(chars.length())
  let replacement = rng.pick_char(pool)
  match rng.below(3) {
    0 => {
      let out = chars.copy()
      out[at] = replacement
      String::from_array(out)
    }
    1 => {
      let out : Array[Char] = []
      for i = 0; i < chars.length(); i = i + 1 {
        if i != at {
          out.push(chars[i])
        }
      }
      String::from_array(out)
    }
    _ => {
      let out : Array[Char] = []
      for i = 0; i < chars.length(); i = i + 1 {
        if i == at {
          out.push(replacement)
        }
        out.push(chars[i])
      }
      String::from_array(out)
    }
  }
}

///|
fn main {
  let sb = StringBuilder()
  let rng = Rng::new(0x5EED202644000001UL)
  let curated = curated_versions()
  let curated_specs = curated_specifiers()
  // 1. The curated corpus: every pair, every specifier against every version.
  for raw in curated {
    emit_parse("curated", sb, raw)
  }
  for raw in curated_specs {
    emit_spec("curated", sb, raw)
  }
  for left in curated {
    for right in curated {
      emit_cmp("curated", sb, left, right)
    }
  }
  for spec in curated_specs {
    for version in curated {
      emit_contains("curated", sb, spec, version)
    }
  }
  for spec in curated_specs {
    emit_filter("curated", sb, spec, curated)
  }
  emit_order("curated", sb, curated)
  // 2. Generated versions and specifiers from the PEP 440 grammar.
  let generated : Array[String] = []
  for i = 0; i < 4000; i = i + 1 {
    generated.push(random_version(rng, true))
  }
  for raw in generated {
    emit_parse("generated", sb, raw)
  }
  for i = 0; i < 3000; i = i + 1 {
    emit_cmp(
      "generated",
      sb,
      generated[rng.below(generated.length())],
      generated[rng.below(generated.length())],
    )
  }
  let generated_specs : Array[String] = []
  for i = 0; i < 700; i = i + 1 {
    generated_specs.push(random_specifier(rng))
  }
  for raw in generated_specs {
    emit_spec("generated", sb, raw)
  }
  for raw in generated_specs {
    for version in sample_versions(rng, generated, 6) {
      emit_contains("generated", sb, raw, version)
    }
  }
  for raw in sample_every(generated_specs, 120) {
    emit_filter("generated", sb, raw, sample_versions(rng, generated, 40))
  }
  emit_order("generated", sb, generated)
  // 3. Mutated versions and specifiers, mostly illegal on purpose.
  let mutated_versions : Array[String] = []
  for i = 0; i < 3000; i = i + 1 {
    let base = if i % 2 == 0 {
      curated[rng.below(curated.length())]
    } else {
      generated[rng.below(generated.length())]
    }
    mutated_versions.push(mutate(rng, base))
  }
  for raw in junk_versions() {
    mutated_versions.push(raw)
  }
  for raw in mutated_versions {
    emit_parse("mutated", sb, raw)
  }
  let mutated_specs : Array[String] = []
  for i = 0; i < 1200; i = i + 1 {
    let base = if i % 2 == 0 {
      curated_specs[rng.below(curated_specs.length())]
    } else {
      generated_specs[rng.below(generated_specs.length())]
    }
    mutated_specs.push(mutate(rng, base))
  }
  for raw in junk_specifiers() {
    mutated_specs.push(raw)
  }
  for raw in mutated_specs {
    emit_spec("mutated", sb, raw)
  }
  // 4. The real-world PyPI fixture.
  for raw in @fixtures.pypi_versions {
    emit_parse("pypi", sb, raw)
  }
  for raw in @fixtures.pypi_specifiers {
    emit_spec("pypi", sb, raw)
  }
  for i = 0; i < 4000; i = i + 1 {
    emit_cmp(
      "pypi",
      sb,
      @fixtures.pypi_versions[rng.below(@fixtures.pypi_versions.length())],
      @fixtures.pypi_versions[rng.below(@fixtures.pypi_versions.length())],
    )
  }
  let real_versions = sample_every(@fixtures.pypi_versions, 600)
  for spec in @fixtures.pypi_specifiers {
    for version in sample_versions(rng, @fixtures.pypi_versions, 25) {
      emit_contains("pypi", sb, spec, version)
    }
  }
  for spec in sample_every(@fixtures.pypi_specifiers, 200) {
    emit_filter("pypi", sb, spec, real_versions)
  }
  emit_order("pypi", sb, @fixtures.pypi_versions)
  // 5. Packaging metadata helpers: name and version canonicalization, and
  //    distribution filenames.
  let curated_name_inputs = curated_names()
  let curated_key_inputs = curated_version_keys()
  let curated_file_inputs = curated_filenames()
  for raw in curated_name_inputs {
    emit_canon_name("curated", sb, raw)
  }
  for raw in curated_key_inputs {
    emit_canon_version("curated", sb, raw)
  }
  for raw in curated_file_inputs {
    emit_file("curated", sb, raw)
  }
  for raw in mutated_versions {
    emit_canon_name("mutated", sb, raw)
    emit_canon_version("mutated", sb, raw)
  }
  for raw in @fixtures.pypi_filenames {
    emit_file("pypi", sb, raw)
  }
  let mutated_files : Array[String] = []
  for i = 0; i < 4000; i = i + 1 {
    let base = if i % 3 == 0 {
      curated_file_inputs[rng.below(curated_file_inputs.length())]
    } else {
      @fixtures.pypi_filenames[rng.below(@fixtures.pypi_filenames.length())]
    }
    mutated_files.push(mutate_filename(rng, base))
  }
  for raw in mutated_files {
    emit_file("mutated", sb, raw)
  }
  println(sb.to_string())
}
