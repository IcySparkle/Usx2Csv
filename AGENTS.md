# AGENTS.md

Purpose: help maintainers (and automation) keep the PowerShell script, Go CLI,
Rust CLI, and web UI in sync while preserving the CSV schema and parsing rules.

## Project map
- `UsxToCsv.ps1`: PowerShell implementation (Windows-friendly).
- `go/convert`: shared Go parsing + CSV writer for the Go CLI and web app.
- `go/main.go`: Go CLI entry point.
- `go/web/main.go`: Go web server (upload -> download zip).
- `rust/src/main.rs`: Rust CLI implementation.
- `web-ui/`: React UI (Vite) used by the web server when `WEB_UI_DIR` is set.
- `docs/`: user-facing docs (mirrors the wiki content).
- `.github/workflows/build.yml`: CI for Go/Rust builds + release artifacts + GHCR.

## Core behavior to preserve
- One CSV row per verse with columns defined in `docs/CSV-Schema.md`.
- Verse end logic:
  - USX: `</verse eid="...">` milestone ends the verse.
  - USFM/SFM: a new `\v` marker ends the previous verse.
- Inline styles map to tags in `TextStyled` (see `docs/CSV-Schema.md`).
- Superscripts are removed from both `TextPlain` and `TextStyled`.
- Footnotes and cross-references include FT-only text; callers and markers are dropped.
- Subtitle/headings persist until replaced and are applied to each verse row.

## Keep implementations in sync
If you change parsing logic, style mappings, or CSV output, update all of:
- `UsxToCsv.ps1`
- `go/convert/convert.go`
- `rust/src/main.rs`
- `docs/CSV-Schema.md` (and `README.md` if behavior is user-visible)

## Common commands
PowerShell script:
```powershell
.\UsxToCsv.ps1 -InputPath "C:\Bible\Sources" -OutputFolder "C:\Bible\CSV"
```

Go CLI:
```powershell
cd go
go build -o usxtocsv .
.\usxtocsv -input "C:\Bible\JHN.usx" -output "C:\Bible\CSV"
```

Rust CLI:
```powershell
cd rust
cargo build --release
.\target\release\usxtocsv -input "C:\Bible\JHN.usx" -output "C:\Bible\CSV"
```

Web server (Go):
```powershell
cd go
go run .\web
```

React UI (Vite):
```powershell
cd web-ui
npm install
npm run dev
```

Docker image:
```bash
docker build -t usxtocsv-web .
docker run -p 8080:8080 usxtocsv-web
```

## Release flow
- CI runs on `main` and on tags `v*`.
- Tagging `v*` builds Go/Rust binaries, attaches them to a GitHub Release, and
  pushes `ghcr.io/<owner>/usxtocsv-web:<tag>` and `:latest`.
- Update `CHANGELOG.md` for user-visible changes before tagging.

## Environment notes
- Go: 1.22
- Rust: 1.70+ (edition 2021)
- PowerShell: 5.1 or 7+
- Node: 20+ for `web-ui`


## Deferred Item Anti-Forgetting Protocol
- If any task/decision is deferred, track it in three places in the same change set:
  1. planning doc as an explicit exit criterion (phase plan, roadmap, or equivalent),
  2. `REPO_MEMORY.md` as open/deferred work,
  3. tests as a tracker (`it.todo`, pending test, or equivalent reminder).
- Deferred items are not considered closed until the test tracker is converted into a passing assertion and the planning/memory entries are updated.
- When deferred scope changes, update planning + memory + change log together so carryover work remains visible.
