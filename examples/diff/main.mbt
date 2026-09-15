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
/// - `<source>\treq\t<raw>\t<ok|bad>\t<name>\t<extras as a|b or ->\t<normalized specifier>\t<url or ->\t<marker text or ->`
/// - `<source>\tmarker\t<raw>\t<ok|bad>\t<canonical rendering or ->`
/// - `<source>\tmarker_env\t<name>\t<key=value;...>` (input, not a check)
/// - `<source>\tmarker_eval\t<env name>\t<raw>\t<ok|bad|err>\t<true|false or error kind>`
/// - `<source>\ttoml\t<case name>\t<document>\t<ok|bad|lenient|lenient-drift>\t<re-serialization or ->`
/// - `<source>\tlicense\t<raw>\t<ok|bad>\t<canonical expression or ->`
/// - `<source>\tmeta\t<case name>\t<document>\t<ok|bad>\t<error code or ->\t<canonical re-rendering or ->`
/// - `<source>\tmeta_values\t<case name>\t<field>\t<index>\t<value>`
/// - `<source>\tmeta_divergence\t<case name>\t<accept|reject>` (input, not a check)
/// - `<source>\tindex\t<case name>\t<document>\t<ok|bad>\t<projection or error code>`
/// - `<source>\tindex_divergence\t<case name>\t<accept|reject>` (input, not a check)
/// - `<source>\tresolve\t<requirement>\t<files as f@rp;...>\t<tags as a|b>\t<python or ->\t<mode>\t<kept as a|b>\t<rejected as f=reason|...>`
/// - `<source>\tindex_dir\t<directory>\t<entries as a|b>\t<ok|bad>\t<projection or error code>`
/// - `<source>\tpylock\t<case name>\t<document>\t<ok|bad>\t<projection or error code>`
/// - `<source>\tpylock_divergence\t<case name>\t<accept|reject>` (input, not a check)
/// - `<source>\tresolve\t<requirement>\t<tags as a|b>\t<python or ->\t<mode>\t<kept as a|b>\t<rejected as f=reason|...>`
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
  { state: seed, }
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
    // tag components are case-insensitive: `packaging`'s `Tag` lowercases all
    // three, so a wheel may spell them either way and both readings agree
     "Zope.Interface-5.4.0-CP311-CP311-Linux_x86_64.whl", "numpy-1.26.4-cp312-cp312-ManyLinux_2_17_X86_64.manylinux2014_x86_64.whl",
    "Flask-3.0.3-Py3-None-Any.whl", "foo-1.0-PY2.PY3-NONE-ANY.whl", "foo-1.0-CP39.Cp310-ABI3-Manylinux1_X86_64.whl",
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
/// Marker expressions that exercise the closed vocabulary, the word operators,
/// the quote decoding and the parenthesis rules.
fn curated_markers() -> Array[String] {
  [
    // the ordinary comparisons
    "python_version == '3.8'", "python_version == \"3.8\"", "python_version<'3.10'",
    "python_version < '3.10'", "python_version <= '3.8'", "python_version > '3.8'",
    "python_version >= '3.8'", "python_version != '3.8'", "python_version ~= '3.8'",
    "python_version === '3.8'", "python_full_version >= '3.8.1'", "implementation_name == 'cpython'",
    "implementation_version == '3.8.0'", "platform_release == '5.4.0'", "platform_system == 'Linux'",
    "platform_machine == 'x86_64'", "os_name == 'posix'", "sys_platform == 'linux'",
    "extra == 'test'", "extra == 'Foo_Bar'", "extra == 'Foo.Bar'",
    // dotted aliases and the python_implementation alias
     "os.name == 'posix'", "sys.platform == 'linux'", "platform.version == '1'",
    "platform.machine == 'x86_64'", "platform.python_implementation == 'CPython'",
    "python_implementation == 'CPython'",
    // membership, in both spellings
     "python_version in '3.8 3.9'", "python_version not in '3.8 3.9'", "extra in 'a b'",
    "extra not in 'a b'",
    // the value on the left
     "'3.8' == python_version", "'CPython' != platform_python_implementation",
    // variable against variable
     "python_version == python_full_version", "os_name == sys_platform", "extra == python_version",
    // combining
     "python_version == '3.8' and os_name == 'posix'", "os_name == 'posix' or python_version == '3.8'",
    "os_name == 'posix' and python_version == '3.8' and extra == 'x'", "os_name == 'posix' or python_version == '3.8' and extra == 'x'",
    "(os_name == 'posix' or python_version == '3.8') and extra == 'x'", "((os_name == 'posix'))",
    "(os_name == 'posix')", "(((os_name == 'posix')))", "python_version == '3.8' and (os_name == 'posix')",
    "(python_version == '3.8' or os_name == 'posix') and (extra == 'a' or extra == 'b')",
    // whitespace is optional around and/or but not inside `not in`
     "os_name=='posix'and extra=='x'", "  os_name  ==  'posix'  ", "python_version == '3.8'\tand\tos_name == 'posix'",
    // set valued keys
     "extra == 'x' or extras == 'y'", "'x' in extras", "extras == 'a'", "dependency_groups == 'test'",
    // PEP 685 / PEP 735: the names either side of a comparison are normalized,
    // so the odd spellings in the `oddnames` environment must still match
     "extra == 'docs-build'", "extra == 'Docs_Build'", "'Docs-Build' == extra", "extra in 'docs build'",
    "extra not in 'docs build'", "extra == 'docs'", "'cli' in extras", "'docs_build' in extras",
    "'docs-build' in extras", "'docsbuild' in dependency_groups", "'test-ci' in dependency_groups",
    "'test_ci' not in dependency_groups", "'test' in dependency_groups",
    // string escapes and quotes
     "extra == 'a\\tb'", "extra == 'a\\nb'", "extra == 'a\\\\b'", "extra == \"it's\"",
    "extra == 'say \"hi\"'", "extra == '\\\\x41'",
    // rejected
     "", "   ", "python_version", "python_version =", "python_version = '3.8'", "python_version == 3.8",
    "python_version == '3.8", "python_version == \"3.8'", "ex0tra == 'x'", "etra == 'x'",
    "extrax == 'x'", "version == 'x'", "python_version == '3.8' and", "python_version == '3.8' or",
    "and python_version == '3.8'", "or python_version == '3.8'", "()", "(python_version == '3.8'",
    "(python_version == '3.8'))", "python_version not '3.8'", "python_version notin 'x'",
    "not python_version == '3.8'", "python_version == '3.8' extra", "python_version == '3.8'; os_name == 'posix'",
    "python_version ==", "python_version == ==", "extra ==", "extra ==== 'x'", "in 'x'",
    "'x' in", "python_version == '3.8' and ()", "python_version < '3.8' > '2'",
  ]
}

