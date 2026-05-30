# macos-runner-setup

One script to provision a macOS machine as a [GitHub Actions self-hosted runner](https://docs.github.com/en/actions/hosting-your-own-runners) for Swift / iOS CI — and to verify it's actually registered.

Born out of a long night of CI flakes on inconsistent self-hosted runners (Homebrew off the non-login `PATH`, missing iOS runtimes, no `iPhone 16` simulator on the newest runtime, duplicate sims making name-based destinations ambiguous). This bakes the fixes in so a fresh box comes up consistent.

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/BoutLabs/macos-runner-setup/main/setup-macos-runner.sh \
  | bash -s -- --owner BoutLabs
```

Or clone and run:

```sh
./setup-macos-runner.sh --owner BoutLabs            # org-level runner
./setup-macos-runner.sh --owner BoutLabs --repo herenotes-ios   # repo-level runner
```

Flags:
- `--owner <org-or-user>` — used to build the exact runner-registration URL
- `--repo <name>` — omit for an org-level runner (serves every repo in the org)
- `--device <name>` — simulator device to ensure (default `iPhone 16`)
- `--runner-dir <path>` — where the runner lives (default `~/actions-runner`; also via `ACTIONS_RUNNER_DIR`)

## What it does (idempotent — re-run anytime)

1. **Homebrew** — installs if missing; writes `brew shellenv` to `~/.zprofile` so the runner's non-login shell finds `brew` and brew-installed tools.
2. **CI tools** — `swiftlint`, `swiftformat`, `xcbeautify`.
3. **Xcode** — checks `xcodebuild`; if absent, prints the install + `xcode-select` + license-accept steps (the Xcode install itself isn't automated).
4. **iOS runtime** — ensures one exists; downloads the latest if not.
5. **Simulator device** — ensures the target device exists **on the newest runtime**, creating it if needed; warns if duplicates have accumulated.
6. **Runner registration** — checks for a configured runner; if none, prints the exact `…/settings/actions/runners/new` URL and the labels CI expects (`self-hosted, macOS, ARM64`). Registration is interactive (needs a one-time token from GitHub) and is never stored here.

## Notes

- macOS + Apple Silicon (`arm64`) assumed; CI labels expect `ARM64` and Homebrew lives at `/opt/homebrew`.
- The script installs tooling and inspects state — it does **not** register the runner for you (that requires a token you generate on the GitHub page it points you to).
- **Run the runner as your user, not as root.** iOS simulators are per-user (`~/Library/Developer/CoreSimulator`), so the runner has to run as the user that owns them — use `svc.sh` (a per-user LaunchAgent), not a root LaunchDaemon. That's why the runner dir defaults to a user-owned path; keep it user-owned wherever you point `--runner-dir` (e.g. `~/.local/share/actions-runner`), not a root-owned `/opt` path.
