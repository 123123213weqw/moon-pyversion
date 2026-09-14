///|
/// PEP 639 license expressions and license file paths, aligned with PyPA
/// `packaging` 26.3. An *expression* is rewritten; a license *file path* is only
/// validated and never normalized.
///
/// Expression rules, all of them observable: `(` and `)` are padded with spaces
/// so a whitespace split suffices as a tokenizer; identifiers match
/// case-insensitively and operators are re-emitted in upper case; only the
/// `LicenseRef-` *prefix* is rewritten, so the body keeps the caller's case and
/// the last spelling of a duplicated reference wins, making `LicenseRef-a or
/// licenseref-A` yield `LicenseRef-A` twice; a `LicenseRef` body must match
/// `[A-Za-z0-9.-]+` and may not take a `+`; one trailing `+` is stripped and
/// re-appended, so `mit++` reports the unknown license `mit+`; `WITH` must follow
/// a license and be followed by an exception identifier; identifiers are whole
/// tokens, so `MIT(mit)` is invalid; and the syntax check is `packaging`'s own,
/// see `check_expression_syntax`.
///
/// The only data is the SPDX identifier list from `packaging.licenses._spdx` (699
/// licenses, 79 exceptions); each entry's dict key there is exactly the ASCII
/// lowercase of its canonical spelling, so only the spelling is stored.
///
/// Boundary: case folding is ASCII, while `packaging` folds with Unicode rules, so
/// e.g. U+0130 can make the two disagree. Tokenization does implement Python's
/// whole `str.split()` whitespace set.

