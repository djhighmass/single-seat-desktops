# Test suite

```
./run.sh              runs unit + functional (never disruptive)
./run.sh unit
./run.sh functional
./run.sh disruptive   lists the disruptive tests -- run one yourself
```

## Philosophy

Tests are purpose-driven: does X actually fulfill Y by doing Z. Almost
everything here runs the *real* script through its *real* CLI entry
point (`wayfire-customize.sh --apply`, `00-create-users.sh`,
`10-install-wayfire-desktops.sh`), with real subprocess execution (a
stub `foot`/`curl` to observe real behavior) and real file-system state
checked afterward -- not string-diffs against expected source text, and
not assertions about implementation details like an exact file mode.
Where a permission genuinely matters, the test checks the reason it has
to be that way (can another onboarded user actually read this file?),
not the literal numeric mode.

**Unit tests exist too, deliberately kept to a minimum** -- currently
just `unit/test_resolve_foot_args.sh`, which is a small, pure,
already-stable computation ("quarter of the screen" = half-width times
half-height) that would need a fake DRM connector to reach at all
through the real CLI. That's the bar for adding another one: a genuinely
pure, stable contract where testing it end-to-end would need
disproportionate scaffolding for what it's checking. The default for
everything else is functional, precisely so that refactoring an
internal implementation doesn't force rewriting the tests that cover it.

