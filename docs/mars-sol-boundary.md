# Mars/Sol Boundary Notes (bithub)

## Goal

`bithub` keeps routing in `mars` while moving SSR to `sol` + `luna`.

## Design Rule

- `core`:
  - Contracts and pure logic for screens/features (data only)
  - No `mars` / `sol` / `luna` dependencies
- `adapters/mars_http`:
  - Connects `core` to `mars.Server`
  - HTML rendered via `sol.render_page` + `luna/x/components` SSR
- `cmd/main`:
  - Only exports the Cloudflare `fetch` entrypoint
  - Delegates to `@mars.Server::to_handler_with_env`

## Migration Intention

`core` maintains reusable data contracts; rendering strategy is swappable at the adapter layer.
Currently, Sol SSR is performed inside the `mars_http` adapter.

## Current Minimal Contract

- `core.mars_route_specs()`
- `core.home_text()`
- `core.healthz_text()`
- `core.ApiState` data contract (`list_entries` / `readme_markdown` / `lookup_file`)
