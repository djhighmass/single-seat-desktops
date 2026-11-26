# apps/ -- optional applications

Each app is optional. Default settings are a separate per-user step. The
desktop installer (`install/`) doesn't need any of this.

```sh
apps/install.sh --list                                      # needs no root
sudo apps/install.sh lxterminal claude-code google-chrome   # name the ones you want
apps/defaults.sh lxterminal claude-code                     # as each user, before first opening LXTerminal
```

Each account needs a readable copy of `apps/`.

| App | Source |
|---|---|
| `lxterminal` | Debian package `lxterminal` |
| `claude-code` | Anthropic's apt repository (stable channel), through `extrepo` |
| `google-chrome` | Google's apt repository, through `extrepo` |

Apps are installed in the order named, and the first failure stops the run.

## Third-party repositories

[`extrepo`](https://packages.debian.org/trixie/extrepo), a Debian package,
supplies these repositories and their keys, checking its catalogue's signature
and each key's checksum; we keep no addresses or keys. Both need its
"non-free" policy. The installer enables it in `/etc/extrepo/config.yaml`; it
stays on, for other non-free entries too. If a supplier's key changes, see
`extrepo update` in `man extrepo`.

## Scope

For a **freshly set-up machine**: existing setups aren't merged or repaired.
The guards below cover what the two scripts do, not what apt or package install
scripts do.

- An installed `claude-code` or `google-chrome-stable` package is left alone.
- An existing `extrepo` repository file is used as it is. `extrepo enable`,
  which would rewrite it, isn't run.
- First setup of Chrome's repository overwrites `/etc/default/google-chrome`
  (`extrepo`'s 10-second warning about this is expected). If the file already
  exists then, the installer stops.
- `/etc/extrepo/config.yaml` is read only when setting up a repository. With a
  `- non-free` line, it isn't changed. Otherwise only the shipped
  `# - non-free` line is uncommented; without that line, the installer stops.
- If setting up a repository, or installing from it, fails (e.g. you had added
  it by hand with a different key setting, which breaks apt), the installer
  removes the repository file and Chrome's defaults file, each only if this run
  created it and `dpkg` shows the package as absent or with only config files
  left. The policy change, `extrepo`'s copy of the key and installed packages
  stay.
- `apps/defaults.sh` only creates files. Anything already there is left alone,
  and it says what to change by hand.

## Defaults

`apps/defaults.sh` runs as the user it configures, never root. It configures
the apps you name, skipping any not found on `PATH`:

- **LXTerminal** gets 10000 lines of scrollback. It creates its own config on
  first start; once that exists, change it by hand.
- **Claude Code** gets the classic renderer (`"tui": "default"`), so the
  terminal's own scrollback keeps working
  ([docs](https://code.claude.com/docs/en/fullscreen)).

It exits non-zero if a settings file couldn't be written. `backup-user.sh`
doesn't save these defaults, so run `apps/defaults.sh` again after a restore.

## Maintaining

Each app is a folder; both runners list the folders themselves.

- `<app>/install.sh` (required): calls helpers from `lib.sh`, such as
  `apt_install` or `from_extrepo`, and `log`/`warn`/`die` from
  `install/lib/common.sh`. A step that fails must stop the run: those two
  helpers do; otherwise add `|| die`.
- `<app>/defaults.sh` (optional): calls `new_default`, from `defaults.sh`.

Both files are sourced, not run. Names use lowercase letters, digits and
hyphens. For a new app, also add a row to the table above, and tests.

Test with `bash apps/tests/test_apps.sh`, also run by
`install/tests/run.sh functional`. apt, dpkg and extrepo are stubbed; checking
the real ones takes a real install. Installer checks past argument handling, and
the check that defaults refuse root, need root or passwordless sudo. The check
that the installer needs root, and the other defaults checks, need a non-root
user; the one that another user can't read Claude Code's settings also needs
passwordless sudo. Skipped checks are reported. The dev
container (`install/tests/test-in-container.sh`) can run them all.
