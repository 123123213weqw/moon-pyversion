///|
/// A stable, structured error for version and specifier parsing.
pub(all) suberror VersionError {
  InvalidVersion(String, Int)
  InvalidSpecifier(String, Int)
} derive(Eq, @debug.Debug)

///|
pub fn VersionError::diagnostic(self : VersionError) -> String {
  match self {
    InvalidVersion(code, pos) => "\{code} at \{pos}"
    InvalidSpecifier(code, pos) => "\{code} at \{pos}"
  }
}

///|
pub impl Show for VersionError with fn to_string(self) {
  VersionError::diagnostic(self)
}

///|
/// One normalized local-version segment. Numeric segments are compared as
/// integers; textual segments are compared case-insensitively.
pub(all) struct LocalPart {
  text : String
  numeric : Bool
} derive(Eq, @debug.Debug)

///|
/// A parsed PEP 440 version. `raw` keeps the caller's original string, while
/// `to_string` returns the normalized public form.
pub(all) struct Version {
  raw : String
  epoch : @bigint.BigInt
  release : Array[@bigint.BigInt]
  has_pre : Bool
  pre_kind : Int
  pre_num : @bigint.BigInt
  has_post : Bool
  post_num : @bigint.BigInt
  has_dev : Bool
  dev_num : @bigint.BigInt
  local_segments : Array[LocalPart]
} derive(@debug.Debug)

///|
priv struct Cursor {
  source : String
  mut pos : Int
}

///|
fn is_digit(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
fn is_ascii_letter(c : Int) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

///|
fn is_alnum(c : Int) -> Bool {
  is_digit(c) || is_ascii_letter(c)
}

///|
fn is_separator(c : Int) -> Bool {
  c == 46 || c == 45 || c == 95
}

///|
fn Cursor::peek(self : Cursor) -> Int {
  if self.pos >= self.source.length() {
    -1
  } else {
    self.source[self.pos].to_int()
  }
}

///|
fn Cursor::peek_at(self : Cursor, offset : Int) -> Int {
  let idx = self.pos + offset
  if idx >= self.source.length() {
    -1
  } else {
    self.source[idx].to_int()
  }
}

///|
fn Cursor::advance(self : Cursor) -> Unit {
  self.pos += 1
}

///|
fn Cursor::parse_digits(self : Cursor) -> @bigint.BigInt raise VersionError {
  let start = self.pos
  while is_digit(self.peek()) {
    self.advance()
  }
  if self.pos == start {
    raise VersionError::InvalidVersion("EXPECTED_DIGITS", start)
  }
  @bigint.BigInt::from_string(self.source[start:self.pos].to_owned())
}

///|
fn Cursor::match_label(self : Cursor, label : String) -> Bool {
  if self.pos + label.length() > self.source.length() {
    false
  } else {
    self.source[self.pos:self.pos + label.length()].to_owned().to_lower() ==
    label
  }
}

///|
/// Returns `(kind, length)` where kind is 1..3 for a/b/rc pre-releases,
/// 4 for post-releases, and 5 for dev-releases.
fn Cursor::suffix_info(self : Cursor) -> (Int, Int) {
  if self.match_label("alpha") {
    (1, 5)
  } else if self.match_label("beta") {
    (2, 4)
  } else if self.match_label("preview") {
    (3, 7)
  } else if self.match_label("pre") {
    (3, 3)
  } else if self.match_label("post") {
    (4, 4)
  } else if self.match_label("rev") {
    (4, 3)
  } else if self.match_label("rc") {
    (3, 2)
  } else if self.match_label("dev") {
    (5, 3)
  } else if self.match_label("a") {
    (1, 1)
  } else if self.match_label("b") {
    (2, 1)
  } else if self.match_label("c") {
    (3, 1)
  } else if self.match_label("r") {
    (4, 1)
  } else {
    (0, 0)
  }
}

///|
fn Cursor::consume_separator(self : Cursor) -> Bool {
  if is_separator(self.peek()) {
    self.advance()
    true
  } else {
    false
  }
}

///|
fn all_digits(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    if !is_digit(text[i].to_int()) {
      return false
    }
  }
  true
}

///|
fn normalize_numeric_local(text : String) -> String {
  @bigint.BigInt::from_string(text).to_string()
}