A couple of functional tests still extract a small function out of a
script (`install_nopasswd_sudoers` in `00-create-users.sh`) -- not to
dodge testing real behavior, but to dodge an *unrelated* dependency
(`adduser`'s interactive password/GECOS prompts) that has nothing to do
with the bug being guarded against. The extracted code is still real,
still called with real arguments, still exercised through real
`visudo`/`usermod`/file-install calls.

Nothing a test produces -- generated configs, screenshots, backup
archives -- ever lands in the repo. Everything runs against a
`mktemp -d` scratch directory, discarded on exit.

## Layout

```
lib/testlib.sh           shared assert helpers + scratch-dir setup
unit/                     pure functions, mocked inputs, no sudo
functional/               real scripts, real execution, mostly no sudo
disruptive/               real switch-desktop.sh calls -- never auto-run
.personal_pattern         gitignored -- see test_repo_hygiene.sh
```

## Implemented

- **unit/test_resolve_foot_args.sh** -- the foot-size arithmetic
  (`quarter`/`full`/literal `WIDTHxHEIGHT`), the one deliberate unit test.
- **functional/test_customize_foot.sh** -- `wayfire-customize.sh --apply`
  generates the `[autostart]` term1 line; the line is then *actually
  executed* through a real shell against a stub `foot`, checking the
  stub's real argv and where its real stdout/stderr landed. This is what
  would have caught this session's escaped-quote bug, and does.
- **functional/test_customize_weather.sh** -- generates the per-user
  weather fetcher, then runs *that* generated script for real against a
  stub `curl`. Covers both the happy path and the jq-null-handling
  regression (a response missing `current_weather` must leave prior data
  untouched, not write a bogus 0°C reading).
- **functional/test_customize_clock.sh** -- generates the extra-clock
  script, runs it for real under a forced TZ, checks output against
  `date` itself rather than a hand-computed string. Also covers turning
  clocks back off (script and wf-shell.ini entry both actually removed).
- **functional/test_customize_idempotent_block.sh** -- re-applies with
  different combinations of extras repeatedly; checks the real
  `wf-shell.ini` never ends up with a duplicated or stale managed block.
  Also checks the Synaptic launcher is wired through `pkexec-wayland`,
  not the raw `synaptic-pkexec` that silently drops the Wayland session.
- **functional/test_backup_restore.sh** -- runs the real
  `backup-user.sh`/`restore-user.sh` against scratch `$HOME` directories
  (no sudo needed, neither script touches anything outside `$HOME`).
  Covers the archive containing only source-of-truth files and nothing
  generated, restoring onto a fresh/differently-located home and having
  it actually re-apply (foot autostart, Synaptic, background image all
  present afterward, not just files copied), round-trip idempotency, and
  a partial (background-only) backup degrading gracefully instead of
  crashing.
- **functional/test_pkexec_wayland.sh** (needs sudo) -- proves the actual
  mechanism against the host's already-running weston: given the
  caller's real `XDG_RUNTIME_DIR`/`WAYLAND_DISPLAY` passed as arguments, a
  process running as root can connect to the caller's compositor. Uses
  `foot`'s own unambiguous "failed to connect to wayland" stderr message
  to tell a real connection apart from a failed one, not just an exit
  code.
- **functional/test_create_users_sudoers.sh** (needs sudo; creates and
  deletes a disposable account) -- the sudoers write-order fix: a failing
  `visudo` must never leave a file in `/etc/sudoers.d/`, and a passing
  one must install something `visudo` itself accepts.
- **functional/test_repo_hygiene.sh** -- sweeps the actual publish
  surface (git-tracked + untracked-but-not-ignored files, from the repo
  root down) for personal identifiers, plus a syntax check on every
  published `.sh` file. The identifier pattern lives in the gitignored
  `install/tests/.personal_pattern` (one `grep -E` pattern, e.g.
  `'alice|bob|alice@example\.com'`), never in a committed file -- with no
  such file present, that half of the check is skipped rather than
  silently checking nothing.
- **functional/test_core_installer.sh** (needs sudo; requires
  `WF_TESTS_ALLOW_SHARED_BOX=1` -- off by default because the account
  picker draws from *every* real account on the box, and a bug in this
  test itself could touch a real one) -- idempotent second run
  (byte-identical, no backup created), `--force-new-user-customizations`
  backing up correctly, all against a disposable throwaway account whose
  index in the installer's own candidate list is computed by exact
  username match, never `'all'`. **Actually run against this project's
  own shared box** (explicit go-ahead given, index verified by hand
  first) -- caught a real bug on the first run: `policykit-1` no longer
  exists as an installable package on this Debian version (split into
  `polkitd`+`pkexec`), which aborted the whole installer under `set -e`
  before it ever reached per-user provisioning. Fixed in
  `10-install-wayfire-desktops.sh`; passes cleanly now.
- **disruptive/test_switch_desktop.sh** (needs sudo, visibly takes over
  the real display -- **never run by an agent except with explicit,
  per-run confirmation, and only when it's first confirmed the agent's
  own session isn't nested inside any live wayfire session** -- otherwise
  only a human, from the host account's own terminal) -- basic switch +
  real logind session, the rapid-double-switch race (regression test for
  the generation-token fix), the switch log's cross-user permission
  isolation, and the forced-crash-triggers-rollback path. **Actually run**
  against a real onboarded `wftest` account, and found two more real bugs
  in the process (both fixed):
  - `switch-desktop.sh` must run as the host account directly -- its own
    documented precondition -- because `systemctl --user stop
    weston...` targets whoever is actually *calling* the script, not
    some named host account. Running it as the wrong user makes that
    call a silent no-op: weston never releases the seat, so the next
    wayfire launch is doomed before it starts -- seatd correctly refuses
    the new client, libseat falls back to its embedded seat backend
    (needs root, can't get it as a regular user), and it hangs for a
    fixed 10s before segfaulting. This is almost certainly what actually
    caused the "wayfire exits after ~10s/93s for no clear reason" mystery
    seen several times earlier in this project's history, now that it's
    fully explained rather than shrugged off as environment flakiness.
    `switch-desktop.sh` now explicitly checks that weston actually
    stopped and fails fast with an actionable message instead of
    proceeding into that failure mode.
  - The switch log's `umask 077` protection (cross-user unreadability)
    had an edge case: `/tmp`'s sticky bit means only a file's *original*
    owner can overwrite it, so a stale log left by a run under the wrong
    user (exactly the scenario above) silently blocked the correct
    user from ever writing their own log at all. Fixed by having
    `switch-desktop.sh` clear its own log and generation-token files
    (via `sudo -n rm`) before writing them, rather than assuming it can
    always just open them for writing.

## Not yet covered (see the earlier design notes below for shape)

- Screenshot-based visual checks (panel position, foot overlap) --
  `grim` + direct visual inspection, not yet scripted.
- Sequential 10x switch cycling for zombie/failed-unit accumulation.
- Portal-timeout regression measurement (wayfire-start to
  panel-layer-shell-configure gap).
- Weather's live geocoding API call (deliberately not exercised --
  `--apply` mode never geocodes, only the interactive prompt does).

## Backup & restore

Implemented (`install/files/backup-user.sh`, `restore-user.sh`) and
covered by `functional/test_backup_restore.sh` above.
