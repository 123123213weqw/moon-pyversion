///|
/// PEP 425 tag-generation cases. Each entry is
/// `(name, payload, projection)`: the name's prefix selects the reference
/// function, the payload holds its arguments, and the projection is the
/// ordered tag list (or, for `select`, the indices the selector returns).
/// A case registered as a divergence carries no projection, because the
/// reference answers it from the running machine.
///
/// Regenerate with tools/fetch_tag_corpus.py; do not edit by hand.
pub let tag_cases : Array[(String, String, String)] = [
  (
    "cpython/py312_cp312_linux", "3.12|cp312|linux_x86_64", "cp312-cp312-linux_x86_64 cp312-abi3-linux_x86_64 cp312-none-linux_x86_64 cp311-abi3-linux_x86_64 cp310-abi3-linux_x86_64 cp39-abi3-linux_x86_64 cp38-abi3-linux_x86_64 cp37-abi3-linux_x86_64 cp36-abi3-linux_x86_64 cp35-abi3-linux_x86_64 cp34-abi3-linux_x86_64 cp33-abi3-linux_x86_64 cp32-abi3-linux_x86_64",
  ),
  (
    "cpython/py312_cp312_three_platforms", "3.12|cp312|manylinux_2_17_x86_64,linux_x86_64,any",
    "cp312-cp312-manylinux_2_17_x86_64 cp312-cp312-linux_x86_64 cp312-cp312-any cp312-abi3-manylinux_2_17_x86_64 cp312-abi3-linux_x86_64 cp312-abi3-any cp312-none-manylinux_2_17_x86_64 cp312-none-linux_x86_64 cp312-none-any cp311-abi3-manylinux_2_17_x86_64 cp311-abi3-linux_x86_64 cp311-abi3-any cp310-abi3-manylinux_2_17_x86_64 cp310-abi3-linux_x86_64 cp310-abi3-any cp39-abi3-manylinux_2_17_x86_64 cp39-abi3-linux_x86_64 cp39-abi3-any cp38-abi3-manylinux_2_17_x86_64 cp38-abi3-linux_x86_64 cp38-abi3-any cp37-abi3-manylinux_2_17_x86_64 cp37-abi3-linux_x86_64 cp37-abi3-any cp36-abi3-manylinux_2_17_x86_64 cp36-abi3-linux_x86_64 cp36-abi3-any cp35-abi3-manylinux_2_17_x86_64 cp35-abi3-linux_x86_64 cp35-abi3-any cp34-abi3-manylinux_2_17_x86_64 cp34-abi3-linux_x86_64 cp34-abi3-any cp33-abi3-manylinux_2_17_x86_64 cp33-abi3-linux_x86_64 cp33-abi3-any cp32-abi3-manylinux_2_17_x86_64 cp32-abi3-linux_x86_64 cp32-abi3-any",
  ),
  (
    "cpython/py312_two_abis", "3.12|cp312,cp312d|any", "cp312-cp312-any cp312-cp312d-any cp312-abi3-any cp312-none-any cp311-abi3-any cp310-abi3-any cp39-abi3-any cp38-abi3-any cp37-abi3-any cp36-abi3-any cp35-abi3-any cp34-abi3-any cp33-abi3-any cp32-abi3-any",
  ),
  (
    "cpython/py312_explicit_stable_abis", "3.12|abi3,none|any", "cp312-abi3-any cp312-none-any cp311-abi3-any cp310-abi3-any cp39-abi3-any cp38-abi3-any cp37-abi3-any cp36-abi3-any cp35-abi3-any cp34-abi3-any cp33-abi3-any cp32-abi3-any",
  ),
  (
    "cpython/py312_no_abis", "3.12||any", "cp312-abi3-any cp312-none-any cp311-abi3-any cp310-abi3-any cp39-abi3-any cp38-abi3-any cp37-abi3-any cp36-abi3-any cp35-abi3-any cp34-abi3-any cp33-abi3-any cp32-abi3-any",
  ),
  (
    "cpython/py313_threaded", "3.13|cp313t|any", "cp313-cp313t-any cp313-abi3t-any cp313-none-any cp312-abi3t-any cp311-abi3t-any cp310-abi3t-any cp39-abi3t-any cp38-abi3t-any cp37-abi3t-any cp36-abi3t-any cp35-abi3t-any cp34-abi3t-any cp33-abi3t-any cp32-abi3t-any",
  ),
  (
    "cpython/py313_threaded_second_abi", "3.13|cp313,cp313t|any", "cp313-cp313-any cp313-cp313t-any cp313-abi3-any cp313-none-any cp312-abi3-any cp311-abi3-any cp310-abi3-any cp39-abi3-any cp38-abi3-any cp37-abi3-any cp36-abi3-any cp35-abi3-any cp34-abi3-any cp33-abi3-any cp32-abi3-any",
  ),
  (
    "cpython/py314_threaded_first", "3.14|cp314t,cp314|any", "cp314-cp314t-any cp314-cp314-any cp314-abi3t-any cp314-none-any cp313-abi3t-any cp312-abi3t-any cp311-abi3t-any cp310-abi3t-any cp39-abi3t-any cp38-abi3t-any cp37-abi3t-any cp36-abi3t-any cp35-abi3t-any cp34-abi3t-any cp33-abi3t-any cp32-abi3t-any",
  ),
  (
    "cpython/py32_boundary", "3.2|cp32|any", "cp32-cp32-any cp32-abi3-any cp32-none-any",
  ),
  ("cpython/py31_before_abi3", "3.1|cp31|any", "cp31-cp31-any cp31-none-any"),
  ("cpython/py3_major_only", "3|cp3|any", "cp3-cp3-any cp3-none-any"),
  (
    "cpython/py27_legacy_abi", "2.7|cp27mu|manylinux1_x86_64", "cp27-cp27mu-manylinux1_x86_64 cp27-none-manylinux1_x86_64",
  ),
  (
    "cpython/py38_debug_abis", "3.8|cp38d,cp38|any", "cp38-cp38d-any cp38-cp38-any cp38-abi3-any cp38-none-any cp37-abi3-any cp36-abi3-any cp35-abi3-any cp34-abi3-any cp33-abi3-any cp32-abi3-any",
  ),
  (
    "cpython/py310_uppercase", "3.10|CP310|LINUX_X86_64", "cp310-cp310-linux_x86_64 cp310-abi3-linux_x86_64 cp310-none-linux_x86_64 cp39-abi3-linux_x86_64 cp38-abi3-linux_x86_64 cp37-abi3-linux_x86_64 cp36-abi3-linux_x86_64 cp35-abi3-linux_x86_64 cp34-abi3-linux_x86_64 cp33-abi3-linux_x86_64 cp32-abi3-linux_x86_64",
  ),
  (
    "cpython/py313_threaded_two_platforms", "3.13|cp313t|linux_x86_64,any", "cp313-cp313t-linux_x86_64 cp313-cp313t-any cp313-abi3t-linux_x86_64 cp313-abi3t-any cp313-none-linux_x86_64 cp313-none-any cp312-abi3t-linux_x86_64 cp312-abi3t-any cp311-abi3t-linux_x86_64 cp311-abi3t-any cp310-abi3t-linux_x86_64 cp310-abi3t-any cp39-abi3t-linux_x86_64 cp39-abi3t-any cp38-abi3t-linux_x86_64 cp38-abi3t-any cp37-abi3t-linux_x86_64 cp37-abi3t-any cp36-abi3t-linux_x86_64 cp36-abi3t-any cp35-abi3t-linux_x86_64 cp35-abi3t-any cp34-abi3t-linux_x86_64 cp34-abi3t-any cp33-abi3t-linux_x86_64 cp33-abi3t-any cp32-abi3t-linux_x86_64 cp32-abi3t-any",
  ),
  (
    "cpython/py39_stable_only_platform", "3.9|cp39|win_amd64", "cp39-cp39-win_amd64 cp39-abi3-win_amd64 cp39-none-win_amd64 cp38-abi3-win_amd64 cp37-abi3-win_amd64 cp36-abi3-win_amd64 cp35-abi3-win_amd64 cp34-abi3-win_amd64 cp33-abi3-win_amd64 cp32-abi3-win_amd64",
  ),
  (
    "generic/pp310_pp73", "pp310|pp73|linux_x86_64", "pp310-pp73-linux_x86_64 pp310-none-linux_x86_64",
  ),
  ("generic/pp310_none_only", "pp310|none|any", "pp310-none-any"),
  (
    "generic/pp310_uppercase_none", "pp310|NONE|any", "pp310-none-any pp310-none-any",
  ),
  (
    "generic/graalpy_no_abis", "graalpy_38_native||any", "graalpy_38_native-none-any",
  ),
  (
    "generic/cp312_two_abis", "cp312|cp312,abi3|manylinux_2_17_x86_64", "cp312-cp312-manylinux_2_17_x86_64 cp312-abi3-manylinux_2_17_x86_64 cp312-none-manylinux_2_17_x86_64",
  ),
  (
    "generic/jy27_multi_platform", "jy27|jython27|win_amd64,any", "jy27-jython27-win_amd64 jy27-jython27-any jy27-none-win_amd64 jy27-none-any",
  ),
  (
    "generic/uppercase_interpreter", "PP310|pp73|ANY", "pp310-pp73-any pp310-none-any",
  ),
  (
    "pure/py312", "3.12", "py312-none-any py3-none-any py311-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any",
  ),
  (
    "pure/py310", "3.10", "py310-none-any py3-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any",
  ),
  ("pure/py32", "3.2", "py32-none-any py3-none-any py31-none-any py30-none-any"),
  (
    "pure/py27", "2.7", "py27-none-any py2-none-any py26-none-any py25-none-any py24-none-any py23-none-any py22-none-any py21-none-any py20-none-any",
  ),
  ("pure/py3_major_only", "3", "py3-none-any"),
  ("pure/py30", "3.0", "py30-none-any py3-none-any"),
  ("pure/py20", "2.0", "py20-none-any py2-none-any"),
  (
    "compatible/py311_cp311_linux", "3.11|cp311|linux_x86_64", "py311-none-linux_x86_64 py3-none-linux_x86_64 py310-none-linux_x86_64 py39-none-linux_x86_64 py38-none-linux_x86_64 py37-none-linux_x86_64 py36-none-linux_x86_64 py35-none-linux_x86_64 py34-none-linux_x86_64 py33-none-linux_x86_64 py32-none-linux_x86_64 py31-none-linux_x86_64 py30-none-linux_x86_64 cp311-none-any py311-none-any py3-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any",
  ),
  (
    "compatible/py311_no_interpreter", "3.11|-|any", "py311-none-any py3-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any py311-none-any py3-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any",
  ),
  (
    "compatible/py311_empty_interpreter", "3.11||any", "py311-none-any py3-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any py311-none-any py3-none-any py310-none-any py39-none-any py38-none-any py37-none-any py36-none-any py35-none-any py34-none-any py33-none-any py32-none-any py31-none-any py30-none-any",
  ),
  (
    "compatible/py27_py2_win", "2.7|py2|win_amd64", "py27-none-win_amd64 py2-none-win_amd64 py26-none-win_amd64 py25-none-win_amd64 py24-none-win_amd64 py23-none-win_amd64 py22-none-win_amd64 py21-none-win_amd64 py20-none-win_amd64 py2-none-any py27-none-any py2-none-any py26-none-any py25-none-any py24-none-any py23-none-any py22-none-any py21-none-any py20-none-any",
  ),
  (
    "compatible/py3_major_only", "3|cp3|any", "py3-none-any cp3-none-any py3-none-any",
  ),
  (
    "mac/mojave_x86_64", "10.9|x86_64", "macosx_10_9_x86_64 macosx_10_9_intel macosx_10_9_fat64 macosx_10_9_fat3 macosx_10_9_universal2 macosx_10_9_universal macosx_10_8_x86_64 macosx_10_8_intel macosx_10_8_fat64 macosx_10_8_fat3 macosx_10_8_universal2 macosx_10_8_universal macosx_10_7_x86_64 macosx_10_7_intel macosx_10_7_fat64 macosx_10_7_fat3 macosx_10_7_universal2 macosx_10_7_universal macosx_10_6_x86_64 macosx_10_6_intel macosx_10_6_fat64 macosx_10_6_fat3 macosx_10_6_universal2 macosx_10_6_universal macosx_10_5_x86_64 macosx_10_5_intel macosx_10_5_fat64 macosx_10_5_fat3 macosx_10_5_universal2 macosx_10_5_universal macosx_10_4_x86_64 macosx_10_4_intel macosx_10_4_fat64 macosx_10_4_fat3 macosx_10_4_universal2 macosx_10_4_universal",
  ),
  (
    "mac/big_sur_arm64", "11.0|arm64", "macosx_11_0_arm64 macosx_11_0_universal2 macosx_10_16_universal2 macosx_10_15_universal2 macosx_10_14_universal2 macosx_10_13_universal2 macosx_10_12_universal2 macosx_10_11_universal2 macosx_10_10_universal2 macosx_10_9_universal2 macosx_10_8_universal2 macosx_10_7_universal2 macosx_10_6_universal2 macosx_10_5_universal2 macosx_10_4_universal2",
  ),
  (
    "mac/monterey_x86_64", "12.3|x86_64", "macosx_12_0_x86_64 macosx_12_0_intel macosx_12_0_fat64 macosx_12_0_fat3 macosx_12_0_universal2 macosx_12_0_universal macosx_11_0_x86_64 macosx_11_0_intel macosx_11_0_fat64 macosx_11_0_fat3 macosx_11_0_universal2 macosx_11_0_universal macosx_10_16_x86_64 macosx_10_16_intel macosx_10_16_fat64 macosx_10_16_fat3 macosx_10_16_universal2 macosx_10_16_universal macosx_10_15_x86_64 macosx_10_15_intel macosx_10_15_fat64 macosx_10_15_fat3 macosx_10_15_universal2 macosx_10_15_universal macosx_10_14_x86_64 macosx_10_14_intel macosx_10_14_fat64 macosx_10_14_fat3 macosx_10_14_universal2 macosx_10_14_universal macosx_10_13_x86_64 macosx_10_13_intel macosx_10_13_fat64 macosx_10_13_fat3 macosx_10_13_universal2 macosx_10_13_universal macosx_10_12_x86_64 macosx_10_12_intel macosx_10_12_fat64 macosx_10_12_fat3 macosx_10_12_universal2 macosx_10_12_universal macosx_10_11_x86_64 macosx_10_11_intel macosx_10_11_fat64 macosx_10_11_fat3 macosx_10_11_universal2 macosx_10_11_universal macosx_10_10_x86_64 macosx_10_10_intel macosx_10_10_fat64 macosx_10_10_fat3 macosx_10_10_universal2 macosx_10_10_universal macosx_10_9_x86_64 macosx_10_9_intel macosx_10_9_fat64 macosx_10_9_fat3 macosx_10_9_universal2 macosx_10_9_universal macosx_10_8_x86_64 macosx_10_8_intel macosx_10_8_fat64 macosx_10_8_fat3 macosx_10_8_universal2 macosx_10_8_universal macosx_10_7_x86_64 macosx_10_7_intel macosx_10_7_fat64 macosx_10_7_fat3 macosx_10_7_universal2 macosx_10_7_universal macosx_10_6_x86_64 macosx_10_6_intel macosx_10_6_fat64 macosx_10_6_fat3 macosx_10_6_universal2 macosx_10_6_universal macosx_10_5_x86_64 macosx_10_5_intel macosx_10_5_fat64 macosx_10_5_fat3 macosx_10_5_universal2 macosx_10_5_universal macosx_10_4_x86_64 macosx_10_4_intel macosx_10_4_fat64 macosx_10_4_fat3 macosx_10_4_universal2 macosx_10_4_universal",
  ),
  (
    "mac/tahoe_arm64", "15.0|arm64", "macosx_15_0_arm64 macosx_15_0_universal2 macosx_14_0_arm64 macosx_14_0_universal2 macosx_13_0_arm64 macosx_13_0_universal2 macosx_12_0_arm64 macosx_12_0_universal2 macosx_11_0_arm64 macosx_11_0_universal2 macosx_10_16_universal2 macosx_10_15_universal2 macosx_10_14_universal2 macosx_10_13_universal2 macosx_10_12_universal2 macosx_10_11_universal2 macosx_10_10_universal2 macosx_10_9_universal2 macosx_10_8_universal2 macosx_10_7_universal2 macosx_10_6_universal2 macosx_10_5_universal2 macosx_10_4_universal2",
  ),
  ("mac/panther_x86_64", "10.3|x86_64", ""),
  ("mac/panther_i386", "10.3|i386", ""),
  (
    "mac/tiger_x86_64", "10.4|x86_64", "macosx_10_4_x86_64 macosx_10_4_intel macosx_10_4_fat64 macosx_10_4_fat3 macosx_10_4_universal2 macosx_10_4_universal",
  ),
  (
    "mac/snow_leopard_ppc64", "10.6|ppc64", "macosx_10_5_ppc64 macosx_10_5_fat64 macosx_10_5_universal macosx_10_4_ppc64 macosx_10_4_fat64 macosx_10_4_universal",
  ),
  (
    "mac/leopard_ppc64", "10.5|ppc64", "macosx_10_5_ppc64 macosx_10_5_fat64 macosx_10_5_universal macosx_10_4_ppc64 macosx_10_4_fat64 macosx_10_4_universal",
  ),
  (
    "mac/lion_ppc", "10.7|ppc", "macosx_10_6_ppc macosx_10_6_fat3 macosx_10_6_fat macosx_10_6_universal macosx_10_5_ppc macosx_10_5_fat3 macosx_10_5_fat macosx_10_5_universal macosx_10_4_ppc macosx_10_4_fat3 macosx_10_4_fat macosx_10_4_universal macosx_10_3_ppc macosx_10_3_fat3 macosx_10_3_fat macosx_10_3_universal macosx_10_2_ppc macosx_10_2_fat3 macosx_10_2_fat macosx_10_2_universal macosx_10_1_ppc macosx_10_1_fat3 macosx_10_1_fat macosx_10_1_universal macosx_10_0_ppc macosx_10_0_fat3 macosx_10_0_fat macosx_10_0_universal",
  ),
  (
    "mac/snow_leopard_ppc", "10.6|ppc", "macosx_10_6_ppc macosx_10_6_fat3 macosx_10_6_fat macosx_10_6_universal macosx_10_5_ppc macosx_10_5_fat3 macosx_10_5_fat macosx_10_5_universal macosx_10_4_ppc macosx_10_4_fat3 macosx_10_4_fat macosx_10_4_universal macosx_10_3_ppc macosx_10_3_fat3 macosx_10_3_fat macosx_10_3_universal macosx_10_2_ppc macosx_10_2_fat3 macosx_10_2_fat macosx_10_2_universal macosx_10_1_ppc macosx_10_1_fat3 macosx_10_1_fat macosx_10_1_universal macosx_10_0_ppc macosx_10_0_fat3 macosx_10_0_fat macosx_10_0_universal",
  ),
  ("mac/system9_x86_64", "9.2|x86_64", ""),
  (
    "mac/sonoma_i386", "14.0|i386", "macosx_14_0_i386 macosx_14_0_intel macosx_14_0_fat3 macosx_14_0_fat macosx_14_0_universal macosx_13_0_i386 macosx_13_0_intel macosx_13_0_fat3 macosx_13_0_fat macosx_13_0_universal macosx_12_0_i386 macosx_12_0_intel macosx_12_0_fat3 macosx_12_0_fat macosx_12_0_universal macosx_11_0_i386 macosx_11_0_intel macosx_11_0_fat3 macosx_11_0_fat macosx_11_0_universal macosx_10_16_universal2 macosx_10_15_universal2 macosx_10_14_universal2 macosx_10_13_universal2 macosx_10_12_universal2 macosx_10_11_universal2 macosx_10_10_universal2 macosx_10_9_universal2 macosx_10_8_universal2 macosx_10_7_universal2 macosx_10_6_universal2 macosx_10_5_universal2 macosx_10_4_universal2",
  ),
  (
    "mac/big_sur_x86_64", "11.0|x86_64", "macosx_11_0_x86_64 macosx_11_0_intel macosx_11_0_fat64 macosx_11_0_fat3 macosx_11_0_universal2 macosx_11_0_universal macosx_10_16_x86_64 macosx_10_16_intel macosx_10_16_fat64 macosx_10_16_fat3 macosx_10_16_universal2 macosx_10_16_universal macosx_10_15_x86_64 macosx_10_15_intel macosx_10_15_fat64 macosx_10_15_fat3 macosx_10_15_universal2 macosx_10_15_universal macosx_10_14_x86_64 macosx_10_14_intel macosx_10_14_fat64 macosx_10_14_fat3 macosx_10_14_universal2 macosx_10_14_universal macosx_10_13_x86_64 macosx_10_13_intel macosx_10_13_fat64 macosx_10_13_fat3 macosx_10_13_universal2 macosx_10_13_universal macosx_10_12_x86_64 macosx_10_12_intel macosx_10_12_fat64 macosx_10_12_fat3 macosx_10_12_universal2 macosx_10_12_universal macosx_10_11_x86_64 macosx_10_11_intel macosx_10_11_fat64 macosx_10_11_fat3 macosx_10_11_universal2 macosx_10_11_universal macosx_10_10_x86_64 macosx_10_10_intel macosx_10_10_fat64 macosx_10_10_fat3 macosx_10_10_universal2 macosx_10_10_universal macosx_10_9_x86_64 macosx_10_9_intel macosx_10_9_fat64 macosx_10_9_fat3 macosx_10_9_universal2 macosx_10_9_universal macosx_10_8_x86_64 macosx_10_8_intel macosx_10_8_fat64 macosx_10_8_fat3 macosx_10_8_universal2 macosx_10_8_universal macosx_10_7_x86_64 macosx_10_7_intel macosx_10_7_fat64 macosx_10_7_fat3 macosx_10_7_universal2 macosx_10_7_universal macosx_10_6_x86_64 macosx_10_6_intel macosx_10_6_fat64 macosx_10_6_fat3 macosx_10_6_universal2 macosx_10_6_universal macosx_10_5_x86_64 macosx_10_5_intel macosx_10_5_fat64 macosx_10_5_fat3 macosx_10_5_universal2 macosx_10_5_universal macosx_10_4_x86_64 macosx_10_4_intel macosx_10_4_fat64 macosx_10_4_fat3 macosx_10_4_universal2 macosx_10_4_universal",
  ),
  (
    "mac/ten_sixteen_x86_64", "10.16|x86_64", "macosx_10_16_x86_64 macosx_10_16_intel macosx_10_16_fat64 macosx_10_16_fat3 macosx_10_16_universal2 macosx_10_16_universal macosx_10_15_x86_64 macosx_10_15_intel macosx_10_15_fat64 macosx_10_15_fat3 macosx_10_15_universal2 macosx_10_15_universal macosx_10_14_x86_64 macosx_10_14_intel macosx_10_14_fat64 macosx_10_14_fat3 macosx_10_14_universal2 macosx_10_14_universal macosx_10_13_x86_64 macosx_10_13_intel macosx_10_13_fat64 macosx_10_13_fat3 macosx_10_13_universal2 macosx_10_13_universal macosx_10_12_x86_64 macosx_10_12_intel macosx_10_12_fat64 macosx_10_12_fat3 macosx_10_12_universal2 macosx_10_12_universal macosx_10_11_x86_64 macosx_10_11_intel macosx_10_11_fat64 macosx_10_11_fat3 macosx_10_11_universal2 macosx_10_11_universal macosx_10_10_x86_64 macosx_10_10_intel macosx_10_10_fat64 macosx_10_10_fat3 macosx_10_10_universal2 macosx_10_10_universal macosx_10_9_x86_64 macosx_10_9_intel macosx_10_9_fat64 macosx_10_9_fat3 macosx_10_9_universal2 macosx_10_9_universal macosx_10_8_x86_64 macosx_10_8_intel macosx_10_8_fat64 macosx_10_8_fat3 macosx_10_8_universal2 macosx_10_8_universal macosx_10_7_x86_64 macosx_10_7_intel macosx_10_7_fat64 macosx_10_7_fat3 macosx_10_7_universal2 macosx_10_7_universal macosx_10_6_x86_64 macosx_10_6_intel macosx_10_6_fat64 macosx_10_6_fat3 macosx_10_6_universal2 macosx_10_6_universal macosx_10_5_x86_64 macosx_10_5_intel macosx_10_5_fat64 macosx_10_5_fat3 macosx_10_5_universal2 macosx_10_5_universal macosx_10_4_x86_64 macosx_10_4_intel macosx_10_4_fat64 macosx_10_4_fat3 macosx_10_4_universal2 macosx_10_4_universal",
  ),
  (
    "select/exact_before_generic", "cp312-cp312-linux_x86_64,cp312-abi3-linux_x86_64,py3-none-any|cp312-cp312-linux_x86_64;py3-none-any;cp311-cp311-linux_x86_64",
    "0 1",
  ),
  (
    "select/best_tag_wins", "cp312-cp312-linux_x86_64,cp312-abi3-linux_x86_64,cp312-none-any,py3-none-any|py3-none-any,cp312-abi3-linux_x86_64;cp312-none-any,py3-none-any;py3-none-any",
    "0 1 2",
  ),
  (
    "select/nothing_matches", "cp312-cp312-linux_x86_64|py3-none-any;cp311-cp311-linux_x86_64",
    "",
  ),
  ("select/no_supported_tags", "|py3-none-any", ""),
  ("select/no_items", "py3-none-any|", ""),
  (
    "select/duplicate_tags_in_one_file", "py3-none-any|py3-none-any,py3-none-any",
    "0",
  ),
  ("cpython/host_python_version", "|cp312|any", ""),
  ("compatible/host_python_version", "|cp311|any", ""),
  ("generic/host_interpreter", "|pp73|any", ""),
  ("cpython/host_platforms", "3.12|cp312|", ""),
  ("generic/host_platforms", "pp310|pp73|", ""),
  ("compatible/host_platforms", "3.12|cp312|", ""),
]

///|
/// Cases where the reference reads the host and this library refuses to.
/// The second field is what the reference does: the divergence is asserted
/// in both directions, so a library that started guessing would fail here.
pub let tag_divergences : Array[(String, Bool)] = [
  ("cpython/host_python_version", true),
  ("compatible/host_python_version", true),
  ("generic/host_interpreter", true),
  ("cpython/host_platforms", true),
  ("generic/host_platforms", true),
  ("compatible/host_platforms", true),
]
