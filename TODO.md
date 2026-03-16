# TODO

Last updated: 2026-03-16

## Rules

- Add new requests to `Inbox` first
- Move to `Doing` when started
- Move to `Done` when finished, noting the date

## Inbox

### Short-term (infra wiring)

- [x] Wire R2 binding (done 2026-03-16)
- [x] Wire `from_repo` with real filesystem (done 2026-03-16)
- [x] Deploy CI container to Cloudflare Containers (done 2026-03-16)
- [x] Auto-fill timestamps (done 2026-03-16)
- [ ] Enable Container orchestration: uncomment wrangler.toml containers config, implement spawn API endpoint

### Mid-term (features)

- [x] PR / merge request flow (done 2026-03-16)
- [x] Webhook log (done 2026-03-16)
- [x] Issue state change API (done 2026-03-16)
- [ ] Notification via relay: publish events to bit-relay when issues/PRs change

### Long-term

- [ ] Blame view: `/blame/:path` showing per-line commit attribution
- [ ] Tags / releases: `/tags` list, `/releases` with notes
- [ ] Contributors page: aggregate commit authors with counts
- [ ] Activity graph: commit frequency visualization

### Backlog

- [ ] Add E2E tests for relay node list (`/relay`)
- [ ] Improve relay node list refresh (beyond manual reload)
- [ ] Improve UI feedback on relay publish/poll failures

## Doing

- [ ] (empty)

## Done

- [x] 2026-02-19: Created `TODO.md` and started tracking
- [x] 2026-02-19: Added `/relay` node browser based on relay protocol
- [x] 2026-03-16: Merged codex/mars-first-boundary branch to main
- [x] 2026-03-16: Fixed template literal escape in split resizer script
- [x] 2026-03-16: Updated all dependencies to latest
- [x] 2026-03-16: Translated README.md, TODO.md, docs to English
- [x] 2026-03-16: Added actrun workflow YAML parser and trigger matcher
- [x] 2026-03-16: Added CI webhook E2E tests (21 → 40 cases)
- [x] 2026-03-16: Added commit history and branch listing pages
- [x] 2026-03-16: Added token-based permission control (Owner/Write/Read)
- [x] 2026-03-16: Deployed to Cloudflare Workers (https://bithub.mizchi.workers.dev)
- [x] 2026-03-16: Created CI runner container (Dockerfile + run.sh)
- [x] 2026-03-16: Abstracted Storage trait (MemoryStorage, MapStorage)
- [x] 2026-03-16: Added code search, issues, activity feed, compare, markdown rendering
- [x] 2026-03-16: Formatted timestamps as human-readable dates
- [x] 2026-03-16: Added R2Storage, git loader, issue creation API, CI spawn automation
- [x] 2026-03-16: Added FsStorage for local filesystem persistence
