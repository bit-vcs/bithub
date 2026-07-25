# bithub

An experimental repository for a GitHub-like UI that works with `bit`.

## Current Direction

- HTTP routing via `mars`
- SSR rendering with `sol` + `luna/x/components`
- Targeting Cloudflare Workers (JS target)

See `docs/mars-sol-boundary.md` for the architecture breakdown.

## Check

```bash
moon check --target js
moon test --target js
```

## E2E (Playwright)

```bash
pnpm install
pnpm test:e2e
```

### Project-wise E2E

```bash
pnpm test:e2e:viewer  # bithub viewer
pnpm test:e2e:mars    # mars_http adapter SSR
pnpm test:e2e:cf      # src/cmd/main fetch (Cloudflare-style)
```

## Benchmark

```bash
moon bench -p bit-vcs/bithub/cmd/bithub --target js -f bench_viewer_test.mbt
pnpm bench
moon run src/cmd/bithub_bench --target js -- . 20
```

- `moon bench`: standard bench harness
- `pnpm bench`: quick summary display (default settings)
- `moon run ... -- <repo> <iterations>`: specify target repo and iteration count

## Local Viewer (`bithub .`)

Launch a minimal UI to browse the current repository in a GitHub-like style.

```bash
./bithub .        # port 8787
./bithub . 9000   # custom port
./bithub . --p2p  # generate public URL via localtunnel
./bithub . --p2p --p2p-cmd "cloudflared tunnel --url {url}" # custom tunnel command
./bithub . --relay relay+http://127.0.0.1:8788            # show relay nodes at /relay
./bithub . --p2p --relay relay+https://relay.example.com --relay-sender node-a
./bithub --catalog ./repos.catalog   # serve a multi-repo catalog top page
./bithub --catalog ./repos.catalog 9000
```

- `/` shows `README.md` by default
- `/blob/<path>` displays a file
- `/issues` lists issues from `bit hub`
- `/relay` lists bithub nodes published to the relay
- UI is built with `mizchi/luna/x/components` (minimal footprint)
- `--p2p` spawns a tunnel process and prints the public URL to stdout
- `--p2p-cmd` or `BITHUB_P2P_CMD` overrides the tunnel command (`{url}` / `{port}` are expanded)
- `--relay` queries the relay's `GET /api/v1/poll` and lists entries with `kind=bithub.node`
- `--relay-sender` sets the sender for relay publish (defaults to `BITHUB_RELAY_SENDER` / `USER`)
- `BIT_RELAY_AUTH_TOKEN` adds an Authorization header to relay poll/publish requests
- `BITHUB_RELAY_SIGN_PRIVATE_KEY_PEM` or `BITHUB_RELAY_SIGN_PRIVATE_KEY_FILE` adds signature headers (`x-relay-*`) to relay publish requests

### Catalog File (`--catalog`)

`--catalog` mode explicitly lists repositories to serve.
`/` shows a combined top page; each repo is browsable at `/repo/<id>/...`.

Example `repos.catalog` (UTF-8 text):

```text
# path only (display name derived from the last directory component)
/Users/mz/ghq/github.com/bit-vcs/bithub

# name<TAB>path
bit core	/Users/mz/ghq/github.com/bit-vcs/bit
```

- Relative paths are resolved from the catalog file's directory
- Path-only lines get an auto-generated display name

## Cloudflare Entrypoint

`src/cmd/main/main.mbt` exports `fetch(request, env, exec_ctx)` and delegates to `@mars.Server::to_handler_with_env`. Page rendering lives in `src/adapters/mars_http/server.mbt`, using `@sol.render_page` + `mizchi/luna/x/components` for SSR.

### Cloudflare Artifacts browse adapter

`worker-entry.js` binds the test namespace `bit-vcs-playground` as `ARTIFACTS`. The read-only
adapter keeps Git credentials in the Worker and exposes raw Artifacts metadata instead. The binding
uses `remote = true`, so `wrangler dev` accesses the real test namespace:

- `GET /api/artifacts/repos`
- `GET /api/artifacts/repos/<repo>/log?ref=main&limit=20&offset=0`
- `GET /api/artifacts/repos/<repo>/commits/<sha>`
- `GET /api/artifacts/repos/<repo>/trees/<sha>`

These endpoints remain disabled until a dedicated secret is configured. This prevents the default
public read UI from accidentally exposing a private Artifact repository:

```bash
pnpm wrangler secret put BITHUB_ARTIFACTS_READ_TOKEN
```

Call them with `Authorization: Bearer $BITHUB_ARTIFACTS_READ_TOKEN`. The adapter only calls
`list`, `log`, `readCommit`, and `readTree`; it never creates Git tokens, writes repository data, or
replaces bithub's R2-backed issue/PR/CI state.