///|
/// The marker environments the evaluation records run against. Each is a
/// complete environment, and each is emitted as a `marker_env` record before it
/// is used, so the oracle does not have to keep a second copy of these values.
fn marker_environments() -> Array[
  (String, String, @pyversion.MarkerEnvironment),
] {
  let values : Array[(String, Array[(String, String)])] = [
    (
      "posix38",
      [
        ("python_version", "3.8"),
        ("python_full_version", "3.8.18"),
        ("os_name", "posix"),
        ("sys_platform", "linux"),
        ("platform_release", "5.4.0"),
        ("platform_system", "Linux"),
        ("platform_version", "#1 SMP"),
        ("platform_machine", "x86_64"),
        ("platform_python_implementation", "CPython"),
        ("implementation_name", "cpython"),
        ("implementation_version", "3.8.18"),
        ("extra", ""),
      ],
    ),
    (
      "win311",
      [
        ("python_version", "3.11"),
        ("python_full_version", "3.11.9"),
        ("os_name", "nt"),
        ("sys_platform", "win32"),
        ("platform_release", "10"),
        ("platform_system", "Windows"),
        ("platform_version", "10.0.22631"),
        ("platform_machine", "AMD64"),
        ("platform_python_implementation", "CPython"),
        ("implementation_name", "cpython"),
        ("implementation_version", "3.11.9"),
        ("extra", "test"),
      ],
    ),
    (
      "pypy310",
      [
        ("python_version", "3.10"),
        ("python_full_version", "3.10.14"),
        ("os_name", "posix"),
        ("sys_platform", "linux"),
        ("platform_release", "6.1.0"),
        ("platform_system", "Linux"),
        ("platform_version", "#1 SMP"),
        ("platform_machine", "aarch64"),
        ("platform_python_implementation", "PyPy"),
        ("implementation_name", "pypy"),
        ("implementation_version", "7.3.15"),
        ("extra", "all"),
      ],
    ),
    (
      "macos312",
      [
        ("python_version", "3.12"),
        ("python_full_version", "3.12.3"),
        ("os_name", "posix"),
        ("sys_platform", "darwin"),
        ("platform_release", "23.5.0"),
        ("platform_system", "Darwin"),
        ("platform_version", "Darwin Kernel Version 23.5.0"),
        ("platform_machine", "arm64"),
        ("platform_python_implementation", "CPython"),
        ("implementation_name", "cpython"),
        ("implementation_version", "3.12.3"),
        ("extra", "Docs"),
      ],
    ),
    (
      // The same keys, but spelled the way a `pyproject.toml` may spell them:
      // PEP 685 / PEP 735 compare names, so an extra called `Docs_Build` and a
      // group member called `CLI` still have to match the normalized markers.
      "oddnames",
      [
        ("python_version", "3.13"),
        ("python_full_version", "3.13.2"),
        ("os_name", "posix"),
        ("sys_platform", "linux"),
        ("platform_release", "6.8.0-45-generic"),
        ("platform_system", "Linux"),
        ("platform_version", "#45-Ubuntu SMP PREEMPT_DYNAMIC"),
        ("platform_machine", "x86_64"),
        ("platform_python_implementation", "CPython"),
        ("implementation_name", "cpython"),
        ("implementation_version", "3.13.2"),
        ("extra", "Docs_Build"),
      ],
    ),
  ]
  let names : Array[String] = [
    "posix38", "win311", "pypy310", "macos312", "oddnames",
  ]
  let sets : Array[Array[(String, Array[String])]] = [
    [],
    [],
    [],
    [("extras", ["cli", "docs"])],
    [
      ("extras", ["CLI", "docs_build"]),
      ("dependency_groups", ["DocsBuild", "test_ci"]),
    ],
  ]
  let out : Array[(String, String, @pyversion.MarkerEnvironment)] = []
  for i = 0; i < values.length(); i = i + 1 {
    let environment = @pyversion.MarkerEnvironment::new()
    let assignments = StringBuilder()
    for j = 0; j < values[i].1.length(); j = j + 1 {
      let key = values[i].1[j].0
      environment.set(key, values[i].1[j].1)
      if j > 0 {
        assignments.write_string(";")
      }
      assignments.write_string(key + "=" + values[i].1[j].1)
    }
    for group in sets[i] {
      let members = StringBuilder()
      for k = 0; k < group.1.length(); k = k + 1 {
        if k > 0 {
          members.write_string(",")
        }
        members.write_string(group.1[k])
      }
      environment.set_names(group.0, group.1)
      assignments.write_string(";set:" + group.0 + "=" + members.to_string())
    }
    out.push((names[i], assignments.to_string(), environment))
  }
  out
}

///|
/// Emit an environment definition so the oracle evaluates against exactly the
/// values the library was given.
fn emit_marker_env(
  source : String,
  sb : StringBuilder,
  name : String,
  assignments : String,
) -> Unit {
  sb.write_string("\{source}\tmarker_env\t\{name}\t\{assignments}\n")
}

///|
fn marker_opt(raw : String) -> @pyversion.Marker? {
  Some(@pyversion.Marker::parse(raw)) catch {
    _ => None
  }
}

///|
fn marker_render_opt(raw : String) -> String? {
  match marker_opt(raw) {
    Some(marker) => Some(marker.to_string()) catch { _ => None }
    None => None
  }
}

///|
/// Escape the characters that would break the tab-separated, line-based record
/// format. Only the marker records need this: a marker value is a quoted string
/// whose decoded form may hold a tab or a newline, and the canonical rendering
/// writes that decoded form back out.
fn escape_record(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\t' {
      out.write_string("\\t")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c.to_int() < 32 || c.to_int() == 127 {
      // Every other control character, as `\u{..}`.
      //
      // The three above have short spellings, but a raw vertical tab or form feed
      // is just as fatal to the transport: it is a record separator to anything
      // that reads the corpus by lines, and a *line break* to this lexer, so a
      // document carrying one could not even be written as a literal. The
      // `Keywords` whitespace rules need both characters, which is how the hole
      // was found; escaping the whole class is the fix rather than the two
      // characters that happened to expose it.
      out.write_string("\\u{")
      out.write_string(hex_lower(c.to_int()))
      out.write_string("}")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// A non-negative integer in lowercase hexadecimal, without padding.
fn hex_lower(value : Int) -> String {
  if value == 0 {
    return "0"
  }
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  let mut n = value
  while n > 0 {
    out.write_char(digits.to_array()[n % 16])
    n = n / 16
  }
  // The digits come out least significant first.
  let text = out.to_string()
  let reversed : Array[Char] = []
  for i = text.length() - 1; i >= 0; i = i - 1 {
    reversed.push(text.to_array()[i])
  }
  String::from_array(reversed)
}

///|
/// Emit one marker record: acceptance and canonical rendering.
fn emit_marker(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string("\{source}\tmarker\t\{escape_record(raw)}\t")
  match marker_render_opt(raw) {
    Some(rendered) => sb.write_string("ok\t\{escape_record(rendered)}\n")
    None => sb.write_string("bad\t-\n")
  }
}

///|
fn marker_error_kind(error : @pyversion.MarkerError) -> String {
  match error {
    @pyversion.UndefinedEnvironmentName(_) => "UndefinedEnvironmentName"
    @pyversion.UndefinedComparison(_) => "UndefinedComparison"
    @pyversion.SetValuedOnLeft(_, _) => "SetValuedOnLeft"
  }
}

///|
/// Emit one marker evaluation record against a named environment.
fn emit_marker_eval(
  source : String,
  sb : StringBuilder,
  env_name : String,
  environment : @pyversion.MarkerEnvironment,
  raw : String,
) -> Unit {
  sb.write_string(
    "\{source}\tmarker_eval\t\{env_name}\t\{escape_record(raw)}\t",
  )
  match marker_opt(raw) {
    None => sb.write_string("bad\t-\n")
    Some(marker) =>
      try {
        let result = marker.evaluate(environment)
        sb.write_string("ok\t\{result}\n")
      } catch {
        error => sb.write_string("err\t\{marker_error_kind(error)}\n")
      }
  }
}

///|
/// Characters used to perturb marker expressions.
fn marker_pool() -> Array[Char] {
  [
    '(', ')', '\'', '"', '=', '<', '>', '!', '~', ' ', 'a', 'n', 'd', 'o', 'r', 'i',
    's', 'x', '0', '9', '_',
  ]
}

///|
fn mutate_marker(rng : Rng, source : String) -> String {
  let pool = marker_pool()
  let chars = source.to_array()
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
        out.push(chars[i])
        if i == at {
          out.push(replacement)
        }
      }
      String::from_array(out)
    }
  }
}

