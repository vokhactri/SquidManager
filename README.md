# SquidManager

A menu bar app for running [Squid](https://www.squid-cache.org/) on a Mac. It replaces SquidMan, which bundles Squid 4.13, stops the proxy when you quit it, and is closed source.

I use it to turn a Mac at home into a residential proxy. Squid runs as a launchd agent, so it starts at login, comes back about a second after a crash, and keeps running after the app quits. The app is only a control panel.

## Requirements

- macOS 15 or later
- Squid from Homebrew: `brew install squid`

## Install

Choose a way to install:

- DMG: Download `SquidManager.dmg` from the [latest release](https://github.com/vokhactri/SquidManager/releases/latest), open it and drag SquidManager.app into Applications.
- ZIP: Download `SquidManager.zip` from the same release, extract it and move SquidManager.app into Applications.
- From source: Clone this repo and run `scripts/build-app.sh --install`. See [Build](#build) for details.

The app is signed ad hoc, so Gatekeeper may block a downloaded copy. Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/SquidManager.app
```

## Build

```sh
scripts/build-app.sh            # creates build/SquidManager.app
scripts/build-app.sh --install  # also copies it to /Applications
scripts/make-dmg.sh             # packs the built app into build/SquidManager.dmg
scripts/test.sh                 # runs the tests, including `squid -k parse` on generated configs
scripts/format.sh               # formats and lints the code to the Airbnb Swift Style Guide
scripts/format.sh --lint        # only reports problems, changes nothing
```

The app takes its version from the latest `v*` tag. A build from a commit past the tag gets a suffix, such as `0.2.0-3-gabc123`, and the updater treats it as `0.2.0`.

## Releasing

```sh
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow runs the tests, builds the app, checks that it starts as version 0.2.0 and attaches `SquidManager.dmg` and `SquidManager.zip` to a new GitHub release. The CI workflow runs the tests, the linter and a build on every push to `main` and on pull requests.

Xcode is not required, only the Command Line Tools. Keep it that way when changing the UI. In the macOS 27 SDK, `@State` is a macro, and its plugin (`SwiftUIMacros`) ships only with Xcode. Views keep local state in a small `ObservableObject` held by `@StateObject` instead. The same applies to `#Preview`, `@Previewable` and `@Entry`.

## What it does

- Generates `squid.conf` from an editable template, as SquidMan does, then checks it with `squid -k parse` before starting.
- Starts Squid with `launchctl bootstrap` under the label `com.squidmanager.squid`. Pressing Stop runs `launchctl bootout` and deletes the agent, so a stopped proxy stays stopped after a reboot.
- Wraps Squid in `caffeinate -i -s` so the Mac does not idle-sleep while the proxy runs. A laptop with the lid closed still sleeps unless it is on power with an external display.
- Hides the proxy from the sites you visit. It sends no `Via` header, strips `X-Forwarded-For`, and drops `Cache-Control`. Squid otherwise adds `Cache-Control: max-age=259200` to every request, which gives the proxy away.
- Lets clients in two ways. Addresses on the allow list (a Tailscale peer, say) connect without a password. Everyone else needs a user name and password if authentication is on. Users are stored as `$apr1$` hashes and changes apply without a restart.
- Optionally forwards everything through a parent proxy, with a list of hosts that go direct.
- Shows the access log, cache log, launchd output and the generated `squid.conf`, and can rotate logs and flush the cache.
- Notices when `brew upgrade squid` installs a new version. The running squid keeps the old binary until it restarts, so the app offers a restart.
- On first launch, imports the port, allowed clients, parent proxy and direct hosts from SquidMan's preferences.

## Command line

The app binary also takes commands, which is useful over SSH:

```sh
SM=/Applications/SquidManager.app/Contents/MacOS/SquidManager
$SM status    # running pid 1234 port 3128, plus the addresses clients should use
$SM start
$SM stop
$SM restart
$SM rotate
$SM update    # installs the latest release; a running app keeps the old version until reopened
```

## Files

Config and logs live in `$XDG_CONFIG_HOME/squidmanager`. If the variable is unset or not an absolute path, they go in `~/.config/squidmanager`. An app opened from Finder doesn't see variables set in your shell profile, so it uses `~/.config` even if your shell sets `XDG_CONFIG_HOME` to something else.

| Path                                                  | Contents                                              |
| ----------------------------------------------------- | ----------------------------------------------------- |
| `~/.config/squidmanager/`                             | `squid.conf`, `passwd`, `squid.pid`, `.gitignore`     |
| `~/.config/squidmanager/logs/`                        | `access.log`, `cache.log`, `stderr.log`               |
| `~/Library/Caches/SquidManager/`                      | disk cache (off by default)                           |
| `~/Library/LaunchAgents/com.squidmanager.squid.plist` | the launchd agent, present only while the proxy is on |

The app writes `.gitignore` the first time it creates the folder, with `logs/` and `squid.pid` in it, so a dotfiles repo can track the folder without picking up logs. If a `.gitignore` is already there, the app leaves it alone.

Squid's config parser splits on spaces, so none of these paths can contain one.

## Moving from SquidMan

SquidMan keeps its own Squid on the same port. Quit SquidMan and stop its Squid (in SquidMan, press Stop Squid), then press Start here. If the port is still taken, SquidManager tells you which process holds it.

## License

MIT, by Tri Vo Khac. Squid itself is GPL-2.0 and is installed separately through Homebrew.