///|
/// Canonical spelling of every SPDX license identifier in
/// `packaging.licenses._spdx.LICENSES`, space separated.
let spdx_license_ids : String = "0BSD 3D-Slicer-1.0 AAL Abstyles AdaCore-doc Adobe-2006 Adobe-Display-PostScript Adobe-Glyph Adobe-Utopia ADSL AFL-1.1 AFL-1.2 AFL-2.0 AFL-2.1 AFL-3.0 Afmparse AGPL-1.0 AGPL-1.0-only AGPL-1.0-or-later AGPL-3.0 AGPL-3.0-only AGPL-3.0-or-later Aladdin AMD-newlib AMDPLPA AML AML-glslang AMPAS ANTLR-PD ANTLR-PD-fallback any-OSI any-OSI-perl-modules Apache-1.0 Apache-1.1 Apache-2.0 APAFML APL-1.0 App-s2p APSL-1.0 APSL-1.1 APSL-1.2 APSL-2.0 Arphic-1999 Artistic-1.0 Artistic-1.0-cl8 Artistic-1.0-Perl Artistic-2.0 Artistic-dist Aspell-RU ASWF-Digital-Assets-1.0 ASWF-Digital-Assets-1.1 Baekmuk Bahyph Barr bcrypt-Solar-Designer Beerware Bitstream-Charter Bitstream-Vera BitTorrent-1.0 BitTorrent-1.1 blessing BlueOak-1.0.0 Boehm-GC Boehm-GC-without-fee Borceux Brian-Gladman-2-Clause Brian-Gladman-3-Clause BSD-1-Clause BSD-2-Clause BSD-2-Clause-Darwin BSD-2-Clause-first-lines BSD-2-Clause-FreeBSD BSD-2-Clause-NetBSD BSD-2-Clause-Patent BSD-2-Clause-pkgconf-disclaimer BSD-2-Clause-Views BSD-3-Clause BSD-3-Clause-acpica BSD-3-Clause-Attribution " +
  "BSD-3-Clause-Clear BSD-3-Clause-flex BSD-3-Clause-HP BSD-3-Clause-LBNL BSD-3-Clause-Modification BSD-3-Clause-No-Military-License BSD-3-Clause-No-Nuclear-License BSD-3-Clause-No-Nuclear-License-2014 BSD-3-Clause-No-Nuclear-Warranty BSD-3-Clause-Open-MPI BSD-3-Clause-Sun BSD-4-Clause BSD-4-Clause-Shortened BSD-4-Clause-UC BSD-4.3RENO BSD-4.3TAHOE BSD-Advertising-Acknowledgement BSD-Attribution-HPND-disclaimer BSD-Inferno-Nettverk BSD-Protection BSD-Source-beginning-file BSD-Source-Code BSD-Systemics BSD-Systemics-W3Works BSL-1.0 BUSL-1.1 bzip2-1.0.5 bzip2-1.0.6 C-UDA-1.0 CAL-1.0 CAL-1.0-Combined-Work-Exception Caldera Caldera-no-preamble Catharon CATOSL-1.1 CC-BY-1.0 CC-BY-2.0 CC-BY-2.5 CC-BY-2.5-AU CC-BY-3.0 CC-BY-3.0-AT CC-BY-3.0-AU CC-BY-3.0-DE CC-BY-3.0-IGO CC-BY-3.0-NL CC-BY-3.0-US CC-BY-4.0 CC-BY-NC-1.0 CC-BY-NC-2.0 CC-BY-NC-2.5 CC-BY-NC-3.0 CC-BY-NC-3.0-DE CC-BY-NC-4.0 CC-BY-NC-ND-1.0 CC-BY-NC-ND-2.0 CC-BY-NC-ND-2.5 CC-BY-NC-ND-3.0 CC-BY-NC-ND-3.0-DE CC-BY-NC-ND-3.0-IGO CC-BY-NC-ND-4.0 CC-BY-NC-SA-1.0 CC-BY-NC-SA-2.0 " +
  "CC-BY-NC-SA-2.0-DE CC-BY-NC-SA-2.0-FR CC-BY-NC-SA-2.0-UK CC-BY-NC-SA-2.5 CC-BY-NC-SA-3.0 CC-BY-NC-SA-3.0-DE CC-BY-NC-SA-3.0-IGO CC-BY-NC-SA-4.0 CC-BY-ND-1.0 CC-BY-ND-2.0 CC-BY-ND-2.5 CC-BY-ND-3.0 CC-BY-ND-3.0-DE CC-BY-ND-4.0 CC-BY-SA-1.0 CC-BY-SA-2.0 CC-BY-SA-2.0-UK CC-BY-SA-2.1-JP CC-BY-SA-2.5 CC-BY-SA-3.0 CC-BY-SA-3.0-AT CC-BY-SA-3.0-DE CC-BY-SA-3.0-IGO CC-BY-SA-4.0 CC-PDDC CC-PDM-1.0 CC-SA-1.0 CC0-1.0 CDDL-1.0 CDDL-1.1 CDL-1.0 CDLA-Permissive-1.0 CDLA-Permissive-2.0 CDLA-Sharing-1.0 CECILL-1.0 CECILL-1.1 CECILL-2.0 CECILL-2.1 CECILL-B CECILL-C CERN-OHL-1.1 CERN-OHL-1.2 CERN-OHL-P-2.0 CERN-OHL-S-2.0 CERN-OHL-W-2.0 CFITSIO check-cvs checkmk ClArtistic Clips CMU-Mach CMU-Mach-nodoc CNRI-Jython CNRI-Python CNRI-Python-GPL-Compatible COIL-1.0 Community-Spec-1.0 Condor-1.1 copyleft-next-0.3.0 copyleft-next-0.3.1 Cornell-Lossless-JPEG CPAL-1.0 CPL-1.0 CPOL-1.02 Cronyx Crossword CryptoSwift CrystalStacker CUA-OPL-1.0 Cube curl cve-tou D-FSL-1.0 DEC-3-Clause diffmark DL-DE-BY-2.0 DL-DE-ZERO-2.0 DOC DocBook-DTD DocBook-Schema " +
  "DocBook-Stylesheet DocBook-XML Dotseqn DRL-1.0 DRL-1.1 DSDP dtoa dvipdfm ECL-1.0 ECL-2.0 eCos-2.0 EFL-1.0 EFL-2.0 eGenix Elastic-2.0 Entessa EPICS EPL-1.0 EPL-2.0 ErlPL-1.1 etalab-2.0 EUDatagrid EUPL-1.0 EUPL-1.1 EUPL-1.2 Eurosym Fair FBM FDK-AAC Ferguson-Twofish Frameworx-1.0 FreeBSD-DOC FreeImage FSFAP FSFAP-no-warranty-disclaimer FSFUL FSFULLR FSFULLRSD FSFULLRWD FSL-1.1-ALv2 FSL-1.1-MIT FTL Furuseth fwlw Game-Programming-Gems GCR-docs GD generic-xts GFDL-1.1 GFDL-1.1-invariants-only GFDL-1.1-invariants-or-later GFDL-1.1-no-invariants-only GFDL-1.1-no-invariants-or-later GFDL-1.1-only GFDL-1.1-or-later GFDL-1.2 GFDL-1.2-invariants-only GFDL-1.2-invariants-or-later GFDL-1.2-no-invariants-only GFDL-1.2-no-invariants-or-later GFDL-1.2-only GFDL-1.2-or-later GFDL-1.3 GFDL-1.3-invariants-only GFDL-1.3-invariants-or-later GFDL-1.3-no-invariants-only GFDL-1.3-no-invariants-or-later GFDL-1.3-only GFDL-1.3-or-later Giftware GL2PS Glide Glulxe GLWTPL gnuplot GPL-1.0 GPL-1.0+ GPL-1.0-only GPL-1.0-or-later GPL-2.0 GPL-2.0+ GPL-2.0-only " +
  "GPL-2.0-or-later GPL-2.0-with-autoconf-exception GPL-2.0-with-bison-exception GPL-2.0-with-classpath-exception GPL-2.0-with-font-exception GPL-2.0-with-GCC-exception GPL-3.0 GPL-3.0+ GPL-3.0-only GPL-3.0-or-later GPL-3.0-with-autoconf-exception GPL-3.0-with-GCC-exception Graphics-Gems gSOAP-1.3b gtkbook Gutmann HaskellReport HDF5 hdparm HIDAPI Hippocratic-2.1 HP-1986 HP-1989 HPND HPND-DEC HPND-doc HPND-doc-sell HPND-export-US HPND-export-US-acknowledgement HPND-export-US-modify HPND-export2-US HPND-Fenneberg-Livingston HPND-INRIA-IMAG HPND-Intel HPND-Kevlin-Henney HPND-Markus-Kuhn HPND-merchantability-variant HPND-MIT-disclaimer HPND-Netrek HPND-Pbmplus HPND-sell-MIT-disclaimer-xserver HPND-sell-regexpr HPND-sell-variant HPND-sell-variant-MIT-disclaimer HPND-sell-variant-MIT-disclaimer-rev HPND-UC HPND-UC-export-US HTMLTIDY IBM-pibs ICU IEC-Code-Components-EULA IJG IJG-short ImageMagick iMatix Imlib2 Info-ZIP Inner-Net-2.0 InnoSetup Intel Intel-ACPI Interbase-1.0 IPA IPL-1.0 ISC ISC-Veillard Jam JasPer-2.0 jove JPL-image JPNIC JSON " +
  "Kastrup Kazlib Knuth-CTAN LAL-1.2 LAL-1.3 Latex2e Latex2e-translated-notice Leptonica LGPL-2.0 LGPL-2.0+ LGPL-2.0-only LGPL-2.0-or-later LGPL-2.1 LGPL-2.1+ LGPL-2.1-only LGPL-2.1-or-later LGPL-3.0 LGPL-3.0+ LGPL-3.0-only LGPL-3.0-or-later LGPLLR Libpng libpng-1.6.35 libpng-2.0 libselinux-1.0 libtiff libutil-David-Nugent LiLiQ-P-1.1 LiLiQ-R-1.1 LiLiQ-Rplus-1.1 Linux-man-pages-1-para Linux-man-pages-copyleft Linux-man-pages-copyleft-2-para Linux-man-pages-copyleft-var Linux-OpenIB LOOP LPD-document LPL-1.0 LPL-1.02 LPPL-1.0 LPPL-1.1 LPPL-1.2 LPPL-1.3a LPPL-1.3c lsof Lucida-Bitmap-Fonts LZMA-SDK-9.11-to-9.20 LZMA-SDK-9.22 Mackerras-3-Clause Mackerras-3-Clause-acknowledgment magaz mailprio MakeIndex man2html Martin-Birgmeier McPhee-slideshow metamail Minpack MIPS MirOS MIT MIT-0 MIT-advertising MIT-Click MIT-CMU MIT-enna MIT-feh MIT-Festival MIT-Khronos-old MIT-Modern-Variant MIT-open-group MIT-testregex MIT-Wu MITNFA MMIXware Motosoto MPEG-SSG mpi-permissive mpich2 MPL-1.0 MPL-1.1 MPL-2.0 MPL-2.0-no-copyleft-exception mplus MS-LPL MS-PL " +
  "MS-RL MTLL MulanPSL-1.0 MulanPSL-2.0 Multics Mup NAIST-2003 NASA-1.3 Naumen NBPL-1.0 NCBI-PD NCGL-UK-2.0 NCL NCSA Net-SNMP NetCDF Newsletr NGPL ngrep NICTA-1.0 NIST-PD NIST-PD-fallback NIST-Software NLOD-1.0 NLOD-2.0 NLPL Nokia NOSL Noweb NPL-1.0 NPL-1.1 NPOSL-3.0 NRL NTIA-PD NTP NTP-0 Nunit O-UDA-1.0 OAR OCCT-PL OCLC-2.0 ODbL-1.0 ODC-By-1.0 OFFIS OFL-1.0 OFL-1.0-no-RFN OFL-1.0-RFN OFL-1.1 OFL-1.1-no-RFN OFL-1.1-RFN OGC-1.0 OGDL-Taiwan-1.0 OGL-Canada-2.0 OGL-UK-1.0 OGL-UK-2.0 OGL-UK-3.0 OGTSL OLDAP-1.1 OLDAP-1.2 OLDAP-1.3 OLDAP-1.4 OLDAP-2.0 OLDAP-2.0.1 OLDAP-2.1 OLDAP-2.2 OLDAP-2.2.1 OLDAP-2.2.2 OLDAP-2.3 OLDAP-2.4 OLDAP-2.5 OLDAP-2.6 OLDAP-2.7 OLDAP-2.8 OLFL-1.3 OML OpenPBS-2.3 OpenSSL OpenSSL-standalone OpenVision OPL-1.0 OPL-UK-3.0 OPUBL-1.0 OSET-PL-2.1 OSL-1.0 OSL-1.1 OSL-2.0 OSL-2.1 OSL-3.0 PADL Parity-6.0.0 Parity-7.0.0 PDDL-1.0 PHP-3.0 PHP-3.01 Pixar pkgconf Plexus pnmstitch PolyForm-Noncommercial-1.0.0 PolyForm-Small-Business-1.0.0 PostgreSQL PPL PSF-2.0 psfrag psutils Python-2.0 Python-2.0.1 python-ldap Qhull QPL-1.0 " +
  "QPL-1.0-INRIA-2004 radvd Rdisc RHeCos-1.1 RPL-1.1 RPL-1.5 RPSL-1.0 RSA-MD RSCPL Ruby Ruby-pty SAX-PD SAX-PD-2.0 Saxpath SCEA SchemeReport Sendmail Sendmail-8.23 Sendmail-Open-Source-1.1 SGI-B-1.0 SGI-B-1.1 SGI-B-2.0 SGI-OpenGL SGP4 SHL-0.5 SHL-0.51 SimPL-2.0 SISSL SISSL-1.2 SL Sleepycat SMAIL-GPL SMLNJ SMPPL SNIA snprintf SOFA softSurfer Soundex Spencer-86 Spencer-94 Spencer-99 SPL-1.0 ssh-keyscan SSH-OpenSSH SSH-short SSLeay-standalone SSPL-1.0 StandardML-NJ SugarCRM-1.1.3 SUL-1.0 Sun-PPP Sun-PPP-2000 SunPro SWL swrule Symlinks TAPR-OHL-1.0 TCL TCP-wrappers TermReadKey TGPPL-1.0 ThirdEye threeparttable TMate TORQUE-1.1 TOSL TPDL TPL-1.0 TrustedQSL TTWL TTYP0 TU-Berlin-1.0 TU-Berlin-2.0 Ubuntu-font-1.0 UCAR UCL-1.0 ulem UMich-Merit Unicode-3.0 Unicode-DFS-2015 Unicode-DFS-2016 Unicode-TOU UnixCrypt Unlicense Unlicense-libtelnet Unlicense-libwhirlpool UPL-1.0 URT-RLE Vim VOSTROM VSL-1.0 W3C W3C-19980720 W3C-20150513 w3m Watcom-1.0 Widget-Workshop Wsuipa WTFPL wwl wxWindows X11 X11-distribute-modifications-variant X11-swapped " +
  "Xdebug-1.03 Xerox Xfig XFree86-1.1 xinetd xkeyboard-config-Zinoviev xlock Xnet xpp XSkat xzoom YPL-1.0 YPL-1.1 Zed Zeeff Zend-2.0 Zimbra-1.3 Zimbra-1.4 Zlib zlib-acknowledgement ZPL-1.1 ZPL-2.0 ZPL-2.1"