///|
/// PEP 639 license expressions at their edges: the SPDX identifier lookups, the
/// operators, the `LicenseRef-` and `DocumentRef-` forms, and the shapes the
/// grammar rejects.
fn curated_licenses() -> Array[String] {
  [
    // plain identifiers, and the case folding that finds them
    "MIT", "mit", "MiT", "Apache-2.0", "apache-2.0", "APACHE-2.0", "BSD-3-Clause",
    "GPL-2.0-only", "gpl-2.0-ONLY", "0BSD", "blessing", "curl", "xinetd",
    // the identifiers whose canonical spelling is not a title case transform
     "BSD-2-Clause-FreeBSD", "CC-BY-SA-4.0", "LGPL-2.1-or-later", "AGPL-3.0-or-later",
    "GFDL-1.3-invariants-or-later", "Zlib", "zlib-acknowledgement", "ZPL-2.1",
    // operators, in every case and with every padding
     "MIT OR Apache-2.0", "mit or apache-2.0", "MIT and Apache-2.0", "MIT AND Apache-2.0",
    "MIT  AND  Apache-2.0", "MIT\tOR\tApache-2.0", "MIT\nOR\nApache-2.0", "MIT OR Apache-2.0 OR BSD-3-Clause",
    "MIT AND Apache-2.0 AND BSD-3-Clause",
    // and binds tighter than or, but neither is reordered
     "MIT AND Apache-2.0 OR BSD-3-Clause", "MIT OR Apache-2.0 AND BSD-3-Clause",
    // parentheses, which are only padding in this grammar
     "(MIT)", "(mit)", "( MIT )", "((MIT))", "(MIT OR Apache-2.0) AND BSD-3-Clause",
    "MIT AND (Apache-2.0 OR BSD-3-Clause)",
    // the `+` suffix
     "MIT+", "GPL-2.0+", "CDDL-1.0+", "MIT++",
    // license references
     "LicenseRef-a", "licenseref-a", "LICENSEREF-A", "LicenseRef-a.b-c", "LicenseRef-a OR LicenseRef-A",
    "LicenseRef-a WITH LicenseRef-b", "DocumentRef-doc:LicenseRef-a", "DocumentRef-doc:licenseref-a",
    // exceptions
     "GPL-2.0-only WITH Classpath-exception-2.0", "gpl-2.0-only with classpath-exception-2.0",
    "GPL-2.0-only WITH Bison-exception-2.2", "MIT WITH Autoconf-exception-2.0", "GPL-2.0-only WITH (Classpath-exception-2.0)",
    // rejected
     "", "   ", "nope", "MIT OR", "OR MIT", "MIT AND", "AND MIT", "MIT OR OR MIT",
    "MIT WITH", "WITH MIT", "MIT WITH MIT", "MIT WITH nope", "MIT+ OR GPL-2.0+",
    "LicenseRef-", "LicenseRef-a+", "DocumentRef-:LicenseRef-a", "DocumentRef-doc:MIT",
    "MIT(mit)", "MIT OR(", "MIT)", "(MIT", "MIT;Apache-2.0", "MIT,Apache-2.0", "mit license",
    "MIT OR MIT WITH", "WITH Classpath-exception-2.0", "GPL-2.0-only WITH Classpath-exception-2.0 WITH Bison-exception-2.2",
    "LicenseRef-a OR LicenseRef-a", "()", "( )", "MIT WITH ()",
  ]
}

///|
fn license_pool() -> Array[Char] {
  [
    '(', ')', ' ', '+', '-', '.', ':', 'A', 'a', 'M', 'T', 'R', 'O', 'D', 'N', 'W',
    'H', 'L', 'e', 'f', 's', 'c', 'n', '0', '9', ',',
  ]
}

///|
fn mutate_license(rng : Rng, source : String) -> String {
  let pool = license_pool()
  let chars = source.to_array()
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
        out.push(chars[i])
        if i == at {
          out.push(replacement)
        }
      }
      String::from_array(out)
    }
  }
}

///|
fn license_opt(raw : String) -> String? {
  Some(@pyversion.canonicalize_license_expression(raw)) catch {
    _ => None
  }
}

///|
/// Emit one license expression record.
fn emit_license(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string("\{source}\tlicense\t\{escape_record(raw)}\t")
  match license_opt(raw) {
    Some(canonical) => sb.write_string("ok\t\{escape_record(canonical)}\n")
    None => sb.write_string("bad\t-\n")
  }
}

///|
/// Emit the declared divergences for core metadata. These are inputs rather than
/// checks: they tell the harness which documents this library deliberately
/// answers differently from the reference implementation, and in which
/// direction, so a difference that is not declared is a failure and a declared
/// one is asserted in both directions.
fn emit_metadata_divergences(sb : StringBuilder) -> Unit {
  for entry in @fixtures.metadata_divergences {
    let expectation = if entry.1 { "accept" } else { "reject" }
    sb.write_string(
      "curated\tmeta_divergence\t\{escape_record(entry.0)}\t\{expectation}\n",
    )
  }
}

///|
/// Emit one core metadata record.
///
/// A rejected document reports the stable error code this library produced; an
/// accepted one also reports the canonical re-rendering. The harness re-parses
/// that text with the reference implementation and compares a projection of the
/// values against the reference's own parse of the original, which checks the
/// rules, the field values and the round trip in one record.
fn emit_metadata(
  source : String,
  sb : StringBuilder,
  name : String,
  document : String,
) -> Unit {
  sb.write_string(
    "\{source}\tmeta\t\{escape_record(name)}\t\{escape_record(document)}\t",
  )
  match metadata_opt(document) {
    Some(metadata) =>
      sb.write_string("ok\t-\t\{escape_record(metadata.to_string())}\n")
    None => {
      let code = metadata_error_code(document)
      sb.write_string("bad\t\{escape_record(code)}\t-\n")
    }
  }
}

///|
/// Emit the values `Metadata::parse` extracted from `document`, one record per
/// value, as
/// `<source>\tmeta_values\t<case name>\t<field>\t<index>\t<value>`.
///
/// This asks a different question from the `meta` record beside it. That one asks
/// whether the two implementations agree on *acceptance*, and whether the
/// canonical re-rendering the library produces means the same thing to the
/// reference implementation. This one asks whether the values themselves are the
/// same values -- which the round trip cannot answer, because `packaging` strips
/// whitespace and canonicalizes names on the way in, so a spelling this library
/// got wrong is normalised away by the very step meant to check it. The
/// `Keywords` whitespace rule is exactly that shape of mistake, and is why these
/// records exist.
///
/// A list-valued field also carries a record with the index `-` whose value is the
/// number of entries, so a list that comes out too short is a difference rather
/// than a record that simply is not there. A scalar that may be absent is always
/// emitted, with `-` for absent, for the same reason.
fn emit_metadata_values(
  source : String,
  sb : StringBuilder,
  name : String,
  document : String,
) -> Unit {
  let metadata = match metadata_opt(document) {
    Some(metadata) => metadata
    None => return
  }
  let write = fn(field : String, index : String, value : String) -> Unit {
    sb.write_string(
      "\{source}\tmeta_values\t\{escape_record(name)}\t\{field}\t\{index}\t\{escape_record(value)}\n",
    )
  }
  // The name as the library would compare it, and the version as it would print
  // it: the two values a resolver matches on.
  write("name", "-", @pyversion.canonicalize_name(metadata.name))
  write("version", "-", metadata.version.to_string())
  // `Keywords`, entry by entry: the field whose parts are stripped.
  write("keywords", "-", metadata.keywords.length().to_string())
  for i, keyword in metadata.keywords {
    write("keywords", i.to_string(), keyword)
  }
  // `Provides-Extra` in the PEP 685 compare form, which is what the reference
  // reports as well.
  let extras = metadata.extras()
  write("provides-extra", "-", extras.length().to_string())
  for i, extra in extras {
    write("provides-extra", i.to_string(), extra)
  }
  // `Requires-Python` as *parsed and re-rendered*, not as written, and how many
  // `Requires-Dist` lines there are. The raw spelling is the document's -- real
  // metadata on PyPI writes `>=2.6, !=3.0.*` with a space -- while the reference
  // re-renders the set it parsed (`!=3.0.*,>=2.6`). Those are two different
  // things, and comparing them would report whitespace and ordering that no rule
  // governs; the set the library matches with is what has to agree.
  let requires_python = match metadata.requires_python() {
    Some(specifier) => specifier.to_string()
    None => "-"
  }
  write("requires-python", "-", requires_python)
  write("requires-dist", "-", metadata.requires_dist.length().to_string())
  // Whether a summary is present at all: the text itself is long and is already
  // covered by the round trip, but presence is a rule of its own.
  let summary = match metadata.summary {
    Some(_) => "1"
    None => "0"
  }
  write("summary", "-", summary)
}

