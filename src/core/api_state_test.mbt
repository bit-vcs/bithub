///|
test "xml_escape handles basic XML special characters" {
  inspect(xml_escape("hello"), content="hello")
  inspect(xml_escape("&"), content="&amp;")
  inspect(xml_escape("<"), content="&lt;")
  inspect(xml_escape(">"), content="&gt;")
  inspect(xml_escape("\""), content="&quot;")
}

///|
test "xml_escape handles multiple special characters" {
  inspect(xml_escape("&<>\""), content="&amp;&lt;&gt;&quot;")
  inspect(xml_escape("<tag>"), content="&lt;tag&gt;")
  inspect(xml_escape("\"quoted\""), content="&quot;quoted&quot;")
  inspect(xml_escape("A & B"), content="A &amp; B")
}

///|
test "xml_escape handles mixed content" {
  inspect(xml_escape("Hello <world> & \"friends\"!"), content="Hello &lt;world&gt; &amp; &quot;friends&quot;!")
  inspect(xml_escape("x < y && z > w"), content="x &lt; y &amp;&amp; z &gt; w")
  inspect(xml_escape("Say \"Hello & goodbye\""), content="Say &quot;Hello &amp; goodbye&quot;")
}

///|
test "xml_escape handles empty and single character strings" {
  inspect(xml_escape(""), content="")
  inspect(xml_escape("a"), content="a")
  inspect(xml_escape("&"), content="&amp;")
  inspect(xml_escape("<"), content="&lt;")
  inspect(xml_escape(">"), content="&gt;")
  inspect(xml_escape("\""), content="&quot;")
}

///|
test "xml_escape preserves normal characters" {
  inspect(xml_escape("abcdefghijklmnopqrstuvwxyz"), content="abcdefghijklmnopqrstuvwxyz")
  inspect(xml_escape("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), content="ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  inspect(xml_escape("0123456789"), content="0123456789")
  inspect(xml_escape("!@#$%^*()_+-=[]{}|;':,./?"), content="!@#$%^*()_+-=[]{}|;':,./?")
}

///|
test "xml_escape handles real-world XML content" {
  let title = "Project <name> & \"description\""
  let expected = "Project &lt;name&gt; &amp; &quot;description&quot;"
  inspect(xml_escape(title), content=expected)
  
  let description = "This is a <test> description with & symbols and \"quotes\""
  let expected_desc = "This is a &lt;test&gt; description with &amp; symbols and &quot;quotes&quot;"
  inspect(xml_escape(description), content=expected_desc)
}