///|
/// Canonical spelling of every SPDX exception identifier in
/// `packaging.licenses._spdx.EXCEPTIONS`, space separated.
let spdx_exception_ids : String = "389-exception Asterisk-exception Asterisk-linking-protocols-exception Autoconf-exception-2.0 Autoconf-exception-3.0 Autoconf-exception-generic Autoconf-exception-generic-3.0 Autoconf-exception-macro Bison-exception-1.24 Bison-exception-2.2 Bootloader-exception CGAL-linking-exception Classpath-exception-2.0 CLISP-exception-2.0 cryptsetup-OpenSSL-exception Digia-Qt-LGPL-exception-1.1 " +
  "DigiRule-FOSS-exception eCos-exception-2.0 erlang-otp-linking-exception Fawkes-Runtime-exception FLTK-exception fmt-exception Font-exception-2.0 freertos-exception-2.0 GCC-exception-2.0 GCC-exception-2.0-note GCC-exception-3.1 Gmsh-exception GNAT-exception GNOME-examples-exception GNU-compiler-exception gnu-javamail-exception GPL-3.0-389-ds-base-exception GPL-3.0-interface-exception " +
  "GPL-3.0-linking-exception GPL-3.0-linking-source-exception GPL-CC-1.0 GStreamer-exception-2005 GStreamer-exception-2008 harbour-exception i2p-gpl-java-exception Independent-modules-exception KiCad-libraries-exception LGPL-3.0-linking-exception libpri-OpenH323-exception Libtool-exception Linux-syscall-note LLGPL LLVM-exception LZMA-exception mif-exception mxml-exception Nokia-Qt-exception-1.1 " +
  "OCaml-LGPL-linking-exception OCCT-exception-1.0 OpenJDK-assembly-exception-1.0 openvpn-openssl-exception PCRE2-exception polyparse-exception PS-or-PDF-font-exception-20170817 QPL-1.0-INRIA-2004-exception Qt-GPL-exception-1.0 Qt-LGPL-exception-1.1 Qwt-exception-1.0 romic-exception RRDtool-FLOSS-exception-2.0 SANE-exception SHL-2.0 SHL-2.1 stunnel-exception SWI-exception Swift-exception " +
  "Texinfo-exception u-boot-exception-2.0 UBDL-exception Universal-FOSS-exception-1.0 vsftpd-openssl-exception WxWindows-exception-3.1 x11vnc-openssl-exception"