///|
fn metadata_opt(document : String) -> @pyversion.Metadata? {
  Some(@pyversion.Metadata::parse(document)) catch {
    _ => None
  }
}

///|
/// The stable error code of a rejected document, or `<no error>` when it parses
/// after all (which cannot happen at a call site that already decided it does
/// not, and is reported rather than silently turned into a success).
fn metadata_error_code(document : String) -> String {
  try {
    ignore(@pyversion.Metadata::parse(document))
    "<no error>"
  } catch {
    @pyversion.InvalidMetadata(code, _) => code
    _ => "OTHER_ERROR"
  }
}

///|
/// Escape one field of an index projection.
///
/// The projection is a flat string whose separators are `;`, `|`, `,` and `=`,
/// and any of those can occur inside a JSON string (a `url`, a `yanked` reason).
/// Escaping them here keeps the encoding injective, so two different documents
/// cannot produce the same projection. `tools/fetch_index_corpus.py` applies the
/// same transformation when it computes the projection independently.
fn escape_projection(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c == '\\' {
      out.write_string("\\\\")
    } else if c == '|' {
      out.write_string("\\p")
    } else if c == ';' {
      out.write_string("\\s")
    } else if c == ',' {
      out.write_string("\\c")
    } else if c == '=' {
      out.write_string("\\e")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// The PEP 691 mapping of one parsed response, written out the way the reference
/// implementation in `tools/fetch_index_corpus.py` writes it.
///
/// Both sides derive this from the document independently -- this function from
/// the parsed `SimpleIndex`, the Python one from `json.loads` plus the rules of
/// the specification -- and a record is only accepted when the two strings are
/// equal, so the mapping itself is what is being compared.
fn index_projection(index : @pyversion.SimpleIndex) -> String {
  let out = StringBuilder()
  out.write_string("name=" + escape_projection(index.name()))
  let api_version = match index.api_version() {
    Some(text) => text
    None => ""
  }
  out.write_string(";api-version=" + escape_projection(api_version))
  out.write_string(";versions=\{index.versions().length()}")
  let files = index.files()
  out.write_string(";files=\{files.length()}")
  for file in files {
    out.write_string(";file:" + escape_projection(file.filename))
    out.write_string("|" + escape_projection(file.url))
    // the `hashes` member is a map: rendered in algorithm order, as the
    // reference implementation's `sorted()` does
    out.write_string("|" + render_hashes(file.hashes))
    let requires_python = match file.requires_python {
      Some(text) => text
      None => ""
    }
    out.write_string("|" + escape_projection(requires_python))
    out.write_string("|" + escape_projection(render_yanked(file.yanked)))
    let size = match file.size {
      Some(count) => count.to_string()
      None => ""
    }
    out.write_string("|" + size)
    let upload_time = match file.upload_time {
      Some(text) => text
      None => ""
    }
    out.write_string("|" + escape_projection(upload_time))
  }
  out.to_string()
}

///|
fn render_hashes(hashes : Array[(String, String)]) -> String {
  let keys : Array[String] = []
  let map : Map[String, String] = Map([])
  for entry in hashes {
    map[entry.0] = entry.1
    keys.push(entry.0)
  }
  let sorted = keys.copy()
  sorted.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  let out = StringBuilder()
  let mut first = true
  for key in sorted {
    // a repeated algorithm keeps its last value on both sides
    if map.get(key) is Some(digest) {
      if !first {
        out.write_string(",")
      }
      out.write_string(escape_projection(key) + "=" + escape_projection(digest))
      first = false
    }
  }
  out.to_string()
}

///|
fn render_yanked(yanked : @pyversion.SimpleYanked) -> String {
  match yanked {
    NotYanked => "not-yanked"
    Yanked(reason) => "yanked:" + reason
  }
}

///|
/// Emit one PEP 691 simple-index record.
///
/// A document the index specification accepts also reports the projection above;
/// a rejected one reports the stable error code. The harness parses the same
/// document with `json` and re-derives the projection, so both the verdict and
/// the mapping are compared.
fn emit_index(
  source : String,
  sb : StringBuilder,
  name : String,
  document : String,
) -> Unit {
  sb.write_string(
    "\{source}\tindex\t\{escape_record(name)}\t\{escape_record(document)}\t",
  )
  match index_opt(document) {
    Some(index) =>
      sb.write_string("ok\t\{escape_record(index_projection(index))}\n")
    None =>
      sb.write_string("bad\t\{escape_record(index_error_code(document))}\n")
  }
}

///|
fn index_opt(document : String) -> @pyversion.SimpleIndex? {
  Some(@pyversion.SimpleIndex::parse(document)) catch {
    _ => None
  }
}

///|
fn index_error_code(document : String) -> String {
  try {
    ignore(@pyversion.SimpleIndex::parse(document))
    "<no error>"
  } catch {
    @pyversion.InvalidIndex(code, _) => code
    _ => "OTHER_ERROR"
  }
}

///|
/// Emit the declared PEP 691 divergences: documents this library deliberately
/// answers differently from Python's `json`, and in which direction. They are
/// inputs rather than checks, so the harness can assert that the two answers
/// really do differ.
fn emit_index_divergences(sb : StringBuilder) -> Unit {
  for entry in @fixtures.index_divergences {
    let expectation = if entry.1 { "accept" } else { "reject" }
    sb.write_string(
      "curated\tindex_divergence\t\{escape_record(entry.0)}\t\{expectation}\n",
    )
  }
}

///|
/// One `IndexFile` for a distribution filename, built the way the resolver's
/// callers build them: the name is PEP 503 normalized and the version comes from
/// the file name. `None` when the name is not a distribution name at all.
fn index_file_of(
  filename : String,
  requires_python : String?,
) -> @pyversion.IndexFile? {
  match wheel_name_opt(filename) {
    Some(wheel) =>
      Some({
        filename,
        path: filename,
        kind: @pyversion.WheelFile,
        name: @pyversion.canonicalize_name(wheel.name),
        version: wheel.version,
        requires_python,
      })
    None =>
      match sdist_name_opt(filename) {
        Some(sdist) =>
          Some({
            filename,
            path: filename,
            kind: @pyversion.SdistFile,
            name: @pyversion.canonicalize_name(sdist.name),
            version: sdist.version,
            requires_python,
          })
        None => None
      }
  }
}

///|
fn wheel_name_opt(filename : String) -> @pyversion.WheelFilename? {
  Some(@pyversion.parse_wheel_filename(filename)) catch {
    _ => None
  }
}

///|
fn sdist_name_opt(filename : String) -> @pyversion.SdistFilename? {
  Some(@pyversion.parse_sdist_filename(filename)) catch {
    _ => None
  }
}

///|
/// `filename@requires-python`, the self-contained encoding of a candidate set,
/// so the harness recomputes the resolver's answer from the record alone.
fn render_candidate(filename : String, requires_python : String?) -> String {
  let constraint = match requires_python {
    Some(text) => text
    None => "-"
  }
  escape_projection(filename) + "@" + escape_projection(constraint)
}

///|
/// Emit one resolver record.
///
/// The record carries its own inputs -- the requirement, the candidate files
/// with their `Requires-Python` constraints, the ordered tag list, the
/// interpreter and the prerelease mode -- so the harness recomputes the answer
/// from the record rather than from a shared list. Both sides therefore have to
/// agree on the selection *and* the order, and a rejected file also carries the
/// rule that rejected it.
fn emit_resolve(
  source : String,
  sb : StringBuilder,
  requirement_text : String,
  candidates : Array[(String, String?)],
  tags : Array[String],
  python : String?,
  mode : String,
) -> Unit {
  sb.write_string("\{source}\tresolve\t\{escape_record(requirement_text)}\t")
  let files : Array[String] = []
  for candidate in candidates {
    files.push(render_candidate(candidate.0, candidate.1))
  }
  sb.write_string(escape_record(join_fields(files)) + "\t")
  sb.write_string(escape_record(join_fields(tags)) + "\t")
  let interpreter = match python {
    Some(text) => text
    None => "-"
  }
  sb.write_string(escape_record(interpreter) + "\t" + mode + "\t")
  match resolve_inputs(requirement_text, candidates, tags, python, mode) {
    None => sb.write_string("bad\t-\t-\n")
    Some(inputs) => {
      let (kept, rejections) = inputs
      let names : Array[String] = []
      for file in kept {
        names.push(file.filename)
      }
      sb.write_string(escape_record(join_fields(names)) + "\t")
      let reasons : Array[String] = []
      for entry in rejections {
        reasons.push(escape_projection(entry.0) + "=" + entry.1)
      }
      sb.write_string(escape_record(join_fields(reasons)) + "\n")
    }
  }
}

///|
/// `Some((candidates in order, rejections))` for one resolver record, or `None`
/// when the requirement or a filename does not parse -- which the harness reads
/// as a rejected record rather than as an empty answer.
fn resolve_inputs(
  requirement_text : String,
  candidates : Array[(String, String?)],
  tags : Array[String],
  python : String?,
  mode : String,
) -> (Array[@pyversion.IndexFile], Array[(String, String)])? {
  let requirement = @pyversion.Requirement::parse(requirement_text) catch {
    _ => return None
  }
  let files : Array[@pyversion.IndexFile] = []
  for candidate in candidates {
    match index_file_of(candidate.0, candidate.1) {
      Some(file) => files.push(file)
      None => return None
    }
  }
  let interpreter = match python {
    Some(text) =>
      match parse_opt(text) {
        Some(version) => Some(version)
        None => return None
      }
    None => None
  }
  let prereleases = mode_to_prereleases(mode)
  let rejected = @pyversion.explain_rejection(
    files,
    requirement,
    tags,
    interpreter,
    prereleases~,
  )
  let kept = @pyversion.resolve_candidates(
    files,
    requirement,
    tags,
    interpreter,
    prereleases~,
  )
  Some((kept, rejected))
}

///|
fn mode_to_prereleases(mode : String) -> Bool? {
  match mode {
    "any" => Some(true)
    "none" => Some(false)
    _ => None
  }
}

///|
/// The resolver records: a requirement, a candidate set with `Requires-Python`
/// constraints, an ordered tag list (most specific first, as
/// `packaging.tags.sys_tags()` orders it), an interpreter, and a prerelease
/// mode. The sets are small but every rule of the resolver is reachable: a name
/// from another project, a version out of range, a prerelease dropped by the
/// policy, a constraint that excludes the interpreter, a wheel for another
/// platform, a wheel that outranks an sdist of the same version, a build tag
/// tie-break, and the same version published twice.
fn resolver_cases() -> Array[
  (String, Array[(String, String?)], Array[String], String?, String),
] {
  let tags : Array[String] = [
    "cp312-cp312-manylinux_2_17_x86_64", "cp312-abi3-manylinux_2_17_x86_64", "cp312-none-manylinux_2_17_x86_64",
    "py3-none-any", "py2.py3-none-any", "cp312-cp312-win_amd64",
  ]
  let linux_only : Array[String] = [
    "cp312-cp312-manylinux_2_17_x86_64", "py3-none-any",
  ]
  let wheels : Array[(String, String?)] = [
    ("demo-1.0-py3-none-any.whl", None),
    ("demo-1.0.tar.gz", None),
    ("demo-1.1-py3-none-any.whl", None),
    ("demo-1.1-cp312-cp312-win_amd64.whl", None),
    ("demo-2.0rc1-py3-none-any.whl", None),
    ("demo-2.0-py3-none-any.whl", None),
    ("demo-2.0-1-py3-none-any.whl", None),
    ("demo-2.0-2-py3-none-any.whl", None),
    ("demo-2.0.tar.gz", None),
    ("other-3.0-py3-none-any.whl", None),
    ("demo-3.0-py3-none-any.whl", Some(">=3.13")),
    ("demo-3.0-py3-none-any.whl", Some("nonsense")),
    ("demo-0.9-py3-none-any.whl", None),
    ("demo-1.0+local-py3-none-any.whl", None),
  ]
  [
    ("demo", wheels, tags, Some("3.12.3"), "auto"),
    ("demo", wheels, tags, Some("3.12.3"), "any"),
    ("demo", wheels, tags, Some("3.12.3"), "none"),
    ("demo", wheels, linux_only, Some("3.12.3"), "auto"),
    ("demo>=1.1", wheels, tags, Some("3.12.3"), "auto"),
    ("demo==1.0", wheels, tags, Some("3.12.3"), "auto"),
    ("demo~=1.0", wheels, tags, Some("3.12.3"), "auto"),
    ("demo!=1.1", wheels, tags, Some("3.12.3"), "auto"),
    ("demo==2.0.*", wheels, tags, Some("3.12.3"), "auto"),
    ("demo", wheels, tags, None, "auto"),
    ("demo", wheels, tags, Some("3.13.0"), "auto"),
    ("demo", wheels, ["py3-none-any"], Some("3.12.3"), "auto"),
    ("demo", wheels, [], Some("3.12.3"), "auto"),
    ("demo[extra]>=1.0", wheels, tags, Some("3.12.3"), "auto"),
    ("other", wheels, tags, Some("3.12.3"), "auto"),
    ("missing", wheels, tags, Some("3.12.3"), "auto"),
    ("demo", [], tags, Some("3.12.3"), "auto"),
    ("demo ; python_version >= '3.12'", wheels, tags, Some("3.12.3"), "auto"),
  ]
}

///|
/// Emit one directory-scan record.
///
/// The listing is injected -- `moonbitlang/core` has no filesystem package -- so
/// the same record is reproducible everywhere, and the harness replays the same
/// entry list with its own filename parsers. The projection lists every
/// recognized distribution as `name|version|kind|filename`, in the order the
/// scanner returns them, which is the order both sides have to agree on.
fn emit_index_dir(
  source : String,
  sb : StringBuilder,
  directory : String,
  entries : Array[String],
) -> Unit {
  sb.write_string(
    "\{source}\tindex_dir\t\{escape_record(directory)}\t\{escape_record(join_fields(entries))}\t",
  )
  match index_dir_opt(directory, entries) {
    Some(index) =>
      sb.write_string("ok\t\{escape_record(index_dir_projection(index))}\n")
    None => sb.write_string("bad\tINDEX_UNCLASSIFIED\n")
  }
}

///|
fn index_dir_opt(
  directory : String,
  entries : Array[String],
) -> @pyversion.LocalIndex? {
  Some(@pyversion.LocalIndex::scan(directory, lister=fn(_) { entries })) catch {
    _ => None
  }
}

///|
fn index_dir_projection(index : @pyversion.LocalIndex) -> String {
  let out = StringBuilder()
  out.write_string("directory=" + escape_projection(index.directory))
  let files = index.files
  out.write_string(";files=\{files.length()}")
  for file in files {
    let kind = match file.kind {
      WheelFile => "wheel"
      SdistFile => "sdist"
    }
    out.write_string(
      ";file:" +
      escape_projection(file.name) +
      "|" +
      escape_projection(file.version.to_string()) +
      "|" +
      kind +
      "|" +
      escape_projection(file.filename),
    )
  }
  out.to_string()
}

///|
/// Join record fields with `|`, escaping the separator.
fn join_fields(values : Array[String]) -> String {
  let out = StringBuilder()
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      out.write_string("|")
    }
    out.write_string(escape_projection(values[i]))
  }
  out.to_string()
}

