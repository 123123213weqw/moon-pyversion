///|
/// Throughput harness for the version and specifier hot paths.
///
/// It reuses the real-world corpus in the `fixtures` package so the
/// inputs are the same strings the differential oracle validates. Timing uses
/// `@env.now()`, which is millisecond resolution on every backend; each loop
/// runs long enough (hundreds of milliseconds) for that to be meaningful.
/// The numbers are wall clock figures for the machine and backend that run
/// them, not a cross-language benchmark.
///
/// Run with `moon run examples/bench --target js`.
fn report(
  label : String,
  iterations : Int,
  started : UInt64,
  checksum : Int,
) -> Unit {
  let elapsed_ms = @env.now() - started
  let nanos_per_op = if iterations > 0 {
    elapsed_ms * 1_000_000UL / iterations.to_uint64()
  } else {
    0UL
  }
  let ops_per_second = if elapsed_ms > 0 {
    iterations.to_uint64() * 1000UL / elapsed_ms
  } else {
    0UL
  }
  println(
    "\{label}: \{iterations} ops in \{elapsed_ms} ms, \{nanos_per_op} ns/op, \{ops_per_second} ops/s (checksum \{checksum})",
  )
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
fn corpus() -> Array[String] {
  let out : Array[String] = []
  for raw in @fixtures.pypi_versions {
    out.push(raw)
  }
  for raw in @fixtures.pypi_specifiers {
    out.push(raw)
  }
  out
}

///|
fn main {
  let inputs = corpus()
  let total = inputs.length()
  if total == 0 {
    println("empty corpus")
    return
  }
  let parsed : Array[@pyversion.Version] = []
  for raw in @fixtures.pypi_versions {
    match parse_opt(raw) {
      Some(v) => parsed.push(v)
      None => ()
    }
  }
  let specifiers : Array[@pyversion.SpecifierSet] = []
  for raw in @fixtures.pypi_specifiers {
    match spec_opt(raw) {
      Some(s) => specifiers.push(s)
      None => ()
    }
  }
  println(
    "corpus: \{total} strings, \{parsed.length()} versions, \{specifiers.length()} specifier sets",
  )

  // Parsing and normalizing.
  let parse_iterations = 200_000
  let mut checksum = 0
  let parse_started = @env.now()
  for i = 0; i < parse_iterations; i = i + 1 {
    let raw = inputs[i % total]
    match parse_opt(raw) {
      Some(v) => checksum += v.release.length()
      None => checksum += 1
    }
  }
  report("parse", parse_iterations, parse_started, checksum)

  // Ordering.
  let compare_iterations = 500_000
  checksum = 0
  let compare_started = @env.now()
  for i = 0; i < compare_iterations; i = i + 1 {
    if parsed.length() > 1 {
      let left = parsed[i % parsed.length()]
      let right = parsed[(i * 7 + 3) % parsed.length()]
      checksum += @pyversion.Version::compare(left, right)
    }
  }
  report("compare", compare_iterations, compare_started, checksum)

  // Membership and filtering.
  let contains_iterations = 200_000
  checksum = 0
  let contains_started = @env.now()
  for i = 0; i < contains_iterations; i = i + 1 {
    if specifiers.length() > 0 && parsed.length() > 0 {
      let spec = specifiers[i % specifiers.length()]
      let version = parsed[(i * 11 + 5) % parsed.length()]
      if spec.contains(version, prereleases=Some(true)) {
        checksum += 1
      }
    }
  }
  report("contains", contains_iterations, contains_started, checksum)

  let filter_iterations = 2_000
  checksum = 0
  let filter_started = @env.now()
  for i = 0; i < filter_iterations; i = i + 1 {
    if specifiers.length() > 0 && parsed.length() > 0 {
      let spec = specifiers[i % specifiers.length()]
      checksum += @pyversion.SpecifierSet::filter(
        parsed,
        spec,
        prereleases=Some(true),
      ).length()
    }
  }
  report("filter", filter_iterations, filter_started, checksum)
}
