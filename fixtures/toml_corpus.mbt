///|
/// TOML 1.0 conformance cases with the verdict of the reference reader
/// (`tomli`). Each entry is `(name, document, accepted, canonical value)`;
/// a rejected document carries an empty canonical value.
///
/// Regenerate with tools/fetch_toml_corpus.py; do not edit by hand.
pub let toml_cases : Array[(String, String, Bool, String)] = [
  ("01_empty", "# nothing but a comment\n\n", true, "table:{}"),
  (
    "02_scalars", "str = \"hello\"\nint = 42\nfloat = 3.25\nbool = true\nbool2 = false\ndt = 1979-05-27T07:32:00Z\n",
    true, "table:{str=str:hello,int=int:42,float=float:3.25,bool=bool:true,bool2=bool:false,dt=datetime:1979-05-27 07:32:00+00:00}",
  ),
  (
    "03_strings_basic", "a = \"\"\nb = \"plain\"\nc = \"with \\\"quotes\\\" inside\"\nd = \"tab\\there\"\ne = \"back\\\\slash\"\nf = \"quote at end \\\"\"\ng = \"unicode: \\u00e9 \\u4e2d\"\n",
    true, "table:{a=str:,b=str:plain,c=str:with \"quotes\" inside,d=str:tab\there,e=str:back\\\\slash,f=str:quote at end \",g=str:unicode: é 中}",
  ),
  (
    "04_strings_literal", "a = ''\nb = 'C:\\Users\\nodejs'\nc = 'no \\n escape'\nd = \"literal # not comment\"\ne = 'quoted \"double\" inside'\n",
    true, "table:{a=str:,b=str:C:\\\\Users\\\\nodejs,c=str:no \\\\n escape,d=str:literal # not comment,e=str:quoted \"double\" inside}",
  ),
  (
    "05_strings_ml_basic", "a = \"\"\"\nline one\nline two\"\"\"\nb = \"\"\"ends with quote\\\"\"\"\"\nc = \"\"\"has \\\"literal\\\" quotes\"\"\"\nd = \"\"\"no newline at start\"\"\"\n",
    true, "table:{a=str:line one\\nline two,b=str:ends with quote\",c=str:has \"literal\" quotes,d=str:no newline at start}",
  ),
  (
    "06_strings_ml_literal", "a = '''\nfirst\nsecond'''\nb = '''single line'''\nc = '''has '' two quotes'''\nd = '''C:\\path\\x'''\n",
    true, "table:{a=str:first\\nsecond,b=str:single line,c=str:has '' two quotes,d=str:C:\\\\path\\\\x}",
  ),
  (
    "07_escapes", "nl = \"\\n\"\ntab = \"\\t\"\ncr = \"\\r\"\nbs = \"\\\\\"\nquote = \"\\\"\"\nb = \"\\b\"\nf = \"\\f\"\nu = \"\\u0041\"\nu2 = \"\\u00e9\"\nU = \"\\U0001F600\"\n",
    true, "table:{nl=str:\\n,tab=str:\t,cr=str:\r,bs=str:\\\\,quote=str:\",b=str:,f=str:,u=str:A,u2=str:é,U=str:😀}",
  ),
  (
    "08_unicode_escapes", "emoji = \"\\U0001F600\"\naccent = \"\\u00E9\"\ncjk = \"\\u4E2D\\u6587\"\nmixed = \"a\\u00e9b\\U0001F600c\"\nraw = \"日本語 텍스트\"\n",
    true, "table:{emoji=str:😀,accent=str:é,cjk=str:中文,mixed=str:aéb😀c,raw=str:日本語 텍스트}",
  ),
  (
    "09_integers", "a = 0\nb = 1\nc = -1\nd = +1\ne = 1234567890\nf = 1_000_000\ng = 0x7FFFFFFF\nh = 0x7fff_ffff\ni = 0o755\nj = 0b1010_1010\nk = -0\nl = 2147483647\nm = -2147483648\n",
    true, "table:{a=int:0,b=int:1,c=int:-1,d=int:1,e=int:1234567890,f=int:1000000,g=int:2147483647,h=int:2147483647,i=int:493,j=int:170,k=int:0,l=int:2147483647,m=int:-2147483648}",
  ),
  (
    "10_floats", "a = 1.0\nb = 3.1415\nc = -0.01\nd = 5e+22\ne = 1e6\nf = -2E-2\ng = 6.626e-34\nh = 224_617.445_991_228\ni = 0.0\nj = -0.0\nk = 1e0\n",
    true, "table:{a=float:1.0,b=float:3.1415,c=float:-0.01,d=float:5e+22,e=float:1000000.0,f=float:-0.02,g=float:6.626e-34,h=float:224617.445991228,i=float:0.0,j=float:-0.0,k=float:1.0}",
  ),
  (
    "11_special_floats", "a = inf\nb = +inf\nc = -inf\nd = nan\ne = +nan\n", true,
    "table:{a=float:inf,b=float:inf,c=float:-inf,d=float:nan,e=float:nan}",
  ),
  (
    "12_booleans", "t = true\nf = false\nnested_true = true\n", true, "table:{t=bool:true,f=bool:false,nested_true=bool:true}",
  ),
  (
    "13_datetimes", "odt1 = 1979-05-27T07:32:00Z\nodt2 = 1979-05-27T00:32:00-07:00\nodt3 = 1979-05-27T00:32:00.999999-07:00\nodt4 = 1979-05-27 07:32:00Z\nodt5 = 1979-05-27t07:32:00z\nldt1 = 1979-05-27T07:32:00\nldt2 = 1979-05-27T00:32:00.5\nld1 = 1979-05-27\nlt1 = 07:32:00\nlt2 = 00:32:00.999999\nlt3 = 23:59:59\n",
    true, "table:{odt1=datetime:1979-05-27 07:32:00+00:00,odt2=datetime:1979-05-27 00:32:00-07:00,odt3=datetime:1979-05-27 00:32:00.999999-07:00,odt4=datetime:1979-05-27 07:32:00+00:00,odt5=datetime:1979-05-27 07:32:00+00:00,ldt1=datetime:1979-05-27 07:32:00,ldt2=datetime:1979-05-27 00:32:00.500000,ld1=datetime:1979-05-27,lt1=datetime:07:32:00,lt2=datetime:00:32:00.999999,lt3=datetime:23:59:59}",
  ),
  (
    "14_arrays", "a = []\nb = [1, 2, 3]\nc = [\"x\", \"y\"]\nd = [true, false]\ne = [1, \"two\", 3.0, true]\nf = [1979-05-27]\ng = [[1, 2], [3, 4]]\nh = [{x = 1}, {y = 2}]\n",
    true, "table:{a=array:[],b=array:[int:1,int:2,int:3],c=array:[str:x,str:y],d=array:[bool:true,bool:false],e=array:[int:1,str:two,float:3.0,bool:true],f=array:[datetime:1979-05-27],g=array:[array:[int:1,int:2],array:[int:3,int:4]],h=array:[table:{x=int:1},table:{y=int:2}]}",
  ),
  (
    "15_arrays_nested", "a = [[[[1]]]]\nb = [[1, 2], [3]]\nc = [[], []]\nd = [1, [2, [3, [4]]]]\n",
    true, "table:{a=array:[array:[array:[array:[int:1]]]],b=array:[array:[int:1,int:2],array:[int:3]],c=array:[array:[],array:[]],d=array:[int:1,array:[int:2,array:[int:3,array:[int:4]]]]}",
  ),
  (
    "16_arrays_multiline", "a = [\n  1, # first\n  2,\n  3,   # third\n]\nb = [\n  \"x\", \"y\",\n  \"z\"\n]\nc = [ # leading comment\n  1\n]\n",
    true, "table:{a=array:[int:1,int:2,int:3],b=array:[str:x,str:y,str:z],c=array:[int:1]}",
  ),
  (
    "17_inline_tables", "a = {}\nb = { x = 1 }\nc = { x = 1, y = 2 }\nd = { name = \"x\", ver = \"1.0\" }\ne = { nested = { a = 1 } }\nf = { arr = [1, 2] }\n",
    true, "table:{a=table:{},b=table:{x=int:1},c=table:{x=int:1,y=int:2},d=table:{name=str:x,ver=str:1.0},e=table:{nested=table:{a=int:1}},f=table:{arr=array:[int:1,int:2]}}",
  ),
  (
    "18_inline_nested", "a = { b = { c = { d = 1 } } }\nb = { x = 1, y = { z = 2 }, w = [1, {q = 2}] }\nc = { dotted.key = 1 }\n",
    true, "table:{a=table:{b=table:{c=table:{d=int:1}}},b=table:{x=int:1,y=table:{z=int:2},w=array:[int:1,table:{q=int:2}]},c=table:{dotted=table:{key=int:1}}}",
  ),
  (
    "19_tables", "[a]\nx = 1\ny = 2\n", true, "table:{a=table:{x=int:1,y=int:2}}",
  ),
  (
    "20_tables_nested", "[a]\nx = 1\n\n[a.b]\ny = 2\n\n[a.b.c]\nz = 3\n", true, "table:{a=table:{x=int:1,b=table:{y=int:2,c=table:{z=int:3}}}}",
  ),
  (
    "21_tables_out_of_order", "[fruit.apple]\ncolor = \"red\"\n\n[animal]\nkind = \"cat\"\n\n[fruit.orange]\ncolor = \"orange\"\n",
    true, "table:{fruit=table:{apple=table:{color=str:red},orange=table:{color=str:orange}},animal=table:{kind=str:cat}}",
  ),
  (
    "22_dotted_keys", "a.b.c = 1\na.b.d = 2\na.e = 3\nname.first = \"x\"\nname.last = \"y\"\n\"quoted.key\".inner = 1\n",
    true, "table:{a=table:{b=table:{c=int:1,d=int:2},e=int:3},name=table:{first=str:x,last=str:y},\"quoted.key\"=table:{inner=int:1}}",
  ),
  (
    "23_dotted_key_subtable", "[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n\n[fruit.apple.texture]\nsmooth = true\n",
    true, "table:{fruit=table:{apple=table:{color=str:red,taste=table:{sweet=bool:true},texture=table:{smooth=bool:true}}}}",
  ),
  (
    "24_array_of_tables", "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\n\n[[products]]\nname = \"Nail\"\nsku = 284758393\ncolor = \"gray\"\n",
    true, "table:{products=array:[table:{name=str:Hammer,sku=int:738594937},table:{},table:{name=str:Nail,sku=int:284758393,color=str:gray}]}",
  ),
  (
    "25_aot_nested", "[[a.b]]\nx = 1\n\n[[a.b]]\nx = 2\n", true, "table:{a=table:{b=array:[table:{x=int:1},table:{x=int:2}]}}",
  ),
  (
    "26_aot_subtables", "[[a]]\nx = 1\n\n[a.b]\ny = 2\n\n[[a]]\nx = 3\n\n[a.b]\ny = 4\n",
    true, "table:{a=array:[table:{x=int:1,b=table:{y=int:2}},table:{x=int:3,b=table:{y=int:4}}]}",
  ),
  (
    "27_quoted_keys", "\"a b\" = 1\n'a.b' = 2\n\"\" = 3\n'' = 4\n\"unicode key é\" = 5\n",
    false, "",
  ),
  (
    "28_comments", "# leading comment\na = 1 # trailing comment\n# another line\n\nb = 2#comment without space\nc = \"# not a comment\"\n",
    true, "table:{a=int:1,b=int:2,c=str:# not a comment}",
  ),
  (
    "29_pyproject_like", "[build-system]\nrequires = [\"setuptools>=61.0\", \"wheel\"]\nbuild-backend = \"setuptools.build_meta\"\n\n[project]\nname = \"example-package\"\nversion = \"0.0.1\"\ndescription = \"A small example package\"\nreadme = \"README.md\"\nrequires-python = \">=3.8\"\nkeywords = [\"sample\", \"setuptools\"]\nclassifiers = [\n  \"Programming Language :: Python :: 3\",\n  \"License :: OSI Approved :: MIT License\",\n]\ndependencies = [\n  \"requests>=2.28\",\n  \"click\",\n]\n\n[project.optional-dependencies]\ntest = [\"pytest>=7.0\"]\ndev = [\"ruff\", \"mypy>=1.0\"]\n\n[project.urls]\nHomepage = \"https://github.com/example/example\"\n\"Bug Tracker\" = \"https://github.com/example/example/issues\"\n\n[project.scripts]\nexample = \"example:main\"\n\n[tool.black]\nline-length = 88\ntarget-version = [\"py38\", \"py39\"]\n\n[tool.ruff]\nline-length = 88\n\n[tool.ruff.lint]\nselect = [\"E\", \"F\", \"I\"]\nignore = []\n\n[tool.pytest.ini_options]\naddopts = \"-ra -q\"\ntestpaths = [\"tests\"]\n\n[tool.mypy]\npython_version = \"3.11\"\nwarn_unused_ignores = true\n\n[tool.poetry]\nname = \"poetry-demo\"\nversion = \"0.1.0\"\nauthors = [\"X <x@example.com>\"]\n",
    true, "table:{build-system=table:{requires=array:[str:setuptools>=61.0,str:wheel],build-backend=str:setuptools.build_meta},project=table:{name=str:example-package,version=str:0.0.1,description=str:A small example package,readme=str:README.md,requires-python=str:>=3.8,keywords=array:[str:sample,str:setuptools],classifiers=array:[str:Programming Language :: Python :: 3,str:License :: OSI Approved :: MIT License],dependencies=array:[str:requests>=2.28,str:click],optional-dependencies=table:{test=array:[str:pytest>=7.0],dev=array:[str:ruff,str:mypy>=1.0]},urls=table:{Homepage=str:https://github.com/example/example,\"Bug Tracker\"=str:https://github.com/example/example/issues},scripts=table:{example=str:example:main}},tool=table:{black=table:{line-length=int:88,target-version=array:[str:py38,str:py39]},ruff=table:{line-length=int:88,lint=table:{select=array:[str:E,str:F,str:I],ignore=array:[]}},pytest=table:{ini_options=table:{addopts=str:-ra -q,testpaths=array:[str:tests]}},mypy=table:{python_version=str:3.11,warn_unused_ignores=bool:true},poetry=table:{name=str:poetry-demo,version=str:0.1.0,authors=array:[str:X <x@example.com>]}}}",
  ),
  (
    "30_pylock_like", "lock-version = \"1.1\"\npython-versions = \">=3.9\"\ncontent-hash = \"abc123\"\n\n[[package]]\nname = \"certifi\"\nversion = \"2023.7.22\"\ndescription = \"Python package for providing Mozilla's CA Bundle.\"\noptional = false\npython-versions = \">=3.6\"\nfiles = [\n  {file = \"certifi-2023.7.22-py3-none-any.whl\", hash = \"sha256:92d6037539857d8206b8f6ae472e8b77db8058fec5937a1ef3f54304089edbb9\"},\n  {file = \"certifi-2023.7.22.tar.gz\", hash = \"sha256:539cc1d13202e33ca466e88b2807e29f4c13049d6d87031a3c110744495cb082\"},\n]\n\n[package.dependencies]\nchardet = \">=3.0.2\"\n\n[[package]]\nname = \"requests\"\nversion = \"2.31.0\"\noptional = false\n\n[package.dependencies]\ncertifi = \">=2017.4.17\"\ncharset-normalizer = \">=2,<4\"\nidna = \">=2.5,<4\"\nurllib3 = \">=1.21.1,<3\"\n\n[package.extras]\nsocks = [\"PySocks (>=1.5.6,!=1.5.7)\"]\nuse-chardet-on-py3 = [\"chardet (>=3.0.2,<6)\"]\n\n[metadata]\nlock-version = \"2.0\"\npython-versions = \">=3.9\"\ncontent-hash = \"def456\"\n",
    true, "table:{lock-version=str:1.1,python-versions=str:>=3.9,content-hash=str:abc123,package=array:[table:{name=str:certifi,version=str:2023.7.22,description=str:Python package for providing Mozilla's CA Bundle.,optional=bool:false,python-versions=str:>=3.6,files=array:[table:{file=str:certifi-2023.7.22-py3-none-any.whl,hash=str:sha256:92d6037539857d8206b8f6ae472e8b77db8058fec5937a1ef3f54304089edbb9},table:{file=str:certifi-2023.7.22.tar.gz,hash=str:sha256:539cc1d13202e33ca466e88b2807e29f4c13049d6d87031a3c110744495cb082}],dependencies=table:{chardet=str:>=3.0.2}},table:{name=str:requests,version=str:2.31.0,optional=bool:false,dependencies=table:{certifi=str:>=2017.4.17,charset-normalizer=str:>=2,<4,idna=str:>=2.5,<4,urllib3=str:>=1.21.1,<3},extras=table:{socks=array:[str:PySocks (>=1.5.6,!=1.5.7)],use-chardet-on-py3=array:[str:chardet (>=3.0.2,<6)]}}],metadata=table:{lock-version=str:2.0,python-versions=str:>=3.9,content-hash=str:def456}}",
  ),
  (
    "31_crlf", "# comment\na = 1\nb = \"two\"\n\n[t]\nc = 3\n", true, "table:{a=int:1,b=str:two,t=table:{c=int:3}}",
  ),
  (
    "32_ws_edges", "\ta\t=\t1\t\n  b = 2  \n\n   \n[s]\n\t c = 3\n", true, "table:{a=int:1,b=int:2,s=table:{c=int:3}}",
  ),
  (
    "33_empty_containers", "a = []\nb = {}\nc = [[]]\nd = [{}]\ne = { f = {} }\n",
    true, "table:{a=array:[],b=table:{},c=array:[array:[]],d=array:[table:{}],e=table:{f=table:{}}}",
  ),
  (
    "34_numbers_underscores", "a = 1_2_3\nb = 1_000_000_000\nc = 0x1_2\nd = 0b1_0_1\ne = 0o7_5_5\nf = 1_0.5_5\ng = 1e1_0\nh = 1_0e1_0\n",
    true, "table:{a=int:123,b=int:1000000000,c=int:18,d=int:5,e=int:493,f=float:10.55,g=float:10000000000.0,h=float:100000000000.0}",
  ),
  (
    "35_ml_line_continuation", "a = \"\"\"\\\n   The quick brown \\\n   fox jumps over \\\n   the lazy dog.\\\n   \"\"\"\nb = \"\"\"one \\\n   two\"\"\"\nc = \"\"\"\\\n   x\"\"\"\n",
    true, "table:{a=str:The quick brown fox jumps over the lazy dog.,b=str:one two,c=str:x}",
  ),
  (
    "36_array_inline_tables", "points = [ { x = 1, y = 2 }, { x = 3, y = 4 } ]\n",
    true, "table:{points=array:[table:{x=int:1,y=int:2},table:{x=int:3,y=int:4}]}",
  ),
  (
    "37_key_forms", "bare = 1\nbare-key = 2\nbare_key = 3\n1234 = 4\n- = 5\n_ = 6\n\"127.0.0.1\" = 7\n'key with spaces' = 8\n",
    true, "table:{bare=int:1,bare-key=int:2,bare_key=int:3,1234=int:4,-=int:5,_=int:6,\"127.0.0.1\"=int:7,\"key with spaces\"=int:8}",
  ),
  ("38_no_trailing_newline", "a = 1\nb = 2", true, "table:{a=int:1,b=int:2}"),
  (
    "39_comment_only_lines", "a = 1\n\n# comment\n   # indented comment\n\nb = 2 # end\n",
    true, "table:{a=int:1,b=int:2}",
  ),
  (
    "40_table_after_dotted_root", "a.b = 1\n[a.c]\nd = 2\n", true, "table:{a=table:{b=int:1,c=table:{d=int:2}}}",
  ),
  (
    "41_top_level_and_tables", "title = \"root value\"\ncount = 3\n\n[owner]\nname = \"x\"\n\n[[servers]]\nhost = \"a\"\n\n[[servers]]\nhost = \"b\"\n",
    true, "table:{title=str:root value,count=int:3,owner=table:{name=str:x},servers=array:[table:{host=str:a},table:{host=str:b}]}",
  ),
  (
    "42_string_specials", "empty = \"\"\nspace = \" \"\nnewline_via_escape = \"a\\nb\"\nlong_ml = \"\"\"\nfirst\nsecond\nthird\n\"\"\"\nliteral_ml = '''\nhas \"quotes\"\nand # hash\n'''\n",
    true, "table:{empty=str:,space=str: ,newline_via_escape=str:a\\nb,long_ml=str:first\\nsecond\\nthird\\n,literal_ml=str:has \"quotes\"\\nand # hash\\n}",
  ),
  (
    "43_keys_duplicated_in_sections", "[a]\nb = 1\n\n[c]\nb = 1\n\n[d.e]\nf = 1\n\n[d.g]\nf = 1\n",
    true, "table:{a=table:{b=int:1},c=table:{b=int:1},d=table:{e=table:{f=int:1},g=table:{f=int:1}}}",
  ),
  (
    "44_inline_table_in_aot", "[[p]]\ndata = { a = 1, b = [1, 2] }\n", true, "table:{p=array:[table:{data=table:{a=int:1,b=array:[int:1,int:2]}}]}",
  ),
  (
    "45_deep_mix", "[tool.x]\na.b.c.d = 1\n\n[tool.x.a.b.c.e]\nf = 2\n\n[[tool.x.list]]\nn = 1\n\n[[tool.x.list]]\nn = 2\n\n[tool.x.list.sub]\nm = 3\n",
    true, "table:{tool=table:{x=table:{a=table:{b=table:{c=table:{d=int:1,e=table:{f=int:2}}}},list=array:[table:{n=int:1},table:{n=int:2,sub=table:{m=int:3}}]}}}",
  ),
  (
    "46_arrays_mixed", "# TOML 1.0.0 removed the 0.5 rule that array members share a type.\nmixed = [1, \"x\", true, 1979-05-27, [2], {b = 3}]\n",
    true, "table:{mixed=array:[int:1,str:x,bool:true,datetime:1979-05-27,array:[int:2],table:{b=int:3}]}",
  ),
  ("90_err_dup_key", "a = 1\na = 2\n", false, ""),
  ("91_err_bad_escape", "a = \"\\q\"\n", false, ""),
  ("92_err_unterminated_string", "a = \"abc\n", false, ""),
  (
    "93_err_inline_trailing_comma", "a = {b = 1,}\n", true, "table:{a=table:{b=int:1}}",
  ),
  (
    "94_err_inline_newline", "a = {b = 1,\n c = 2}\n", true, "table:{a=table:{b=int:1,c=int:2}}",
  ),
  ("95_err_redefine_table", "[a]\nx = 1\n[a]\ny = 2\n", false, ""),
  ("96_err_value_then_table", "[a]\nb = 1\n[a.b]\n", false, ""),
  ("97_err_inline_extend", "a = {b = 1}\n[a.c]\nd = 1\n", false, ""),
  ("98_err_leading_zero", "a = 01\n", false, ""),
  ("99_err_bad_underscore", "a = 1__2\n", false, ""),
  ("9A_err_invalid_value", "a = @nope\n", false, ""),
  ("9B_err_dup_dotted", "a.b = 1\na.b.c = 2\n", false, ""),
  ("9C_err_surrogate_escape", "a = \"\\uD800\"\n", false, ""),
  ("9D_err_unclosed_array", "a = [1, 2\n", false, ""),
  ("9E_err_no_newline_after_stmt", "a = 1 = 2\n", false, ""),
  ("9F_err_bad_datetime", "a = 1979-02-30\n", false, ""),
  ("9G_err_newline_in_basic_string", "a = \"x\ny\"\n", false, ""),
  ("9H_err_aot_then_table", "[[a]]\nx = 1\n[a]\ny = 2\n", false, ""),
  ("9I_err_dup_inline_key", "a = {b = 1, b = 2}\n", false, ""),
  ("9J_err_hex_float", "a = 0x1.5\n", false, ""),
  (
    "9K_err_dotted_then_table_header", "[fruit]\napple.color = 'red'\n[fruit.apple]\nx = 1\n",
    false, "",
  ),
  ("9L_err_bare_key_only", "a\n", false, ""),
  ("9M_err_table_reopen_dotted_root", "a.b = 1\n[a]\n", false, ""),
  ("9N_err_empty_table_header", "[]\n", false, ""),
  ("9O_err_inline_dotted_frozen", "a = {b = {c = 1}, b.d = 2}\n", false, ""),
  ("9P_err_table_then_aot", "[a]\nx = 1\n[[a]]\ny = 2\n", false, ""),
  ("9Q_err_float_leading_dot", "a = .5\n", false, ""),
  ("9R_err_bare_key_unicode", "é = 1\n", false, ""),
  ("9S_err_aot_no_close", "[[a]\n", false, ""),
  ("9T_err_underscore_lead", "a = _1\n", false, ""),
  ("9U_err_trailing_dot_key", "a. = 1\n", false, ""),
  (
    "9V_err_dup_table_after_aot_sub", "[[a]]\n[a.b]\nx = 1\n[a.b]\ny = 2\n", false,
    "",
  ),
  ("9W_err_key_no_value", "a =\n", false, ""),
  (
    "9X_err_inline_after_table_value", "[a]\nb = {c = 1}\n[a.b.d]\ne = 1\n", false,
    "",
  ),
  ("9Y_err_hex_escape", "a = \"\\x41\"\n", true, "table:{a=str:A}"),
]

///|
/// Case names where TOML 1.0 requires a rejection but the reference
/// reader accepts one. See `toml_cases/leniencies.txt` for the reason.
pub let toml_leniencies : Array[String] = [
  "93_err_inline_trailing_comma", "94_err_inline_newline", "9Y_err_hex_escape",
]