///|
/// The directory listings the scanner records run on. The names are the ones a
/// real download directory holds: wheels with and without a build tag, wheels
/// for other platforms, sdists, and files that are not distributions at all
/// (a README, a lock file, a partial download, a directory).
fn index_directories() -> Array[(String, Array[String])] {
  [
    (
      "/srv/wheels",
      [
        "README.txt", "requirements.txt", "pip.conf", "sha256sums", "Flask-3.0.2.tar.gz",
        "Flask-3.0.3-py3-none-any.whl", "Flask-3.0.4-1-py3-none-any.whl", "flask-3.0.4-py3-none-any.whl",
        "zope.interface-6.0.zip", "zope.interface-6.1-cp312-cp312-win_amd64.whl",
        "numpy-1.26.3.tar.gz", "numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.whl",
        "pkg-a-1.0.0.dev1-py3-none-any.whl", "pkg_a-1.0.0.tar.gz", "pkg-a-2.0.0-py3-none-any.whl",
      ],
    ),
    (
      // the names here are chosen so that MoonBit's default `String` order -- which
      // compares length first -- and code point order disagree: "b" sorts before
      // "ab" by length and after it by code point.
      "/srv/names",
      [
        "b-1.0.tar.gz", "ab-1.0.tar.gz", "zzz-1.0.tar.gz", "a-b-1.0.tar.gz", "ab_2-1.0.tar.gz",
        "Ab-2.0.tar.gz",
      ],
    ),
    ("/srv/empty", []),
    (
      "/srv/odd",
      [
        "broken-1.0.whl", "1.0.tar.gz", "-1.0-py3-none-any.whl", "demo.tar.gz", "demo-1.0.whl",
        "demo-1.0-py3-none-any.whl.part", "demo-1.0-py3-none-any.whl", "Demo-1.0-py3-none-any.whl",
        "demo-1.0.tar.gz", "demo-1.0.zip", "demo-1.0.zip.sha256",
      ],
    ),
    (
      // a subdirectory whose name looks like a distribution: a scan classifies by
      // name only, never stat-ing the entry
      "/srv/tricky",
      [
        "demo-1.0-py3-none-any.whl", "demo-2.0.tar.gz/", "..", ".", "demo-1.0+local-py3-none-any.whl",
        "demo-1.0.post1.tar.gz",
      ],
    ),
  ]
}

