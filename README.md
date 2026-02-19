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

## Benchmark

```bash
moon bench -p bit-vcs/bithub/cmd/bithub --target js -f bench_viewer_test.mbt
pnpm bench
moon run src/cmd/bithub_bench --target js -- . 20
```

- `moon bench`: 標準ベンチハーネス
- `pnpm bench`: 手早いサマリ表示（デフォルト設定）
- `moon run ... -- <repo> <iterations>`: 対象リポジトリと反復回数を明示指定

## Local Viewer (`bithub .`)

現在のリポジトリを GitHub 風に閲覧する最小 UI を起動できます。

```bash
./bithub .        # port 8787
./bithub . 9000   # custom port
./bithub . --p2p  # localtunnel で公開URLを生成
./bithub . --p2p --p2p-cmd "cloudflared tunnel --url {url}" # 任意コマンド
./bithub --catalog ./repos.catalog   # 複数repoの総合トップを公開
./bithub --catalog ./repos.catalog 9000
```

- `/` で `README.md` を優先表示
- `/blob/<path>` でファイル表示
- `/issues` で `bit hub` の Issue 一覧表示
- UI は `mizchi/luna/x/components` ベースの最小構成
- `--p2p` でトンネルを別プロセス起動して公開URLを標準出力に表示
- `--p2p-cmd` か `BITHUB_P2P_CMD` で起動コマンドを上書き（`{url}` / `{port}` を展開）

### Catalog File (`--catalog`)

`--catalog` は明示的に公開対象リポジトリを列挙するモードです。  
`/` に総合トップを表示し、各 repo は `/repo/<id>/...` で閲覧できます。

`repos.catalog` の例（UTF-8 テキスト）:

```text
# path only (表示名は末尾ディレクトリ名)
/Users/mz/ghq/github.com/bit-vcs/bithub

# name<TAB>path
bit core	/Users/mz/ghq/github.com/bit-vcs/bit
```

- 相対パスは catalog ファイルのあるディレクトリ基準で解決
- path only 行は自動で表示名を生成

## Cloudflare Entrypoint

`/Users/mz/ghq/github.com/bit-vcs/bithub/src/cmd/main/main.mbt` に
`fetch(request, env, exec_ctx)` を公開し、`@mars.Server::to_handler_with_env` へ委譲する。
GitHub-like UI interface for bit
