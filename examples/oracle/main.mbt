///|
fn main {
  let versions = [
    "0.9", "1", "1.0.0", "1.0.dev1", "1.0.dev2", "1.0a1", "1.0a1.dev1", "1.0a1.post1",
    "1.0a2.dev1", "1.0b1", "1.0rc1", "1.0", "1.0+ABC", "1.0+1", "1.0.post0.dev1",
    "1.0.post1.dev1", "1.0.post1", "1.0.post2", "1.1a1", "1.1", "1.1.post1", "1.2",
    "2.0a1", "2.0", "1!1.0",
  ]
  let specs = [
    "", "==1.0", "==1.0.*", "!=1.0.*", "!=1.0a1", "<1.0", "<=1.0", ">1.0", ">=1.0",
    "~=1.0", "~=1.0.0", "<1.0.post1", ">1.0.post1", ">1.0a1", ">1.0.dev1", "<1.0a1",
    ">=1.0a1", "===1.0+ABC", ">=1.0,!=1.1.*,<2.0",
  ]
  for a in versions {
    let av = try! @pyversion.Version::parse(a)
    for b in versions {
      let bv = try! @pyversion.Version::parse(b)
      println("compare\t\{a}\t\{b}\t\{av.compare(bv)}")
    }
    for s in specs {
      let spec = try! @pyversion.SpecifierSet::parse(s)
      println("auto\t\{s}\t\{a}\t\{spec.contains(av)}")
      println("true\t\{s}\t\{a}\t\{spec.contains(av, prereleases=Some(true))}")
      println(
        "false\t\{s}\t\{a}\t\{spec.contains(av, prereleases=Some(false))}",
      )
    }
  }
}
