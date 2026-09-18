# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**single-seat-desktops**: an installer (`install/`) that turns existing Linux accounts on a Debian
Linux Terminal VM (Android's Linux Terminal app / crosvm) into switchable,
real-hardware wayfire desktops — one "host" account stays on weston as the
stable base, every other onboarded account gets its own `wayfire`
compositor, switched to one at a time via a `<user>-wayfire` alias. This is
convenience isolation between trusted accounts (or trusted personas of one
person) sharing one physical device — **not a security boundary**.
Switching is authorized by the host account's own root access, not by
proving you are the target account, so it is not appropriate for handing
the device to a genuinely untrusted individual.

Pure bash + systemd units/config, no build step. `install/README.md` has
the full usage/architecture rationale; read it before making changes —
most non-obvious decisions in this codebase are the product of real,
documented debugging, not arbitrary choices.

## Commands

No build step. There is no repo-wide linter configured; `bash -n
<script>` is the syntax check used throughout (also run automatically by
`test_repo_hygiene.sh`, see below).

```sh
# Run the safe part of the suite (unit + functional; never disruptive)
bash install/tests/run.sh
bash install/tests/run.sh unit
bash install/tests/run.sh functional

# Run a single test file directly
bash install/tests/functional/test_customize_foot.sh

# The one test gated behind an env var (draws from every real account on
# the box; keep off on a shared machine unless you've verified the logic)
WF_TESTS_ALLOW_SHARED_BOX=1 bash install/tests/functional/test_core_installer.sh

# Lists (never runs) the disruptive tests
bash install/tests/run.sh disruptive
```

**Before ever running `install/tests/disruptive/test_switch_desktop.sh`
or manually invoking `/usr/local/bin/switch-desktop.sh` yourself as an
agent**: check `cat /proc/$$/cgroup` first. If it shows a
`wayfire-*.service` unit, your own process tree is nested inside a live
wayfire session, and `switch-desktop.sh`'s own "stop any other onboarded
user's wayfire" step will kill that cgroup — including you, mid-command.
This happened for real in this project's history. Only proceed from a
session that is not nested inside any wayfire unit, and even then treat
it as visibly disruptive to whatever is currently on the real display.

## Architecture

**Core vs. personal customization are deliberately separate scripts, run
by different people/privilege levels.** `10-install-wayfire-desktops.sh`
(root, run once per account) installs every package any personal
customization could possibly need up front, then generates only a
minimal `wayfire.ini`/`wf-shell.ini` — no terminal, weather, clocks, or
launchers. `wayfire-customize.sh` (no root, run by the account itself,
any time) layers those personal choices on top: it rewrites a single
`term1 =` line in `wayfire.ini` and a marker-delimited block
(`# --- wayfire-customize: begin/end managed block ---`) appended to
`wf-shell.ini`. Never hand-edit inside that block or the `term1` line —
regenerate via `wayfire-customize.sh --apply` instead, which reads
`~/.config/wayfire-customize.conf` as its source of truth.
`backup-user.sh`/`restore-user.sh` back up exactly that conf file (plus
`timezone`/`background.png`) — nothing generated — because everything
else is cheaply re-derived from it.

**The switch mechanism has a hard invocation constraint.**
`switch-desktop.sh` (deployed to `/usr/local/bin`, invoked via a
`<user>-wayfire` alias in the host account's `.bash_aliases`) must be run
*directly by the host account*, never sudo'd into, never called from
another account's shell. It calls plain `systemctl --user stop/start
weston...`, which always targets whoever is *actually calling it* — not
a named account. Getting this wrong doesn't fail loudly on its own: it
silently no-ops, weston never releases the seat, and the next wayfire
launch is doomed before it starts (seatd correctly refuses the new
client, libseat falls back to an embedded seat backend that needs root
and can't get it as a regular user, hangs a fixed 10s, segfaults). The
script now explicitly checks that weston actually stopped and fails fast
with an actionable message instead of proceeding into that failure — but
the underlying constraint (run it as the host account, directly) still
stands and is not something the script can fully defend itself against.

**Root-launched GUI apps go through `pkexec-wayland`, never plain
`pkexec`.** `pkexec` resets almost the entire environment before exec'ing
as root, including `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` — a native-Wayland
GTK app run through plain `pkexec` just fails to show a window with no
obvious error. `pkexec-wayland` (caller-side) +
`pkexec-wayland-helper` (root-side, re-exports the env) +
`local.pkexec-wayland.policy` thread those two values through as plain
arguments instead (pkexec strips environment, not argv). This is generic
— reuse it for any future root-needing GUI launcher, not just Synaptic.

**Testability is threaded through specific env-var overrides, not
general mocking.** `wayfire-customize.sh` and `00-create-users.sh` each
have a `main()` guarded by `if [ "${BASH_SOURCE[0]}" = "$0" ]; then main
"$@"; fi` so they can be sourced without executing. `wayfire-customize.sh`
also reads `WAYFIRE_INI`/`WFSHELL_INI`/`CONF`/`SUPPORT`/`DRM_SYS_PATH`
from the environment with real-path defaults — tests set these to point
at scratch files and a fake sysfs tree; production code never sets them.

## Testing philosophy (see `install/tests/README.md` for full detail)

Tests run the *real* script through its *real* CLI entry point, with
real subprocess execution (a stub `foot`/`curl` placed first in `PATH`)
and real filesystem state checked afterward — not string-diffs against
source text, and not assertions about implementation details like an
exact file mode. Where a permission genuinely matters, the test checks
the reason it has to be that way (can another onboarded user actually
read this file?), not the literal numeric mode. Unit tests are kept to a
deliberate minimum (currently one: `resolve_foot_args`'s arithmetic) —
add one only for a genuinely pure, stable computation that would need
disproportionate scaffolding to reach through the real CLI.

`install/tests/.personal_pattern` (gitignored) holds the actual regex of
personal identifiers to scrub before this repo is public;
`test_repo_hygiene.sh` (committed) reads it generically and skips
cleanly if the file is absent. That pattern must never be hardcoded into
a committed file — doing so would defeat the entire point of the check.

Three test tiers by risk: `unit/` and `functional/` need no live wayfire
session and mostly no sudo (a couple do, and skip cleanly if it's
unavailable); `disruptive/` actually calls `switch-desktop.sh` and
visibly takes over the real display — see the invocation-constraint
warning under Commands above before ever running it.
