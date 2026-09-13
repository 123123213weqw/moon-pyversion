///|
fn main {
  try {
    let raw = "v01.002-rc3+ABC_007"
    let v = @pyversion.Version::parse(raw)
    println("input      : \{v.raw}")
    println("normalized : \{@pyversion.Version::to_string(v)}")

    let earlier = try! @pyversion.Version::parse("1.0")
    let later = try! @pyversion.Version::parse("1.1.dev1")
    let ordering = if earlier < later {
      "1.0 < 1.1.dev1"
    } else {
      "unexpected ordering"
    }
    println("compare    : \{ordering}")

    let spec = try! @pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
    let candidates = [
      try! @pyversion.Version::parse("0.9"),
      try! @pyversion.Version::parse("1.0"),
      try! @pyversion.Version::parse("1.4.1"),
      try! @pyversion.Version::parse("1.5"),
      try! @pyversion.Version::parse("2.0"),
    ]
    let filtered = @pyversion.SpecifierSet::filter(candidates, spec)
    let b = StringBuilder()
    b.write_string("filter     : ")
    for i = 0; i < filtered.length(); i = i + 1 {
      if i > 0 {
        b.write_string(", ")
      }
      b.write_string(@pyversion.Version::to_string(filtered[i]))
    }
    println(b.to_string())
  } catch {
    @pyversion.VersionError::InvalidVersion(code, pos) =>
      println("VersionError: \{code} at \{pos}")
    @pyversion.VersionError::InvalidSpecifier(code, pos) =>
      println("SpecifierError: \{code} at \{pos}")
    @pyversion.VersionError::InvalidName(code, pos) =>
      println("NameError: \{code} at \{pos}")
    @pyversion.VersionError::InvalidFilename(code, pos) =>
      println("FilenameError: \{code} at \{pos}")
  }
}
