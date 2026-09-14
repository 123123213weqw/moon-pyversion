///|
/// M4 tests: `toml.mbt`. The TOML 1.0 conformance cases in
/// `fixtures/toml_corpus.mbt` are generated from the reference reader `tomli`
/// and replayed against it by the differential corpus (`toml` records). The
/// tests here pin the individual rules, so a regression names the rule it
/// broke; the error codes are asserted too, because they are the diagnostic a
/// caller reads.

///|
fn toml_of(document : String) -> Toml {
  Toml::parse(document) catch {
    _ => abort("expected the document to parse: \{document}")
  }
}

///|
fn toml_rejected(document : String) -> Bool {
  try {
    ignore(Toml::parse(document))
    false
  } catch {
    _ => true
  }
}

///|
/// The error code of a rejected document, so a test can assert *why*.
fn toml_error_code(document : String) -> String {
  try {
    ignore(Toml::parse(document))
    "<accepted>"
  } catch {
    VersionError::InvalidToml(code, _) => code
    other => "unexpected:\{other.diagnostic()}"
  }
}

///|
test "toml: scalars" {
  let table = toml_of("s = \"x\"\ni = 42\nf = 3.5\nb = true\nc = false\n")
  assert_eq(table.get_string("s"), Some("x"))
  assert_eq(table.get_int("i"), Some(42))
  assert_eq(table.get_bool("b"), Some(true))
  assert_eq(table.get_bool("c"), Some(false))
  assert_true(table.get("f") is Some(TFloat(_)))
}

///|
test "toml: the four string flavours" {
  let table = toml_of(
    "a = \"basic \\\"q\\\"\"\nb = 'literal \\n'\nc = \"\"\"multi\nline\"\"\"\nd = '''literal\nmulti'''\n",
  )
  assert_eq(table.get_string("a"), Some("basic \"q\""))
  // a literal string has no escape processing at all, so this stays a backslash
  assert_eq(table.get_string("b"), Some("literal \\n"))
  // a newline directly after the opening triple quote is trimmed
  assert_eq(table.get_string("c"), Some("multi\nline"))
  assert_eq(table.get_string("d"), Some("literal\nmulti"))
}

///|
test "toml: multiline basic strings keep their first character" {
  // a leading-indent bug once ate the first character of every multiline
  // string, so this pins it explicitly
  assert_eq(toml_of("a = \"\"\"x\"\"\"\n").get_string("a"), Some("x"))
  assert_eq(toml_of("a = \"\"\"xyz\"\"\"\n").get_string("a"), Some("xyz"))
  assert_eq(toml_of("a = \"\"\"\nxyz\"\"\"\n").get_string("a"), Some("xyz"))
}

///|
test "toml: escapes" {
  let table = toml_of(
    "a = \"\\b\\t\\n\\f\\r\\\"\\\\\"\nb = \"\\u00e9\"\nc = \"\\U0001F600\"\n",
  )
  assert_eq(table.get_string("a"), Some("\u{8}\t\n\u{c}\r\"\\"))
  assert_eq(table.get_string("b"), Some("\u{e9}"))
  assert_eq(table.get_string("c"), Some("\u{1F600}"))
  // the escapes TOML 1.0 does not define are errors rather than passthroughs.
  // `\xHH` is one of them: it is a TOML 1.1 addition, so the reference reader
  // accepts it and this library does not (see toml_cases/leniencies.txt).
  assert_eq(toml_error_code("a = \"\\q\"\n"), "INVALID_ESCAPE")
  assert_eq(toml_error_code("a = \"\\x41\"\n"), "INVALID_ESCAPE")
  assert_eq(toml_error_code("a = \"\\uD800\"\n"), "INVALID_ESCAPE")
}

///|
test "toml: integers in every base, and the rules that bound them" {
  let table = toml_of(
    "d = 1_000\nh = 0xDEAD_beef\no = 0o755\nb = 0b1010\nneg = -17\nplus = +3\nzero = 0\nbig = 9223372036854775807\n",
  )
  assert_eq(table.get_int("d"), Some(1000))
  // TOML integers are 64-bit, so a value beyond 32 bits has to survive
  assert_eq(table.get_int("h"), Some(3735928559))
  assert_eq(table.get_int("big"), Some(9223372036854775807))
  assert_eq(table.get_int("o"), Some(493))
  assert_eq(table.get_int("b"), Some(10))
  assert_eq(table.get_int("neg"), Some(-17))
  assert_eq(table.get_int("plus"), Some(3))
  assert_eq(table.get_int("zero"), Some(0))
  // A leading zero, a misplaced underscore or a dot with no fraction digits
  // ends the number early, so what is left over is not a newline: the same
  // diagnosis the reference reader reports ("Expected newline or end of
  // document after a statement"). A value that never starts is "invalid value".
  assert_eq(toml_error_code("a = 01\n"), "EXPECTED_NEWLINE_OR_EOF")
  assert_eq(toml_error_code("a = 1__0\n"), "EXPECTED_NEWLINE_OR_EOF")
  assert_eq(toml_error_code("a = 1_\n"), "EXPECTED_NEWLINE_OR_EOF")
  assert_eq(toml_error_code("a = _1\n"), "INVALID_VALUE")
  assert_eq(
    toml_error_code("a = 9223372036854775808\n"),
    "INTEGER_OUT_OF_RANGE",
  )
  // Both ends of the range, which `toml_cases/47_int64_range.toml` also pins
  // against the reference reader: an accumulator narrower than 64 bits parses
  // the 32-bit cases above and then rejects these.
  assert_eq(
    toml_of("min = -9223372036854775808\n").get_int("min"),
    Some(-9223372036854775807 - 1),
  )
  assert_eq(toml_rejected("a = 9223372036854775808\n"), true)
}

