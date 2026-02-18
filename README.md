# bithub

`bit` と連携する GitHub-like UI のための実験リポジトリです。

## Current Direction

- まずは `mars` で実装する
- `sol` へ引き上げられるように分解点を固定する
- Cloudflare Workers (JS target) 前提で進める

分解方針は `/Users/mz/ghq/github.com/bit-vcs/bithub/docs/mars-sol-boundary.md` を参照。

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

## Local Viewer (`bithub .`)

現在のリポジトリを GitHub 風に閲覧する最小 UI を起動できます。

```bash
./bithub .        # port 8787
./bithub . 9000   # custom port
```

- `/` で `README.md` を優先表示
- `/blob/<path>` でファイル表示
- UI は `mizchi/luna/x/components` ベースの最小構成

## Cloudflare Entrypoint

`/Users/mz/ghq/github.com/bit-vcs/bithub/src/cmd/main/main.mbt` に
`fetch(request, env, exec_ctx)` を公開し、`@mars.Server::to_handler_with_env` へ委譲する。
GitHub-like UI interface for bit