///|
/// Build a `(lowercase key, canonical spelling)` table from a packed list.
fn id_table(packed : String) -> Array[(String, String)] {
  let table : Array[(String, String)] = []
  for chunk in packed.split(" ") {
    if chunk.length() > 0 {
      let id = chunk.to_owned()
      table.push((id.to_lower(), id))
    }
  }
  table
}

///|
/// SPDX license index, keyed the way `packaging`'s dict is keyed.
let spdx_licenses : Array[(String, String)] = id_table(spdx_license_ids)

///|
/// SPDX exception index, used for the identifier that follows `WITH`.
let spdx_exceptions : Array[(String, String)] = id_table(spdx_exception_ids)

///|
/// Canonical spelling for a lowercase key, or `None` when it is unknown.
fn lookup_id(table : Array[(String, String)], key : String) -> String? {
  for entry in table {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Set `key`, replacing an existing entry; `packaging` builds the same map with
/// a dict comprehension, so the last occurrence of a duplicate wins.
fn put_entry(t : Array[(String, String)], key : String, value : String) -> Unit {
  for index = 0; index < t.length(); index = index + 1 {
    if t[index].0 == key {
      t[index] = (key, value)
      return
    }
  }
  t.push((key, value))
}

///|
/// Whitespace as Python's zero-argument `str.split()` sees it: ASCII whitespace,
/// U+001C..U+001F, and the Unicode `White_Space` code points. Not
/// `Char::is_ascii_whitespace()`, which excludes `\v` where Python includes it.
fn is_split_space(c : Char) -> Bool {
  let code = c.to_int()
  if code <= 0x7F {
    return code == 0x20 ||
      (code >= 0x09 && code <= 0x0D) ||
      (code >= 0x1C && code <= 0x1F)
  }
  code == 0x85 ||
  code == 0xA0 ||
  code == 0x1680 ||
  (code >= 0x2000 && code <= 0x200A) ||
  code == 0x2028 ||
  code == 0x2029 ||
  code == 0x202F ||
  code == 0x205F ||
  code == 0x3000
}

///|
/// Split on Python whitespace; `String::split` cannot express that set.
fn split_tokens(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut current : Array[Char] = []
  for c in text {
    if is_split_space(c) {
      if current.length() > 0 {
        out.push(String::from_array(current))
        current = []
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    out.push(String::from_array(current))
  }
  out
}

///|
/// Surround every parenthesis with spaces, so the whitespace split tokenizes.
fn pad_parentheses(raw : String) -> String {
  let out : Array[Char] = []
  for c in raw {
    if c == '(' || c == ')' {
      out.push(' ')
      out.push(c)
      out.push(' ')
    } else {
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// True for the five operator spellings. Anything else is an operand.
fn is_operator(token : String) -> Bool {
  token == "or" ||
  token == "and" ||
  token == "with" ||
  token == "(" ||
  token == ")"
}

///|
/// `packaging`'s syntax check, in two stages.
///
/// Stage one is the ad-hoc token rules applied while its throwaway Python
/// expression is built: `(` is rejected when the previous token was an operand or
/// `)`, and `)` is rejected when the previous token was `(`. Those rules make
/// `()`, `MIT(mit)` and `(MIT)(MIT)` invalid, the last because `(False)(False)`
/// would otherwise compile as a *call*. `with` counts as `or`, since that is what
/// it is compiled to.
///
/// Stage two is what `compile()` then accepts: operands can never end up adjacent,
/// so the grammar collapses to `operand ((and|or) operand)*` with balanced
/// parentheses. CPython gives up at 201 levels of nesting, so 200 is the deepest
/// accepted expression. Precedence is irrelevant, because only acceptance of the
/// token sequence is checked.
fn check_expression_syntax(tokens : Array[String]) -> Unit raise VersionError {
  let mut prev = ""
  let mut have_operand = false
  let mut depth = 0
  for index = 0; index < tokens.length(); index = index + 1 {
    let token = tokens[index]
    if token == "(" &&
      prev != "" &&
      prev != "or" &&
      prev != "and" &&
      prev != "(" {
      raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
    } else if token == ")" && prev == "(" {
      raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
    } else if token == "(" {
      have_operand = false
      depth = depth + 1
      if depth > 200 {
        raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
      }
    } else if token == ")" {
      if !have_operand || depth == 0 {
        raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
      }
      have_operand = true
      depth = depth - 1
    } else if is_operator(token) {
      if !have_operand {
        raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
      }
      have_operand = false
    } else {
      if have_operand {
        raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
      }
      have_operand = true
    }
    prev = if token == "with" { "or" } else { token }
  }
  if depth != 0 || !have_operand {
    raise VersionError::InvalidLicense("INVALID_EXPRESSION", 0)
  }
}

///|
/// True when `text` is a legal `LicenseRef` body, tested with `^[A-Za-z0-9.-]+$`.
/// `_` and `+` are not in that set, so `LicenseRef-a_b` is invalid too.
fn is_license_ref_id(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for c in text {
    if !(c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '.' || c == '-') {
      return false
    }
  }
  true
}

///|
/// Normalize a PEP 639 `License-Expression`, mirroring
/// `packaging.licenses.canonicalize_license_expression`.
///
/// `VersionError::InvalidLicense` carries a stable code and the 0-based index of
/// the offending token: `INVALID_EXPRESSION` for empty input or a syntax error
/// (`packaging` uses one message for both), `UNKNOWN_LICENSE` for an unknown
/// operand, `UNKNOWN_LICENSE_EXCEPTION` for the identifier after `WITH`, and
/// `INVALID_LICENSE_REF` for a bad `LicenseRef`.
///
/// ```moonbit nocheck
/// canonicalize_license_expression("mit")                                // "MIT"
/// canonicalize_license_expression("mit and (apache-2.0 or bsd-2-clause)")
///   // "MIT AND (Apache-2.0 OR BSD-2-Clause)"
/// ```
pub fn canonicalize_license_expression(
  raw : String,
) -> String raise VersionError {
  if raw.is_empty() {
    raise VersionError::InvalidLicense("INVALID_EXPRESSION", 0)
  }
  let padded = pad_parentheses(raw)
  // The references are collected before the expression is lowercased, which is
  // exactly what preserves the case of the body.
  let refs : Array[(String, String)] = []
  for token in split_tokens(padded) {
    let lower = token.to_lower()
    if lower.has_prefix("licenseref-") && token.length() >= 11 {
      put_entry(refs, lower, "LicenseRef-" + token[11:].to_owned())
    }
  }
  let tokens : Array[String] = []
  for token in split_tokens(padded) {
    tokens.push(token.to_lower())
  }
  check_expression_syntax(tokens)
  let normal : Array[String] = []
  let mut last_license_start = false
  for index = 0; index < tokens.length(); index = index + 1 {
    let token = tokens[index]
    if is_operator(token) {
      // `WITH` must follow a license and must be followed by an operand.
      if token == "with" &&
        (
          !last_license_start ||
          index + 1 == tokens.length() ||
          is_operator(tokens[index + 1])
        ) {
        raise VersionError::InvalidLicense("INVALID_EXPRESSION", index)
      }
      normal.push(token.to_upper())
      last_license_start = false
      continue
    }
    if normal.length() > 0 && normal[normal.length() - 1] == "WITH" {
      match lookup_id(spdx_exceptions, token) {
        Some(id) => {
          normal.push(id)
          last_license_start = false
        }
        None =>
          raise VersionError::InvalidLicense("UNKNOWN_LICENSE_EXCEPTION", index)
      }
      continue
    }
    let (final_token, suffix) = if token.has_suffix("+") {
      (token[:token.length() - 1].to_owned(), "+")
    } else {
      (token, "")
    }
    if final_token.has_prefix("licenseref-") {
      let body = if final_token.length() >= 11 {
        final_token[11:].to_owned()
      } else {
        ""
      }
      if suffix != "" || !is_license_ref_id(body) {
        raise VersionError::InvalidLicense("INVALID_LICENSE_REF", index)
      }
      match lookup_id(refs, final_token) {
        Some(value) => normal.push(value)
        None => raise VersionError::InvalidLicense("INVALID_LICENSE_REF", index)
      }
    } else {
      match lookup_id(spdx_licenses, final_token) {
        Some(id) => normal.push(id + suffix)
        None => raise VersionError::InvalidLicense("UNKNOWN_LICENSE", index)
      }
    }
    last_license_start = true
  }
  let joined = StringBuilder()
  for index = 0; index < normal.length(); index = index + 1 {
    if index > 0 {
      joined.write_string(" ")
    }
    joined.write_string(normal[index])
  }
  // Undo the padding with exactly the two replacements `packaging` applies. They
  // are not recursive, which is harmless because every parenthesis is its own
  // token.
  joined
  .to_string()
  .replace_all(old="( ", new="(")
  .replace_all(old=" )", new=")")
}

///|
/// True when `canonicalize_license_expression` accepts `raw`. `packaging` has no
/// such helper; there this predicate only exists inside the `License-Expression`
/// metadata validator.
pub fn is_valid_license_expression(raw : String) -> Bool {
  try {
    ignore(canonicalize_license_expression(raw))
    true
  } catch {
    _ => false
  }
}

///|
/// Split a path the way `pathlib.PureWindowsPath` does, as `(drive, rooted,
/// rest)`. `pathlib` rewrites `/` to `\` (its `altsep`) before parsing, which is
/// why the handling below is on the backslash while the input may use either.
///
/// Two `splitroot` branches are deliberately not modelled, and neither can change
/// an outcome here: extended-length prefixes `\\?\` and `\\.\`, because a path
/// carrying one always still carries a backslash and is rejected by the delimiter
/// rule anyway; and UNC, because such a path starts with `/` after the rewrite and
/// is already rejected by the absolute-path rule. Only `drive letter [separator]`
/// can decide anything, exactly what is returned.
fn split_windows(path : String) -> (String, Bool, String) {
  let chars = path.replace_all(old="/", new="\\").to_array()
  let n = chars.length()
  let mut drive = ""
  let mut start = 0
  if n >= 2 && chars[1] == ':' && chars[0].is_ascii_alphabetic() {
    drive = String::from_array(chars[:2].to_owned())
    start = 2
  }
  let mut rooted = false
  if start < n && chars[start] == '\\' {
    rooted = true
    while start < n && chars[start] == '\\' {
      start = start + 1
    }
  }
  (drive, rooted, String::from_array(chars[start:].to_owned()))
}

///|
/// `pathlib.PureWindowsPath(path).as_posix()`, the value the delimiter rule
/// compares against.
///
/// That comparison is much stricter than "contains no backslash", because
/// rebuilding drops everything that is not a real component: empty components, `.`
/// components, and a trailing separator. So `./LICENSE`, `dir/`, `a//b`, `a/./b`
/// and the empty string are invalid metadata rather than being silently
/// normalized, and any backslash makes a path invalid, since `as_posix` turns it
/// into `/` and the rebuilt string can then never equal the input again.
fn windows_as_posix(path : String) -> String {
  let (drive, rooted, rest) = split_windows(path)
  let parts : Array[String] = []
  for piece in rest.split("\\") {
    let text = piece.to_owned()
    if text.length() > 0 && text != "." {
      parts.push(text)
    }
  }
  let out = StringBuilder()
  if drive != "" || rooted {
    out.write_string(drive)
    if rooted {
      out.write_string("\\")
    }
  }
  for index = 0; index < parts.length(); index = index + 1 {
    if index > 0 {
      out.write_string("\\")
    }
    out.write_string(parts[index])
  }
  let assembled = out.to_string()
  let result = if assembled.is_empty() { "." } else { assembled }
  result.replace_all(old="\\", new="/")
}

///|
/// Validate a PEP 639 `License-File` path and return it unchanged.
///
/// The name follows the request for this module, but note what the oracle
/// actually does: **`packaging` 26.3 has no `canonicalize_license_file`** and never
/// rewrites a license file path. The real rule is the private
/// `packaging.metadata.Metadata._process_license_files`, which accepts or rejects
/// and otherwise returns the path untouched. That is what is implemented here,
/// with the checks in `packaging`'s order so the reported reason matches.
///
/// `VersionError::InvalidLicense` carries a stable code, and the offset is always 0
/// because a path is a single value: `PARENT_DIRECTORY` for `..` anywhere,
/// including inside `a..b`; `UNRESOLVED_GLOB` for `*` anywhere; `ABSOLUTE_PATH`
/// for pathlib-absolute POSIX (`/`) or Windows (drive letter plus separator); and
/// `NOT_POSIX_PATH` when pathlib's Windows flavour does not reproduce the path.
///
/// ```moonbit nocheck
/// canonicalize_license_file("LICENSE")               // "LICENSE"
/// canonicalize_license_file("licenses/PSF-2.0.txt")  // unchanged
/// canonicalize_license_file("./LICENSE")             // raises NOT_POSIX_PATH
/// canonicalize_license_file("a/../b")                // raises PARENT_DIRECTORY
/// ```
pub fn canonicalize_license_file(path : String) -> String raise VersionError {
  if path.contains("..") {
    raise VersionError::InvalidLicense("PARENT_DIRECTORY", 0)
  }
  if path.contains("*") {
    raise VersionError::InvalidLicense("UNRESOLVED_GLOB", 0)
  }
  let (drive, rooted, _) = split_windows(path)
  if path.has_prefix("/") || (drive != "" && rooted) {
    raise VersionError::InvalidLicense("ABSOLUTE_PATH", 0)
  }
  if windows_as_posix(path) != path {
    raise VersionError::InvalidLicense("NOT_POSIX_PATH", 0)
  }
  path
}
