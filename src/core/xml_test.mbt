///|
test "xml_escape empty string" {
  inspect(xml_escape(""), content="")
}

///|
test "xml_escape plain text" {
  inspect(xml_escape("hello"), content="hello")
}

///|
test "xml_escape ampersand" {
  inspect(xml_escape("&"), content="&amp;")
}

///|
test "xml_escape angle brackets" {
  inspect(xml_escape("<>"), content="&lt;&gt;")
}

///|
test "xml_escape quotes" {
  inspect(xml_escape("\""), content="&quot;")
}

///|
test "xml_escape mixed content" {
  inspect(xml_escape("a & b"), content="a &amp; b")
}

///|
test "xml_escape all special chars" {
  inspect(xml_escape("&<>\""), content="&amp;&lt;&gt;&quot;")
}

///|
test "xml_escape complex example" {
  inspect(xml_escape("Hello \"world\" & <tag>"), content="Hello &quot;world&quot; &amp; &lt;tag&gt;")
}