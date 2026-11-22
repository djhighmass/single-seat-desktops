# apps/ -- optional applications

The desktop installer (`install/`) knows nothing about the apps here. It
works with none of them installed. Each app is a choice, installed from its
supplier's own packages, and our default settings for it are a separate
choice on top.

```sh
sudo apps/install.sh --list            # what's available
sudo apps/install.sh                   # asks about each app, then its defaults
sudo apps/install.sh --apps=lxterminal,claude-code --defaults --users=alice,bob
sudo apps/claude-code/install.sh       # one app on its own
apps/lxterminal/defaults.sh            # one app's defaults, for yourself
```

## How an app is laid out

`apps/<app>/install.sh` runs as root and installs the app. The first
`# DESCRIPTION:` line is what the menu shows. Where the supplier publishes
a package or script that sets up its own apt repository and signing key,
we use it rather than copying the repository address or key into this repo.
Where the supplier only documents the steps, we follow them as written,
including any key check.

`apps/<app>/defaults.sh` is optional. It runs as the user it configures
(`apps/install.sh` uses `runuser`), never as root, so everything it writes
belongs to that user. It only adds a setting the user hasn't made: a value
you've set yourself is never replaced. Running it again changes nothing.

`apps/lib/common.sh` has the shared helpers. `apps/tests/run.sh` runs the
tests. The ones that need sudo skip themselves cleanly without it.

## Apps

| App | Source | Our defaults |
|---|---|---|
| `lxterminal` | Debian package `lxterminal` | scrollback of at least 10000 lines (LXTerminal's own default is 1000) |
| `claude-code` | Anthropic's apt repository, set up as their docs describe, with the key fingerprint checked | the classic renderer (`"tui": "default"`), so the terminal's own scrollback works |