///|
fn parse_version(input : String) -> Version raise VersionError {
  let source = input.trim().to_owned()
  if source.is_empty() {
    raise VersionError::InvalidVersion("EMPTY_VERSION", 0)
  }
  let cursor = { source, pos: 0, }

  if cursor.peek() == 118 || cursor.peek() == 86 {
    cursor.advance()
    if !is_digit(cursor.peek()) {
      raise VersionError::InvalidVersion("EXPECTED_DIGIT_AFTER_V", cursor.pos)
    }
  }

  let mut epoch = @bigint.BigInt::from_int(0)
  let release : Array[@bigint.BigInt] = []
  let first = cursor.parse_digits()
  if cursor.peek() == 33 {
    cursor.advance()
    epoch = first
    release.push(cursor.parse_digits())
  } else {
    release.push(first)
  }

  while cursor.peek() == 46 && is_digit(cursor.peek_at(1)) {
    cursor.advance()
    release.push(cursor.parse_digits())
  }

  let mut has_pre = false
  let mut pre_kind = 0
  let mut pre_num = @bigint.BigInt::from_int(0)
  let mut has_post = false
  let mut post_num = @bigint.BigInt::from_int(0)
  let mut has_dev = false
  let mut dev_num = @bigint.BigInt::from_int(0)
  let mut state = 0

  while cursor.peek() != -1 && cursor.peek() != 43 {
    if state == 0 {
      if cursor.peek() == 45 && is_digit(cursor.peek_at(1)) {
        cursor.advance()
        post_num = cursor.parse_digits()
        has_post = true
        state = 2
      } else {
        ignore(cursor.consume_separator())
        let (kind, len) = cursor.suffix_info()
        if kind == 0 {
          raise VersionError::InvalidVersion("EXPECTED_SUFFIX", cursor.pos)
        }
        cursor.pos += len
        ignore(cursor.consume_separator())
        let num = if is_digit(cursor.peek()) {
          cursor.parse_digits()
        } else {
          @bigint.BigInt::from_int(0)
        }
        if kind <= 3 {
          if has_pre {
            raise VersionError::InvalidVersion(
              "DUPLICATE_PRE_RELEASE",
              cursor.pos,
            )
          }
          has_pre = true
          pre_kind = kind
          pre_num = num
          state = 1
        } else if kind == 4 {
          if has_post {
            raise VersionError::InvalidVersion(
              "DUPLICATE_POST_RELEASE",
              cursor.pos,
            )
          }
          has_post = true
          post_num = num
          state = 2
        } else {
          if has_dev {
            raise VersionError::InvalidVersion(
              "DUPLICATE_DEV_RELEASE",
              cursor.pos,
            )
          }
          has_dev = true
          dev_num = num
          state = 3
        }
      }
    } else {
      if !cursor.consume_separator() {
        raise VersionError::InvalidVersion(
          "EXPECTED_SUFFIX_SEPARATOR",
          cursor.pos,
        )
      }
      let (kind, len) = cursor.suffix_info()
      if kind == 0 {
        raise VersionError::InvalidVersion("EXPECTED_SUFFIX", cursor.pos)
      }
      cursor.pos += len
      ignore(cursor.consume_separator())
      let num = if is_digit(cursor.peek()) {
        cursor.parse_digits()
      } else {
        @bigint.BigInt::from_int(0)
      }
      if kind <= 3 {
        raise VersionError::InvalidVersion("INVALID_SUFFIX_ORDER", cursor.pos)
      } else if kind == 4 {
        if has_post || state >= 2 {
          raise VersionError::InvalidVersion("INVALID_SUFFIX_ORDER", cursor.pos)
        }
        has_post = true
        post_num = num
        state = 2
      } else {
        if has_dev || state >= 3 {
          raise VersionError::InvalidVersion("INVALID_SUFFIX_ORDER", cursor.pos)
        }
        has_dev = true
        dev_num = num
        state = 3
      }
    }
  }

  let local_segments : Array[LocalPart] = []
  if cursor.peek() == 43 {
    cursor.advance()
    if cursor.peek() == -1 {
      raise VersionError::InvalidVersion("EMPTY_LOCAL_VERSION", cursor.pos)
    }
    while cursor.peek() != -1 {
      let start = cursor.pos
      while is_alnum(cursor.peek()) {
        cursor.advance()
      }
      if cursor.pos == start {
        raise VersionError::InvalidVersion("INVALID_LOCAL_SEGMENT", cursor.pos)
      }
      let raw_segment = cursor.source[start:cursor.pos].to_owned().to_lower()
      let numeric = all_digits(raw_segment)
      let text = if numeric {
        normalize_numeric_local(raw_segment)
      } else {
        raw_segment
      }
      local_segments.push({ text, numeric, })
      if is_separator(cursor.peek()) {
        cursor.advance()
        if cursor.peek() == -1 || !is_alnum(cursor.peek()) {
          raise VersionError::InvalidVersion(
            "INVALID_LOCAL_SEGMENT",
            cursor.pos,
          )
        }
      } else {
        break
      }
    }
  }

  if cursor.peek() != -1 {
    raise VersionError::InvalidVersion("INVALID_VERSION_END", cursor.pos)
  }

  {
    raw: input,
    epoch,
    release,
    has_pre,
    pre_kind,
    pre_num,
    has_post,
    post_num,
    has_dev,
    dev_num,
    local_segments,
  }
}

