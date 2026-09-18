# single-seat-desktops

Android's Linux Terminal (crosvm) gives you exactly one virtual seat — one
display path, one set of input devices — with no way to have separate
desktop sessions for different accounts or contexts natively. This
installer works around that constraint on a Debian Linux Terminal VM:
one "host" account stays on weston as the permanent stable base, and
every other onboarded account gets its own real-hardware `wayfire`
compositor, switched to one at a time via a `<user>-wayfire` alias.

This is **convenience isolation between trusted accounts sharing one
physical device**, not a security boundary — every onboarded user gets
`video`/`render` group access and can own the real display. Don't onboard
an account you don't trust with that.

## Requirements

- Debian-based Linux Terminal VM (developed against Debian 13 "trixie").
- A host account that normally owns the display via weston (default
  `droid`, the Terminal app's default account) with working sudo.
- Physical/dock keyboard+mouse+monitor for anything beyond the phone's own
  screen — not required to run the installer itself.

## Usage

```sh
cd install

# 1. Make sure every account you want exists. Skips accounts that
#    already exist without touching them.
sudo ./00-create-users.sh alice bob carol

# 2. Wire up whichever of those accounts you want as wayfire desktops.
sudo ./10-install-wayfire-desktops.sh
```

`10-install-wayfire-desktops.sh` sets up the **core desktop only** — enough
for a working, switchable session with a panel, background, policy agent,
and app menu. It deliberately does not ask about a terminal, weather,
clocks, or the Synaptic launcher: those are personal taste, not core
plumbing, so every onboarded user gets a **Customize Desktop** entry in
their own app menu to pick whichever of those they personally want,
whenever they want (see below). Concretely, the core installer will:

1. Install prerequisites (`wayfire`, `wf-shell`, `foot`, `seatd`, `grim`,
   `jq`, `curl`, plus everything the shared tools below need — `yad`,
   `synaptic`, `lxpolkit`, `policykit-1` — installed for everyone up
   front so nothing later ever needs root) and start `seatd`,
   auto-detecting which group it actually runs as rather than assuming
   `video`.
2. Install a polkit rule so every user authenticates as themselves
   (`49-self-auth.rules`), and two app-menu tools available to *every*
   onboarded user automatically, system-wide, needing no root to run:
   **Change Background** (a `yad` file-browse dialog) and **Customize
   Desktop** (`wayfire-customize.sh`, described below).
3. Ask which existing account is the host (stays on weston).
4. List every other real account and let you pick which to onboard.
5. For each one: group membership, linger, a timezone, and a minimal
   `wayfire.ini`/`wf-shell.ini` — that's it.
6. Deploy `/usr/local/bin/switch-desktop.sh` and wire a `<user>-wayfire`
   alias into the host's `.bash_aliases` for each onboarded account.

### Personal customization

Any onboarded user can run `wayfire-customize.sh` themselves (no root
needed — from their own app menu's **Customize Desktop** entry, or
directly from a terminal) to pick:

- an autostart terminal (`foot`, sized `quarter`/`full`/a literal
  `WIDTHxHEIGHT` -- `quarter` resolves against whatever the connected
  output's actual current mode is, so it means the same thing on any
  screen instead of requiring you to work out pixel counts yourself)
- a weather widget (geocoded from a place name you type)
- extra clock widget(s) (repeatable `LABEL TZ` entries — one
  second-timezone clock, or a whole world clock row)
- the Synaptic package-manager launcher

Their answers are saved to `~/.config/wayfire-customize.conf`, so running
it again re-applies (or lets them change) the same setup — handy for
rebuilding a personal environment from scratch after
`--force-new-user-customizations` resets the core files, or on a fresh
account. `wayfire-customize.sh --apply` re-applies saved answers with no
prompts; `--show` prints them.

### Backup and restore

`backup-user.sh [output-file]` bundles the account's source-of-truth
preferences -- `wayfire-customize.conf`, `timezone`, and `background.png`
if set -- into one portable archive (default:
`~/wayfire-backup.tar.gz`). Nothing generated (the weather-fetch script,
the extra-clock script, `wf-shell.ini`'s managed block) is included --
those are derived from the conf file and get rebuilt by re-applying it,
so backing them up too would be redundant and could drift from whatever
templates the installer ships as it evolves.

`restore-user.sh <archive>` restores one onto any onboarded account (core
must already be installed for it) and re-applies it immediately. Nothing
in the archive references a username or home path, so restoring onto a
different account than the backup came from, or onto entirely new
hardware after copying the archive off-device (Google Drive, another
device, wherever), works the same way. Neither script needs root.

Then, **from the host account's own terminal** (not sudo'd into anything):

```sh
alice-wayfire   # whichever <user>-wayfire alias you set up
```

This stops weston and starts that user's own wayfire compositor directly
on the real display, and drops you into a `sudo su - <user>` shell in the
same breath. Exiting that shell does **not** kill the compositor — it
keeps running (that's what `loginctl enable-linger` is for). To switch to
someone else, just run another `*-wayfire` alias from the host's terminal.
To go back to the plain shared weston desktop, restart it yourself as the
host: `systemctl --user start weston.socket weston.service`.

## Re-running / idempotency

Safe to re-run any time. What happens on a second run differs by step:

- **Always reapplied** (safe no-ops if nothing changed): package
  installs, `seatd` enablement, the polkit rule, the shared app-menu
  tools, group membership, `loginctl enable-linger`, the deployed
  `switch-desktop.sh`, and the host's `*-wayfire` aliases. Re-running
  picks up any improvements to `files/switch-desktop.sh` without
  touching per-user config.
- **Only generated once**: a user's core `wayfire.ini`, `wf-shell.ini`,
  and timezone file. If a user already has a `~/.config/wayfire.ini`,
  the installer leaves their core desktop exactly as it is rather than
  re-prompting and clobbering it. Their `wayfire-customize.sh` choices
  live in a separate file and are never touched by this script either
  way.

To force a specific reconfiguration pass (e.g. a different timezone),
re-run with:

```sh
sudo ./10-install-wayfire-desktops.sh --force-new-user-customizations
```

This resets the named user(s)' core files — each existing file is backed
up first as `<file>.bak-<timestamp>`, never silently discarded — and
they'll need to run `wayfire-customize.sh` again afterwards (it'll offer
their previous answers as defaults) to reapply their personal extras on
top of the fresh base.

## Why some of this looks the way it does

A few non-obvious things this installer bakes in, each the product of
real debugging (see `wayfire-multiuser-desktop-checkpoint.md` in the
parent project for the full history):

- **`loginctl enable-linger` is mandatory, not optional.** Without it,
  `systemd-logind` tears down a user's `/run/user/<uid>` the moment their
  last login session (e.g. the `sudo su - <user>` shell the alias drops
  you into) exits — even though their `wayfire` process itself is still
  running. Already-connected clients (like a terminal launched at
  startup) keep working off their existing socket fd, but anything that
  tries to connect *after* that point (the panel, a newly launched app)
  silently fails with "no wayland display."
- **`switch-desktop.sh` must be run by the host account directly, never
  via `sudo <script>`.** Wrapping the whole script in `sudo` strips the
  host's own systemd `--user` D-Bus session, which is needed to stop and
  restart `weston.socket`/`weston.service`.
- **wayfire is launched via `systemd-run -p PAMName=login`, not plain
  `sudo -u <user> wayfire`.** A plainly-sudo'd process has no logind
  session at all (`sd_pid_get_session()` on it returns nothing), and
  without one, `pkexec` can't find the target user's own `lxpolkit`
  registered as an authentication agent for that (nonexistent) session.
  It falls back to a text-mode prompt that tries to read from the
  invoking shell's leftover controlling terminal -- which it isn't the
  foreground process group of, so the kernel just parks it forever in
  stopped state. That's what "invalid session for pid" and apps hanging
  when they ask for a password (Synaptic, `pkexec` anything) turn out to
  be. `-p PAMName=login` gives the session a real id, which is enough for
  `pkexec` to route through the GUI agent instead.
- **A polkit rule (`49-self-auth.rules`) makes every user their own
  admin.** Every onboarded account is in the `sudo` group, so without
  this rule `pkexec` has several valid "admin" identities to choose from
  and asks the caller which one to authenticate as -- confusing on a
  single-seat multi-user box, and exactly what "asks in the terminal what
  user to run as" was.
- **`switch-desktop.sh` stops any other onboarded user's `wayfire-*`
  systemd unit before starting the new one.** seatd only lets one client
  hold the seat at a time; switching straight from one user's session to
  another's without an explicit handoff step risks the new compositor
  being refused the seat, or leftover state from the old one bleeding
  into the new session.
- **The DRM connector-stabilization wait** exists because this
  environment's display isn't a real EDID-negotiated hardware connector —
  it's virtio-gpu output mirroring whatever Android window currently
  hosts the Terminal app, which can renegotiate mode a few times right as
  an external monitor attaches. Launching a compositor mid-flap crashes
  its early Wayland clients.
- **Root-launched GUI apps go through `pkexec-wayland`, never plain
  `pkexec`.** `pkexec` resets almost the entire environment before
  exec'ing as root -- it only conditionally keeps `DISPLAY`/`XAUTHORITY`
  (and only because the action sets `allow_gui`), never
  `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`. A native-Wayland GTK app run this
  way falls back to X11/Xwayland, which doesn't expose a usable
  Xauthority cookie to outside processes here either -- so it fails
  GTK init with "Authorization required" and never shows a window at
  all, with no obvious error at the point you clicked the launcher.
  `pkexec-wayland` threads the caller's `WAYLAND_DISPLAY`/
  `XDG_RUNTIME_DIR` through as plain arguments (pkexec strips
  environment, not argv) via its own polkit action and a small root-side
  helper that re-exports them before exec'ing the real command. It's
  generic -- any future root-needing GUI launcher can reuse it, not just
  Synaptic.
- **Core plumbing and personal taste are deliberately separate
  scripts.** The root-run core installer has no opinion on whether you
  want weather or a launcher bar full of icons; `wayfire-customize.sh`
  runs as the user it affects, needs no root (every package it could
  possibly need was already installed by core), and is exposed the same
  way to every account via a system-wide `.desktop` entry rather than a
  per-user copy — so onboarding a new account doesn't mean re-answering
  someone else's preference questions, and a user can rebuild their own
  setup from `~/.config/wayfire-customize.conf` any time without needing
  the installer at all.
- **`wf-panel`/`wf-background` read `~/.config/wf-shell.ini`, not
  `wayfire.ini`.** They're a separate GTK application (`wf-shell`) with
  their own config file and their own `wf-config` parser; nothing you put
  in `[panel]` inside `wayfire.ini` has any effect.
- **`<alt>` instead of `<super>` for move/resize.** The Super/Meta key
  never reaches the guest at all through this dock/USB-HID/crosvm input
  chain — confirmed with `wev`. This is an Android Linux Terminal quirk,
  not a general Linux desktop assumption.
- **No GPU acceleration is available at all on this hardware/OS
  combination** (Pixel 9-class devices) — Google's Gfxstream passthrough
  for the Linux Terminal app is hard-gated to Pixel 10 only. `pixman`
  (CPU rendering) plus `WLR_NO_HARDWARE_CURSORS=1` and
  `WLR_DRM_NO_ATOMIC=1` is the best available software-rendering path,
  not a workaround for a fixable bug.

## Layout

```
install/
  00-create-users.sh              pre-script: adduser for missing accounts
  10-install-wayfire-desktops.sh  core installer (no personal-taste prompts)
  lib/common.sh                   shared shell helpers
  files/
    switch-desktop.sh             deployed to /usr/local/bin
    49-self-auth.rules            deployed to /etc/polkit-1/rules.d
    wayfire.ini.tmpl              core per-user compositor config (minimal)
    panel-*.sh                    static panel widget scripts (core)
    wayfire-customize.sh          deployed to /usr/local/bin -- run by any
                                   user, for themselves, no root needed
    wayfire-customize.desktop     deployed once to
                                   /usr/local/share/applications -- every
                                   user's app menu picks it up automatically
    backup-user.sh                deployed to /usr/local/bin -- CLI only,
                                   no app-menu entry
    restore-user.sh               deployed to /usr/local/bin, same pattern
    owf-update-weather.sh.tmpl    weather fetcher template, deployed to
                                   /usr/local/lib/wayfire-customize -- read
                                   by wayfire-customize.sh, lat/lon filled
                                   in per user at customize time
    panel-weather.sh              weather panel script, same deployment
    owf-weather.service/.timer    systemd --user units, same deployment
    set-background.sh             deployed to /usr/local/bin -- GUI (yad)
                                   wallpaper picker + restart, shared
    set-background.desktop        deployed once, same pattern as
                                   wayfire-customize.desktop
    pkexec-wayland                deployed to /usr/local/bin -- generic
                                   wrapper for launching a root GUI app
                                   without losing the Wayland session
    pkexec-wayland-helper         deployed to /usr/local/bin -- root side
                                   of pkexec-wayland, re-exports the
                                   caller's Wayland env before exec'ing
    local.pkexec-wayland.policy   deployed to /usr/share/polkit-1/actions
    portal-timeout.conf           deployed to
                                   /etc/systemd/user/<unit>.d/override.conf
                                   for the three xdg-desktop-portal units
```
