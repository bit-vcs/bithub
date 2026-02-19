# Mars/Sol Boundary Notes (bithub)

## Goal

`bithub` はルーティングを `mars` で維持しつつ、SSR は `sol` + `luna` へ寄せる。

## Design Rule

- `core`:
  - 画面/機能の契約と純粋ロジック（データ返却のみ）
  - `mars` / `sol` / `luna` 依存を入れない
- `adapters/mars_http`:
  - `core` を `mars.Server` へ接続する層
  - HTML は `sol.render_page` + `luna/x/components` で SSR する
- `cmd/main`:
  - Cloudflare 向け `fetch` エントリ公開のみ
  - `@mars.Server::to_handler_with_env` に委譲する

## Migration Intention

`core` は再利用可能なデータ契約を保ち、描画戦略は adapter 側で差し替える。
現状は `mars_http` adapter 内で Sol SSR を実施済み。

## Current Minimal Contract

- `core.mars_route_specs()`
- `core.home_text()`
- `core.healthz_text()`
- `core.ApiState` のデータ契約（`list_entries` / `readme_markdown` / `lookup_file`）
