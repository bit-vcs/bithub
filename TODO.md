# TODO

Last updated: 2026-03-17

## Rules

- Add new requests to `Inbox` first
- Move to `Doing` when started
- Move to `Done` when finished, noting the date

## Inbox

### Architecture: split oversized files

- [ ] Split server.mbt into per-page render files
  - Extract render_commits_page, render_commit_detail_page → `render_commits.mbt`
  - Extract render_issues_page, render_issue_detail_page → `render_issues.mbt`
  - Extract render_pulls_page, render_pull_detail_page → `render_pulls.mbt`
  - Extract render_ci_page, render_ci_run_detail_page → `render_ci.mbt`
  - Extract render_search_page, render_blame_page → `render_search.mbt`
  - Extract render_activity_page, render_webhooks_page → `render_misc.mbt`
  - Extract render_tags_page, render_stats_page → `render_misc.mbt`
  - Keep routing + layout + helpers in `server.mbt`
- [ ] Split core package into domain packages
  - `src/core/issues/` — IssueEntry, IssueDetail, create/list/get/update
  - `src/core/pulls/` — PullRequest, create/list/get/merge/close/comment
  - `src/core/ci/` — CiRun, CiJobRun, CiStepRun, process_relay_webhook
  - `src/core/git/` — CommitEntry, BranchEntry, TagEntry, blame, compare
  - Keep Storage trait + ApiState facade in `src/core/`
- [ ] Extract seed data from api_state.mbt into `seed.mbt`
  - Move seed_files() to dedicated file
  - Make seed data optional (only for demo/test mode)

### Architecture: fix R2 and auth

- [ ] Lazy R2 loading: load keys on demand instead of preloading all
  - Add async get/list FFI that returns Promises
  - Cache per-request, not globally
- [ ] Environment-based auth tokens
  - Read `BITHUB_AUTH_TOKENS` env var (JSON array of {token, identity, role})
  - Fall back to seed tokens only when env var is absent
- [ ] from_repo file edits write back to real filesystem
  - When FsStorage path maps to a repo file, also write to the actual file
  - Optionally run `git add` + `git commit` after file edits

### Code quality

- [x] Fix deprecated is_none()/f!() and strconv import (done 2026-03-17, by agents)
- [x] Move parse_kv_fields to storage.mbt (done 2026-03-17, by agent)
- [x] Make route tests resilient (done 2026-03-17, by agent)
- [ ] Fix remaining 9 deprecated warnings
  - `fn(ctx)` → arrow function in 8 async handlers (server.mbt)
  - `fn meth(self : Type, ..)` → `fn Type::meth(..)` in fs_storage.mbt

### Agent harness

- [ ] Multi-file edit support: allow agent to make coordinated changes across files
  - Batch patch_file calls with rollback on moon check failure
- [ ] Auto-retry loop on moon check failure
  - Read error message, feed back to LLM, retry (max 3 attempts)
- [ ] Add `moon_ide` tool wrapping `moon ide peek-def` and `moon ide outline`
  - More accurate than grep for MoonBit symbol lookup

### Remaining features

- [ ] Enable Container orchestration in wrangler.toml
- [ ] Notification via relay: publish events to bit-relay
- [ ] Tags / releases page (tags implemented, releases not yet)
- [ ] Activity graph: commit frequency visualization
- [ ] Add E2E tests for relay node list (`/relay`)

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
- [x] 2026-03-16: Added CI webhook E2E tests (40 cases)
- [x] 2026-03-16: Added commit history and branch listing pages
- [x] 2026-03-16: Added token-based permission control (Owner/Write/Read)
- [x] 2026-03-16: Deployed to Cloudflare Workers
- [x] 2026-03-16: Created CI runner container
- [x] 2026-03-16: Abstracted Storage trait (Memory, Map, Fs, R2)
- [x] 2026-03-16: Added search, issues, activity, compare, markdown
- [x] 2026-03-16: Formatted timestamps as human-readable dates
- [x] 2026-03-16: Added R2Storage, git loader, issue API, CI spawn
- [x] 2026-03-16: Added FsStorage for local filesystem persistence
- [x] 2026-03-16: Wired R2 binding + auto-fill timestamps
- [x] 2026-03-16: Wired real git repo via NodeFs + bitlib
- [x] 2026-03-16: Pushed CI runner to Cloudflare Containers registry
- [x] 2026-03-16: Added PR flow, webhook log, issue state change
- [x] 2026-03-16: Added blame view
- [x] 2026-03-16: Added file editing API, tags, stats, RSS, diff highlight, PR comments
- [x] 2026-03-17: Multi-agent collaboration scenario + OpenRouter demo
- [x] 2026-03-17: Persistent from_repo mode with FsStorage
- [x] 2026-03-17: Agent harness with tool-use loop (read/write/patch/run/search)
- [x] 2026-03-17: MoonBit skills injected into agent system prompt
- [x] 2026-03-17: Agent successfully completed coding task (parse_int_safe tests)