///|
test "toml: floats and the special values" {
  let table = toml_of(
    "a = 1.0\nb = 5e22\nc = -0.01\nd = 6.626e-34\ne = inf\nf = -inf\ng = nan\n",
  )
  assert_true(table.get("a") is Some(TFloat(_)))
  assert_true(table.get("e") is Some(TFloat(_)))
  assert_true(table.get("g") is Some(TFloat(_)))
  // an exponent makes an integer literal a float
  assert_true(table.get("b") is Some(TFloat(_)))
  assert_eq(toml_error_code("a = .5\n"), "INVALID_VALUE")
  assert_eq(toml_error_code("a = 1.\n"), "EXPECTED_NEWLINE_OR_EOF")
  assert_eq(toml_error_code("a = 0x1p3\n"), "EXPECTED_NEWLINE_OR_EOF")
}

///|
test "toml: booleans are lowercase only" {
  assert_eq(toml_of("a = true\n").get_bool("a"), Some(true))
  assert_eq(toml_error_code("a = True\n"), "INVALID_VALUE")
  assert_eq(toml_error_code("a = FALSE\n"), "INVALID_VALUE")
}

///|
test "toml: datetimes keep their source spelling" {
  let table = toml_of(
    "a = 1979-05-27T07:32:00Z\nb = 1979-05-27T00:32:00-07:00\nc = 1979-05-27T07:32:00\nd = 1979-05-27\ne = 07:32:00\nf = 1979-05-27 07:32:00Z\n",
  )
  assert_eq(table.get("a"), Some(TDatetime("1979-05-27T07:32:00Z")))
  assert_eq(table.get("b"), Some(TDatetime("1979-05-27T00:32:00-07:00")))
  assert_eq(table.get("c"), Some(TDatetime("1979-05-27T07:32:00")))
  assert_eq(table.get("d"), Some(TDatetime("1979-05-27")))
  assert_eq(table.get("e"), Some(TDatetime("07:32:00")))
  // the space separator is accepted as written
  assert_eq(table.get("f"), Some(TDatetime("1979-05-27 07:32:00Z")))
  // and the calendar is checked, including leap years
  assert_eq(toml_error_code("a = 1979-02-30\n"), "INVALID_DATETIME")
  assert_eq(toml_error_code("a = 2023-02-29\n"), "INVALID_DATETIME")
  assert_true(!toml_rejected("a = 2024-02-29\n"))
  assert_eq(toml_error_code("a = 1979-13-01\n"), "INVALID_DATETIME")
  assert_eq(toml_error_code("a = 24:00:00\n"), "INVALID_DATETIME")
}

///|
test "toml: arrays, nesting and trailing commas" {
  let table = toml_of(
    "a = [1, 2, 3,]\nb = [[1], [2, 3]]\nc = []\nd = [\n  1,\n  2,\n]\n",
  )
  assert_eq(table.get_array("a").unwrap().length(), 3)
  assert_eq(table.get_array("b").unwrap().length(), 2)
  assert_eq(table.get_array("c").unwrap().length(), 0)
  assert_eq(table.get_array("d").unwrap().length(), 2)
  // TOML 1.0.0 dropped the 0.5 rule that array members share a type
  let mixed = toml_of("a = [1, \"x\", true]\n").get_array("a").unwrap()
  assert_eq(mixed.length(), 3)
  assert_eq(mixed[0], TInt(1))
  assert_eq(mixed[1], TString("x"))
  assert_eq(mixed[2], TBool(true))
  assert_eq(toml_error_code("a = [1, 2\n"), "UNCLOSED_ARRAY")
}