///|
/// Emit one TOML conformance record.
///
/// A rejected document reports only the rejection; an accepted one also reports
/// the library's canonical re-serialization. The oracle re-parses that text and
/// compares it, value by value, against its own parse of the original, which
/// checks the grammar, the values and the round trip in one record.
///
/// `lenient` marks the small set of documents TOML 1.0 requires us to reject
/// while the reference reader accepts them, and `lenient-drift` marks a
/// declared leniency that the library now accepts after all. Recording both
/// directions keeps the divergence asserted instead of tolerated: a test that
/// only ever sees "the reference is looser here" would stay green if the
/// library quietly grew as loose as the reference.
fn emit_toml(
  source : String,
  sb : StringBuilder,
  name : String,
  document : String,
  expected_accept : Bool,
) -> Unit {
  sb.write_string(
    "\{source}\ttoml\t\{escape_record(name)}\t\{escape_record(document)}\t",
  )
  match toml_parse_opt(document) {
    Some(table) =>
      if @fixtures.toml_leniencies.contains(name) {
        // this document is supposed to be rejected; accepting it is the drift
        sb.write_string("lenient-drift\t-\n")
      } else if expected_accept {
        sb.write_string("ok\t\{escape_record(table.to_string())}\n")
      } else {
        // the oracle rejects this document, so reporting a rendering would make
        // the record ambiguous
        sb.write_string("ok\t-\n")
      }
    None =>
      if @fixtures.toml_leniencies.contains(name) {
        sb.write_string("lenient\t-\n")
      } else {
        sb.write_string("bad\t-\n")
      }
  }
}

///|
fn toml_parse_opt(document : String) -> @pyversion.Toml? {
  Some(@pyversion.Toml::parse(document)) catch {
    _ => None
  }
}

///|
/// Requirement lines that exercise the PEP 508 grammar at its edges: the two
/// operand forms (`name specifier` and `name @ url`), extras, markers, and a
/// batch of lines that `packaging` rejects.
fn curated_requirements() -> Array[String] {
  [
    // plain names, with and without extras
    "foo", "foo==1.0", "foo >=1.0", "foo>=1.0,<2.0", "foo != 1.0.*", "foo~=1.4.2",
    "Requests[Security]", "Requests[Security]>=2.0,<3.0; python_version >= \"3.8\"",
    "foo[a,b]", "foo[a, b]", "foo[ a ]", "foo[]", "foo[Bar.Baz]", "foo[a-b_c.d]",
    // markers
     "foo; python_version < \"3.10\"", "foo; python_version<'3.10'", "foo>=1.0 ; extra == \"test\"",
    "foo; os_name == \"posix\" and python_version >= \"3.8\"", "foo; (python_version >= \"3.8\" or os_name == \"posix\") and extra == \"x\"",
    "foo; sys_platform == \"win32\"",
    // url form
     "foo @ https://example.com/foo-1.0.tar.gz", "foo[bar] @ file:///tmp/foo.zip",
    "foo @ file:///tmp/foo.zip ; python_version < \"3.9\"", "foo@https://example.com",
    // parenthesised specifier, a legacy spelling packaging still accepts
     "foo(>=1.0)", "foo (>=1.0,<2.0)", "foo ( >= 1.0 )",
    // names that are legal in different ways
     "1foo", "foo_", "foo._", "a-b_c.d", "FOO", "x", "zope.interface>=5", "importlib_metadata; python_version < \"3.8\"",
    // rejected by packaging
     "", "  ", "foo bar", "foo[", "foo]", "foo[ex", "foo>= ", "foo>=", "foo @ ",
    "foo @@bar", ">=1.0", "foo-", "foo.", "-foo", ".foo", "_foo", "foo_-", "a.",
    ".a", "_a", "foo!", "foo==1.0 extra", "foo;", "foo; and", "foo[extra] @ url2 url3",
    "foo@", "nil",
  ]
}

///|
/// Characters used to perturb requirement lines. Brackets, operators and the
/// semicolon are all in the pool so the mutants frequently become ungrammatical.
fn requirement_pool() -> Array[Char] {
  [
    '[', ']', ',', ';', '@', '=', '<', '>', '~', '(', ')', ' ', '"', '!', '.', '_',
    '-', 'a', 'z', '0', '9', '*', '|',
  ]
}

///|
fn mutate_requirement(rng : Rng, source : String) -> String {
  let pool = requirement_pool()
  let chars = source.to_array()
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
        out.push(chars[i])
        if i == at {
          out.push(replacement)
        }
      }
      String::from_array(out)
    }
  }
}

///|
fn requirement_opt(raw : String) -> @pyversion.Requirement? {
  Some(@pyversion.Requirement::parse(raw)) catch {
    _ => None
  }
}

