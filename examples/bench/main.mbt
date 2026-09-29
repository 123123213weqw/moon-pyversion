///|
fn main raise {
  // Deterministic corpus: 2000 PEP 440 version strings cycling through
  // release, pre/post/dev, epoch and local shapes.
  let versions : Array[String] = []
  for i = 0; i < 2000; i = i + 1 {
    let shape = i % 5
    let base = (i / 5).to_string() +
      "." +
      (i % 9).to_string() +
      "." +
      (i % 7).to_string()
    let v = match shape {
      0 => base
      1 => base + "rc" + (i % 9).to_string()
      2 => base + ".post" + (i % 5).to_string()
      3 => "1!" + base + "+local" + (i % 11).to_string()
      _ => base + "a1.dev" + (i % 3).to_string()
    }
    versions.push(v)
  }
  // Warm up before timing.
  ignore(parse_probe(versions))
  let start = @mbench.monotonic_clock_start()
  let (ok, fail) = parse_probe(versions)
  let micros = @mbench.monotonic_clock_end(start)
  println("versions=" + versions.length().to_string())
  println("parse-ok=" + ok.to_string())
  println("parse-fail=" + fail.to_string())
  println("parse-micros=" + micros.to_string())
  if micros > 0.0 {
    println("parse-us-per-version=" + (micros / 2000.0).to_string())
  }
  // Specifier filtering: parse once, then 2000 containment checks.
  let spec = @pyversion.SpecifierSet::parse(">=1.0, !=2.3.*, <100.0")
  let parsed : Array[@pyversion.Version] = []
  for v in versions {
    parsed.push(@pyversion.Version::parse(v))
  }
  let filter_start = @mbench.monotonic_clock_start()
  let accepted = @pyversion.SpecifierSet::filter(parsed, spec).length()
  let filter_micros = @mbench.monotonic_clock_end(filter_start)
  println("filter-accepted=" + accepted.to_string())
  println("filter-micros=" + filter_micros.to_string())
  if filter_micros > 0.0 {
    println("filter-us-per-version=" + (filter_micros / 2000.0).to_string())
  }
  // Round-trip checksum: parse then serialize, counting output chars.
  let mut checksum = 0
  for v in versions {
    checksum += @pyversion.Version::to_string(@pyversion.Version::parse(v)).length()
  }
  println("roundtrip-char-checksum=" + checksum.to_string())
}

///|
fn parse_probe(versions : Array[String]) -> (Int, Int) {
  let mut ok = 0
  let mut fail = 0
  for v in versions {
    match
      (try @pyversion.Version::parse(v) catch {
        _ => false
      } noraise {
        _ => true
      }) {
      true => ok += 1
      false => fail += 1
    }
  }
  (ok, fail)
}
