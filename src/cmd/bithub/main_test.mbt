///|
test "parse_cli_options defaults" {
  let options = parse_cli_options(["node", "bithub"])
  assert_eq(options.repo, ".")
  assert_eq(options.port, 8787)
  assert_false(options.enable_p2p)
  assert_eq(options.p2p_command_template, None)
  assert_eq(options.catalog_path, None)
  assert_eq(options.relay_url, None)
  assert_eq(options.relay_sender, None)
}

///|
test "parse_cli_options parses positional repo and port with --p2p" {
  let options = parse_cli_options([
    "node", "bithub", "/tmp/repo", "9000", "--p2p",
  ])
  assert_eq(options.repo, "/tmp/repo")
  assert_eq(options.port, 9000)
  assert_true(options.enable_p2p)
}

///|
test "parse_cli_options supports --p2p-cmd in separate token" {
  let options = parse_cli_options([
    "node", "bithub", "--p2p", "--p2p-cmd", "cloudflared tunnel --url {url}", ".",
    "9876",
  ])
  assert_eq(options.repo, ".")
  assert_eq(options.port, 9876)
  assert_true(options.enable_p2p)
  assert_eq(
    options.p2p_command_template,
    Some("cloudflared tunnel --url {url}"),
  )
}

///|
test "parse_cli_options supports --p2p-cmd=..." {
  let options = parse_cli_options([
    "node", "bithub", "--p2p-cmd=npx --yes localtunnel --port {port}",
  ])
  assert_true(options.enable_p2p)
  assert_eq(
    options.p2p_command_template,
    Some("npx --yes localtunnel --port {port}"),
  )
}

///|
test "parse_cli_options supports --catalog and --catalog=..." {
  let options_a = parse_cli_options([
    "node", "bithub", "--catalog", "./repos.catalog", "9010",
  ])
  assert_eq(options_a.catalog_path, Some("./repos.catalog"))

  let options_b = parse_cli_options([
    "node", "bithub", "--catalog=./repos.catalog",
  ])
  assert_eq(options_b.catalog_path, Some("./repos.catalog"))
}

///|
test "parse_catalog_text supports path only and name+path lines" {
  let text =
    #|# sample
    #|/tmp/repo-a
    #|repo b	./repo-b
    #|
  let parsed = parse_catalog_text(text)
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0].0, "repo-a")
  assert_eq(parsed[0].1, "/tmp/repo-a")
  assert_eq(parsed[1].0, "repo b")
  assert_eq(parsed[1].1, "./repo-b")
}

///|
test "render_p2p_command replaces placeholders" {
  let rendered = render_p2p_command(
    "cloudflared tunnel --url {url} --name p-{port}", "http://127.0.0.1:8787", 8787,
  )
  assert_eq(
    rendered, "cloudflared tunnel --url http://127.0.0.1:8787 --name p-8787",
  )
}

///|
test "extract_first_http_url finds first public url" {
  let url = extract_first_http_url("your url is: https://abc123.loca.lt\n")
  assert_eq(url, Some("https://abc123.loca.lt"))
}

///|
test "extract_first_http_url returns none without url" {
  assert_eq(extract_first_http_url("local only"), None)
}

///|
extern "js" fn has_sol_reschedule_symbol() -> Bool =
  #| () => typeof globalThis["moonbitlang$async$internal$event_loop$$reschedule"] === "function"

///|
test "ensure_sol_reschedule_symbol installs global function" {
  ensure_sol_reschedule_symbol()
  assert_true(has_sol_reschedule_symbol())
}

///|
test "parse_cli_options supports relay flags" {
  let options = parse_cli_options([
    "node",
    "bithub",
    ".",
    "--relay",
    "relay+http://127.0.0.1:19090",
    "--relay-sender",
    "node-a",
  ])
  assert_eq(options.relay_url, Some("relay+http://127.0.0.1:19090"))
  assert_eq(options.relay_sender, Some("node-a"))
}

///|
test "parse_relay_nodes_from_poll extracts and deduplicates bithub nodes" {
  let poll_text =
    #|{
    #|  "ok": true,
    #|  "room": "main",
    #|  "next_cursor": 4,
    #|  "envelopes": [
    #|    {
    #|      "sender": "node-b",
    #|      "payload": {
    #|        "kind": "bithub.node",
    #|        "url": "https://node-b.example.com",
    #|        "name": "Repo B"
    #|      }
    #|    },
    #|    {
    #|      "sender": "node-a",
    #|      "payload": {
    #|        "kind": "hub.record",
    #|        "record": "ignored"
    #|      }
    #|    },
    #|    {
    #|      "sender": "node-a",
    #|      "payload": {
    #|        "kind": "bithub.node",
    #|        "url": "https://node-a.example.com",
    #|        "name": "Repo A"
    #|      }
    #|    },
    #|    {
    #|      "sender": "node-a",
    #|      "payload": {
    #|        "kind": "bithub.node",
    #|        "url": "https://node-a-new.example.com",
    #|        "name": "Repo A New"
    #|      }
    #|    }
    #|  ]
    #|}
  let peers = parse_relay_nodes_from_poll(poll_text)
  assert_eq(peers.length(), 2)
  assert_eq(peers[0].sender, "node-a")
  assert_eq(peers[0].url, "https://node-a-new.example.com")
  assert_eq(peers[0].name, "Repo A New")
  assert_eq(peers[1].sender, "node-b")
  assert_eq(peers[1].url, "https://node-b.example.com")
  assert_eq(peers[1].name, "Repo B")
}

///|
test "parse_relay_nodes_from_poll ignores invalid urls" {
  let poll_text =
    #|{
    #|  "envelopes": [
    #|    {
    #|      "sender": "node-a",
    #|      "payload": {
    #|        "kind": "bithub.node",
    #|        "url": "file:///tmp/nope"
    #|      }
    #|    }
    #|  ]
    #|}
  let peers = parse_relay_nodes_from_poll(poll_text)
  assert_eq(peers.length(), 0)
}
