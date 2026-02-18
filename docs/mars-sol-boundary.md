# Mars/Sol Boundary Notes (bithub)

## Goal

`bithub` は当面 `mars` で機能を作り、`sol` への引き上げ可能性を維持する。

## Design Rule

- `core`:
  - 画面/機能の契約と純粋ロジック
  - `mars` / `sol` 依存を入れない
- `adapters/mars_http`:
  - `core` を `mars.Server` へ接続する層
- `cmd/main`:
  - Cloudflare 向け `fetch` エントリ公開のみ
  - `@mars.Server::to_handler_with_env` に委譲する

## Migration Intention

将来 `sol` へ寄せる場合は、`core` を温存したまま `adapters/sol_*` を追加し、`mars_http` との差し替えで移行する。

## Current Minimal Contract

- `core.mars_route_specs()`
- `core.home_text()`
- `core.healthz_text()`

`mars_http` はこの契約だけに依存する。