///|
pub fn Version::parse(input : String) -> Version raise VersionError {
  parse_version(input)
}

///|
fn format_version(v : Version) -> String {
  let b = StringBuilder()
  if v.epoch.compare(@bigint.BigInt::from_int(0)) > 0 {
    b.write_string(v.epoch.to_string())
    b.write_string("!")
  }
  for i = 0; i < v.release.length(); i = i + 1 {
    if i > 0 {
      b.write_string(".")
    }
    b.write_string(v.release[i].to_string())
  }
  if v.has_pre {
    if v.pre_kind == 1 {
      b.write_string("a")
    } else if v.pre_kind == 2 {
      b.write_string("b")
    } else {
      b.write_string("rc")
    }
    b.write_string(v.pre_num.to_string())
  }
  if v.has_post {
    b.write_string(".post")
    b.write_string(v.post_num.to_string())
  }
  if v.has_dev {
    b.write_string(".dev")
    b.write_string(v.dev_num.to_string())
  }
  if v.local_segments.length() > 0 {
    b.write_string("+")
    for i = 0; i < v.local_segments.length(); i = i + 1 {
      if i > 0 {
        b.write_string(".")
      }
      b.write_string(v.local_segments[i].text)
    }
  }
  b.to_string()
}

///|
pub fn Version::to_string(self : Version) -> String {
  format_version(self)
}

///|
pub impl Show for Version with fn to_string(self) {
  format_version(self)
}

///|
pub fn Version::normalize(input : String) -> String raise VersionError {
  let v = parse_version(input)
  format_version(v)
}

///|
fn compare_bigint_arrays(
  left : Array[@bigint.BigInt],
  right : Array[@bigint.BigInt],
) -> Int {
  let len = Int::max(left.length(), right.length())
  for i = 0; i < len; i = i + 1 {
    let l = if i < left.length() {
      left[i]
    } else {
      @bigint.BigInt::from_int(0)
    }
    let r = if i < right.length() {
      right[i]
    } else {
      @bigint.BigInt::from_int(0)
    }
    let c = l.compare(r)
    if c != 0 {
      return c
    }
  }
  0
}

///|
fn compare_numeric_local(left : String, right : String) -> Int {
  if left.length() != right.length() {
    left.length().compare(right.length())
  } else {
    left.compare(right)
  }
}

///|
fn compare_local(left : Array[LocalPart], right : Array[LocalPart]) -> Int {
  let len = Int::min(left.length(), right.length())
  for i = 0; i < len; i = i + 1 {
    let l = left[i]
    let r = right[i]
    let c = if l.numeric && r.numeric {
      compare_numeric_local(l.text, r.text)
    } else if l.numeric != r.numeric {
      if l.numeric {
        1
      } else {
        -1
      }
    } else {
      l.text.compare(r.text)
    }
    if c != 0 {
      return c
    }
  }
  left.length().compare(right.length())
}

///|
pub fn Version::compare(left : Version, right : Version) -> Int {
  let c_epoch = left.epoch.compare(right.epoch)
  if c_epoch != 0 {
    return c_epoch
  }
  let c_release = compare_bigint_arrays(left.release, right.release)
  if c_release != 0 {
    return c_release
  }
  if left.has_dev != right.has_dev {
    return if left.has_dev { -1 } else { 1 }
  }
  if left.has_dev {
    let c_dev = left.dev_num.compare(right.dev_num)
    if c_dev != 0 {
      return c_dev
    }
  }
  if left.has_pre != right.has_pre {
    return if left.has_pre { -1 } else { 1 }
  }
  if left.has_pre {
    let c_kind = left.pre_kind.compare(right.pre_kind)
    if c_kind != 0 {
      return c_kind
    }
    let c_pre = left.pre_num.compare(right.pre_num)
    if c_pre != 0 {
      return c_pre
    }
  }
  if left.has_post != right.has_post {
    return if left.has_post { 1 } else { -1 }
  }
  if left.has_post {
    let c_post = left.post_num.compare(right.post_num)
    if c_post != 0 {
      return c_post
    }
  }
  compare_local(left.local_segments, right.local_segments)
}

///|
pub impl Eq for Version with fn equal(self, other) {
  Version::compare(self, other) == 0
}

///|
pub impl Compare for Version with fn compare(self, other) {
  Version::compare(self, other)
}