///|
test "toml: inline tables are one line in TOML 1.0" {
  let table = toml_of("a = {b = 1, c = \"x\"}\n")
  assert_eq(table.get_table("a").unwrap().get_int("b"), Some(1))
  assert_eq(table.get_table("a").unwrap().get_string("c"), Some("x"))
  assert_eq(toml_of("a = {}\n").get_table("a").unwrap().entries.length(), 0)
  // no trailing comma and no newline: both are TOML 1.1 relaxations
  assert_eq(toml_error_code("a = {b = 1,}\n"), "TRAILING_COMMA_IN_INLINE_TABLE")
  // A newline after the comma and a missing `}` are reported separately: the
  // first needs the table folded onto one line, the second needs a brace.
  assert_eq(
    toml_error_code("a = {b = 1,\n c = 2}\n"),
    "NEWLINE_IN_INLINE_TABLE",
  )
  assert_eq(toml_error_code("a = {\nb = 1}\n"), "NEWLINE_IN_INLINE_TABLE")
  assert_eq(toml_error_code("a = {b = 1\n"), "UNCLOSED_INLINE_TABLE")
}

///|
test "toml: tables, dotted keys and arrays of tables" {
  let table = toml_of(
    "[a]\nx = 1\n\n[a.b]\ny = 2\n\n[[c]]\nz = 1\n\n[[c]]\nz = 2\n\n[d]\ne.f = 3\n",
  )
  assert_eq(table.get_int("a.x"), Some(1))
  assert_eq(table.get_int("a.b.y"), Some(2))
  assert_eq(table.get_array("c").unwrap().length(), 2)
  assert_eq(table.get_int("d.e.f"), Some(3))
}

///|
test "toml: a table cannot be defined twice" {
  assert_eq(toml_error_code("[a]\n[a]\n"), "TABLE_ALREADY_DEFINED")
  assert_eq(toml_error_code("a = 1\n[a]\n"), "CANNOT_OVERWRITE_VALUE")
  assert_eq(toml_error_code("a = 1\na = 2\n"), "DUPLICATE_KEY")
  assert_eq(toml_error_code("[a]\nb = 1\n[a.b]\n"), "CANNOT_OVERWRITE_VALUE")
}

///|
test "toml: quoted keys and comments" {
  let table = toml_of(
    "\"a.b\" = 1\n'c d' = 2\n# a comment\n[e] # trailing\nf = 3\n",
  )
  // a key that literally contains a dot is reachable only by its own spelling
  assert_eq(table.entries[0].0, "a.b")
  assert_eq(table.entries[0].1, TInt(1))
  assert_eq(table.entries[1].0, "c d")
  assert_eq(table.get_int("e.f"), Some(3))
  assert_eq(toml_of("a = 1 # comment\n").get_int("a"), Some(1))
}

///|
test "toml: a statement ends at a newline" {
  assert_eq(toml_error_code("a = 1 b = 2\n"), "EXPECTED_NEWLINE_OR_EOF")
  assert_eq(toml_error_code("a = 1 = 2\n"), "EXPECTED_NEWLINE_OR_EOF")
  // CRLF is normalized before parsing
  assert_eq(toml_of("a = 1\r\nb = 2\r\n").get_int("b"), Some(2))
}

///|
test "toml: the round trip re-parses to an equal document" {
  let document = "[a]\nx = 1\ny = \"s\"\n\n[[b]]\nz = true\n\n[c.d]\nw = [1, 2]\n"
  let table = toml_of(document)
  let rendered = table.to_string()
  assert_eq(toml_of(rendered), table)
  // `a = 1` followed by `[a.b]` is not valid TOML at all: the value `a` cannot
  // later become a table, which is what the reference reader reports too.
  assert_eq(toml_error_code("a = 1\n[a.b]\nc = 2\n"), "CANNOT_OVERWRITE_VALUE")
  // In a table that holds both, plain values are written before sub-tables, so
  // the `[t.sub]` header cannot capture `x`.
  let nested = toml_of("[t]\nx = 1\n[t.sub]\ny = 2\n")
  assert_eq(nested.to_string(), "[t]\nx = 1\n\n[t.sub]\ny = 2\n")
  assert_eq(toml_of(nested.to_string()), nested)
}

///|
test "toml: the reference corpus agrees with the parser" {
  // fixtures/toml_corpus.mbt carries tomli's verdict for every case, so this is
  // the same comparison the differential harness makes, run as a unit test.
  let mut accepted = 0
  let mut rejected = 0
  for entry in @fixtures.toml_cases {
    let (name, document, expected_accept, _) = entry
    if @fixtures.toml_leniencies.contains(name) {
      // TOML 1.0 requires a rejection here even though the reference accepts
      assert_true(toml_rejected(document))
      continue
    }
    if expected_accept {
      ignore(toml_of(document))
      accepted = accepted + 1
    } else {
      assert_true(toml_rejected(document))
      rejected = rejected + 1
    }
  }
  // 83 cases: the reference reader accepts 50, of which 4 are its own
  // leniencies, and rejects 33. Adding a case file means updating these numbers
  // deliberately.
  assert_eq(accepted, 46)
  assert_eq(rejected, 33)
  assert_eq(@fixtures.toml_leniencies.length(), 4)
  assert_eq(@fixtures.toml_cases.length(), 83)
  assert_eq(
    accepted + rejected + @fixtures.toml_leniencies.length(),
    @fixtures.toml_cases.length(),
  )
}