///|
/// Emit one requirement record. The marker is reported as raw text and only its
/// presence is compared against the oracle, because canonicalising marker
/// rendering (quote style, redundant parentheses) is `markers.mbt`'s job.
fn emit_req(source : String, sb : StringBuilder, raw : String) -> Unit {
  sb.write_string("\{source}\treq\t\{raw}\t")
  match requirement_opt(raw) {
    Some(requirement) => {
      let extras = if requirement.extras.length() == 0 {
        "-"
      } else {
        requirement.extras.join("|")
      }
      let url = match requirement.url {
        Some(value) => value
        None => "-"
      }
      let marker = match requirement.marker_text {
        Some(value) => value
        None => "-"
      }
      sb.write_string(
        "ok\t\{requirement.name}\t\{extras}\t\{requirement.specifier.to_string()}\t\{url}\t\{marker}\n",
      )
    }
    None => sb.write_string("bad\t-\t-\t-\t-\t-\n")
  }
}

///|
/// The environment the PEP 751 records decide package applicability in: the two
/// tables `fixtures/pylock_corpus.mbt` declares, so the projection and the
/// harness evaluate every marker against the same one.
fn pylock_marker_environment() -> @pyversion.MarkerEnvironment {
  let environment = @pyversion.MarkerEnvironment::new()
  for pair in @fixtures.pylock_environment {
    environment.set(pair.0, pair.1)
  }
  for entry in @fixtures.pylock_environment_sets {
    environment.set_names(entry.0, entry.1)
  }
  environment
}

///|
/// A list in the projection: its length, then the items in document order joined
/// by `^`. The length is written so an empty list and a list holding one empty
/// string cannot look alike.
fn pylock_list(items : Array[String]) -> String {
  let out = StringBuilder()
  out.write_string(items.length().to_string())
  for item in items {
    out.write_string("^")
    out.write_string(item)
  }
  out.to_string()
}

///|
/// A member that may be absent, as its text or `-`.
fn pylock_optional(value : String?) -> String {
  match value {
    Some(text) => text
    None => "-"
  }
}

///|
/// A parsed version as its PEP 440 rendering, or `-` when the member is absent.
fn pylock_version(value : @pyversion.Version?) -> String {
  match value {
    Some(version) => version.to_string()
    None => "-"
  }
}

///|
/// Whether a locked entry applies to the environment: `1`, `0`, or `!` when the
/// marker mentions a key the environment cannot answer. The `!` is a fact worth
/// recording -- an applicability question that cannot be answered is not the same
/// answer as `false`.
fn pylock_applies(
  locked : @pyversion.PylockPackage,
  environment : @pyversion.MarkerEnvironment,
) -> String {
  match (Some(locked.is_applicable(environment)) catch { _ => None }) {
    Some(true) => "1"
    Some(false) => "0"
    None => "!"
  }
}

///|
/// `0` or `1` for a member that is present or absent.
fn pylock_present(value : Bool) -> String {
  if value {
    "1"
  } else {
    "0"
  }
}

///|
/// The projection of one locked document: the document-level members, then one
/// group per locked entry, with its dependencies and file records.
///
/// The format is written down here and in `tools/fetch_pylock_corpus.py`, which
/// re-derives it from the specification with `tomli`, so a `pylock` record
/// compares the values a reader extracted, not merely its verdict. Groups are
/// separated by `|` and fields by `;`, and no value in the corpus contains
/// either (the harness checks that rather than assuming it).
fn pylock_projection(
  lock : @pyversion.Pylock,
  environment : @pyversion.MarkerEnvironment,
) -> String {
  let out = StringBuilder()
  out.write_string("lock-version=")
  out.write_string(lock.lock_version())
  out.write_string(";environments=")
  out.write_string(pylock_list(lock.environments()))
  out.write_string(";requires-python=")
  out.write_string(pylock_optional(lock.requires_python()))
  out.write_string(";extras=")
  out.write_string(pylock_list(lock.extras()))
  out.write_string(";dependency-groups=")
  out.write_string(pylock_list(lock.dependency_groups()))
  out.write_string(";default-groups=")
  out.write_string(pylock_list(lock.default_groups()))
  out.write_string(";created-by=")
  out.write_string(escape_projection(lock.created_by()))
  let packages = lock.packages()
  out.write_string(";packages=")
  out.write_string(packages.length().to_string())
  for i = 0; i < packages.length(); i = i + 1 {
    let locked = packages[i]
    out.write_string("|pkg")
    out.write_string(i.to_string())
    out.write_string(":name=")
    out.write_string(locked.name)
    out.write_string(";version=")
    out.write_string(pylock_version(locked.version))
    out.write_string(";marker=")
    out.write_string(pylock_optional(locked.marker))
    out.write_string(";applies=")
    out.write_string(pylock_applies(locked, environment))
    out.write_string(";requires-python=")
    out.write_string(pylock_optional(locked.requires_python))
    out.write_string(";deps=")
    out.write_string(locked.dependencies.length().to_string())
    out.write_string(";files=")
    out.write_string(locked.files.length().to_string())
    out.write_string(";wheels=")
    out.write_string(locked.wheels.length().to_string())
    out.write_string(";sdist=")
    out.write_string(pylock_present(locked.sdist is Some(_)))
    out.write_string(";archive=")
    out.write_string(pylock_present(locked.archive is Some(_)))
    out.write_string(";vcs=")
    out.write_string(pylock_present(locked.vcs is Some(_)))
    out.write_string(";directory=")
    out.write_string(pylock_present(locked.directory is Some(_)))
    out.write_string(";index=")
    out.write_string(pylock_optional(locked.index))
    out.write_string(";path=")
    out.write_string(pylock_present(locked.path is Some(_)))
    out.write_string(";all-files=")
    out.write_string(locked.all_files().length().to_string())
    for j = 0; j < locked.dependencies.length(); j = j + 1 {
      let dependency = locked.dependencies[j]
      out.write_string("|dep")
      out.write_string(i.to_string())
      out.write_string(".")
      out.write_string(j.to_string())
      out.write_string(":name=")
      out.write_string(dependency.name)
      out.write_string(";version=")
      out.write_string(pylock_version(dependency.version))
      out.write_string(";marker=")
      out.write_string(pylock_optional(dependency.marker))
      out.write_string(";extras=")
      out.write_string(pylock_list(dependency.extras))
    }
    // `all_files` fixes the order as files, sdist, wheels, archive, so the
    // ordinal is stable no matter which members the document used.
    for k = 0; k < locked.all_files().length(); k = k + 1 {
      let file = locked.all_files()[k]
      out.write_string("|file")
      out.write_string(i.to_string())
      out.write_string(".")
      out.write_string(k.to_string())
      out.write_string(":kind=")
      out.write_string(file.kind.key())
      out.write_string(";filename=")
      out.write_string(pylock_optional(file.filename()))
      out.write_string(";sha256=")
      out.write_string(pylock_optional(file.hash_for("sha256")))
      out.write_string(";size=")
      out.write_string(
        match file.size {
          Some(value) => value.to_string()
          None => "-"
        },
      )
      out.write_string(";upload-time=")
      out.write_string(pylock_optional(file.upload_time))
      out.write_string(";subdirectory=")
      out.write_string(pylock_optional(file.subdirectory))
    }
  }
  out.to_string()
}

///|
/// Emit one PEP 751 record.
///
/// A document the specification accepts also reports the projection above; a
/// rejected one reports the stable error code. The harness reads the same
/// document with `tomli`, applies the specification's rules independently and
/// recomputes the projection, so the verdict, the mapping and every extracted
/// value are compared.
fn emit_pylock(
  source : String,
  sb : StringBuilder,
  name : String,
  document : String,
) -> Unit {
  sb.write_string(
    "\{source}\tpylock\t\{escape_record(name)}\t\{escape_record(document)}\t",
  )
  match pylock_opt(document) {
    Some(lock) =>
      sb.write_string(
        "ok\t\{escape_record(pylock_projection(lock, pylock_marker_environment()))}\n",
      )
    None =>
      sb.write_string("bad\t\{escape_record(pylock_error_code(document))}\n")
  }
}

///|
fn pylock_opt(document : String) -> @pyversion.Pylock? {
  Some(@pyversion.Pylock::parse(document)) catch {
    _ => None
  }
}

///|
/// The stable code of a rejection, or the TOML layer's code when the document is
/// not TOML at all -- `pylock.mbt` leaves that diagnosis to `toml.mbt` on
/// purpose, because that reader owns the offset.
fn pylock_error_code(document : String) -> String {
  try {
    ignore(@pyversion.Pylock::parse(document))
    "<no error>"
  } catch {
    @pyversion.InvalidPylock(code, _) => code
    @pyversion.InvalidToml(code, _) => "toml:\{code}"
    _ => "OTHER_ERROR"
  }
}

///|
/// Emit the declared PEP 751 divergences: documents this library deliberately
/// answers differently from a strict reading of the specification, and in which
/// direction. They are inputs rather than checks, so the harness can assert that
/// the two answers really do differ.
fn emit_pylock_divergences(sb : StringBuilder) -> Unit {
  for entry in @fixtures.pylock_divergences {
    let expectation = if entry.1 { "accept" } else { "reject" }
    sb.write_string(
      "curated\tpylock_divergence\t\{escape_record(entry.0)}\t\{expectation}\n",
    )
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
  // 6. PEP 508 requirement lines, including the real `Requires-Dist` fixture.
  let curated_requirement_inputs = curated_requirements()
  for raw in curated_requirement_inputs {
    emit_req("curated", sb, raw)
  }
  for raw in @fixtures.pypi_requires_dist {
    emit_req("pypi", sb, raw)
  }
  let mutated_requirements : Array[String] = []
  for i = 0; i < 4000; i = i + 1 {
    let base = if i % 3 == 0 {
      curated_requirement_inputs[rng.below(curated_requirement_inputs.length())]
    } else {
      @fixtures.pypi_requires_dist[rng.below(
        @fixtures.pypi_requires_dist.length(),
      )]
    }
    if base.length() == 0 {
      mutated_requirements.push(
        String::from_array([rng.pick_char(requirement_pool())]),
      )
    } else {
      mutated_requirements.push(mutate_requirement(rng, base))
    }
  }
  for raw in mutated_requirements {
    emit_req("mutated", sb, raw)
  }
  // 7. PEP 508 markers: acceptance, canonical rendering, and evaluation against
  //    a handful of complete environments.
  let environments = marker_environments()
  for entry in environments {
    emit_marker_env("curated", sb, entry.0, entry.1)
  }
  let curated_marker_inputs = curated_markers()
  for raw in curated_marker_inputs {
    emit_marker("curated", sb, raw)
    for entry in environments {
      emit_marker_eval("curated", sb, entry.0, entry.2, raw)
    }
  }
  for raw in @fixtures.pypi_requires_dist {
    match requirement_opt(raw) {
      Some(requirement) =>
        match requirement.marker_text {
          Some(text) => emit_marker("pypi", sb, text)
          None => ()
        }
      None => ()
    }
  }
  let mutated_markers : Array[String] = []
  for i = 0; i < 4000; i = i + 1 {
    let base = if i % 3 == 0 {
      curated_marker_inputs[rng.below(curated_marker_inputs.length())]
    } else {
      curated_marker_inputs[rng.below(curated_marker_inputs.length())]
    }
    if base.length() == 0 {
      mutated_markers.push(String::from_array([rng.pick_char(marker_pool())]))
    } else {
      mutated_markers.push(mutate_marker(rng, base))
    }
  }
  for raw in mutated_markers {
    emit_marker("mutated", sb, raw)
    emit_marker_eval("mutated", sb, environments[0].0, environments[0].2, raw)
    emit_marker_eval("mutated", sb, environments[1].0, environments[1].2, raw)
  }
  // 8. TOML 1.0 documents, checked against the reference reader's verdict.
  for entry in @fixtures.toml_cases {
    emit_toml("curated", sb, entry.0, entry.1, entry.2)
  }
  // 9. PEP 639 license expressions.
  let curated_license_inputs = curated_licenses()
  for raw in curated_license_inputs {
    emit_license("curated", sb, raw)
  }
  let mutated_licenses : Array[String] = []
  for i = 0; i < 4000; i = i + 1 {
    if i % 2 == 0 {
      let base = curated_license_inputs[rng.below(
          curated_license_inputs.length(),
        )]
      if base.length() == 0 {
        mutated_licenses.push(
          String::from_array([rng.pick_char(license_pool())]),
        )
      } else {
        mutated_licenses.push(mutate_license(rng, base))
      }
    } else {
      // joining two expressions is a cheap way to produce long, usually broken
      // token sequences that a character mutation rarely reaches
      let left = curated_license_inputs[rng.below(
          curated_license_inputs.length(),
        )]
      let right = curated_license_inputs[rng.below(
          curated_license_inputs.length(),
        )]
      let joiner = if rng.below(2) == 0 { " OR " } else { " AND " }
      mutated_licenses.push(left + joiner + right)
    }
  }
  for raw in mutated_licenses {
    emit_license("mutated", sb, raw)
  }
  // 10. Core metadata (`METADATA` / `PKG-INFO`): the curated rule cases, then the
  //     real documents served next to PyPI wheels. The declared divergences are
  //     written first because they qualify documents by name.
  emit_metadata_divergences(sb)
  for entry in @fixtures.metadata_cases {
    emit_metadata("curated", sb, entry.0, entry.1)
    emit_metadata_values("curated", sb, entry.0, entry.1)
  }
  for entry in @fixtures.metadata_pypi_cases {
    emit_metadata("pypi", sb, entry.0, entry.1)
    emit_metadata_values("pypi", sb, entry.0, entry.1)
  }
  // 11. PEP 691 simple-index documents: the curated cases the specification
  //     accepts, the ones it requires a client to reject, and real responses from
  //     a public index.
  emit_index_divergences(sb)
  for entry in @fixtures.index_cases {
    emit_index("curated", sb, entry.0, entry.1)
  }
  for entry in @fixtures.index_divergence_cases {
    emit_index("curated", sb, entry.0, entry.1)
  }
  for entry in @fixtures.index_bad_cases {
    emit_index("curated_bad", sb, entry.0, entry.1)
  }
  for entry in @fixtures.index_pypi_cases {
    emit_index("pypi_index", sb, entry.0, entry.1)
  }
  // 12. Offline directory scans. The listing is injected, so the record is the
  //     scanner's classification of a fixed entry list.
  for entry in index_directories() {
    emit_index_dir("curated", sb, entry.0, entry.1)
  }
  // 13. Candidate resolution: which files a requirement selects, in which order,
  //     and why the rest were rejected.
  for entry in resolver_cases() {
    emit_resolve("curated", sb, entry.0, entry.1, entry.2, entry.3, entry.4)
  }
  // 14. PEP 751 lock files: the curated documents, the documents derived from
  //     real index responses, the real lock files uv wrote, and the declared
  //     divergences. The uv ones carry their own source name so a report can tell
  //     "a document this repository wrote" from "a document a third-party tool
  //     wrote" without a second table.
  emit_pylock_divergences(sb)
  for entry in @fixtures.pylock_cases {
    emit_pylock("curated", sb, entry.0, entry.1)
  }
  for entry in @fixtures.pylock_divergence_cases {
    emit_pylock("curated", sb, entry.0, entry.1)
  }
  for entry in @fixtures.pylock_bad_cases {
    emit_pylock("curated_bad", sb, entry.0, entry.1)
  }
  for entry in @fixtures.pylock_pypi_cases {
    emit_pylock("pypi_lock", sb, entry.0, entry.1)
  }
  for entry in @fixtures.pylock_uv_cases {
    emit_pylock("uv_lock", sb, entry.0, entry.1)
  }
  println(sb.to_string())
}
