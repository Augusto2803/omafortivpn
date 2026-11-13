# FortiVPN for Omarchy

A FortiGate SSL VPN indicator for the [Omarchy](https://omarchy.org/) bar,
built on [openfortivpn](https://github.com/adrienverge/openfortivpn).

The icon **stays in the bar**, dimmed while disconnected and lit while the
tunnel is up. Middle click connects or disconnects the default profile; left
click opens a panel with the tunnel's state, your profiles, and what can be
done with them. Connecting itself happens in a floating terminal, because that
is where the password and the 2FA token get typed.

| | |
|---|---|
| Plugin id | `omafortivpn` |
| Kind | `bar-widget` |
| Requires | Omarchy 4, `openfortivpn`, `jq`, `openssl`, `gum` |

## Why it works this way

Authentication with 2FA needs a human typing a token that rotates every 30
seconds. That does not fit in a config file, and it does not fit in a systemd
unit that starts at boot. So:

- **Connect** opens a floating terminal to collect the password and the token,
  because a terminal is the only place to ask for them. It then starts
  `openfortivpn` as a transient systemd unit and closes as soon as the tunnel
  is up. The window holds nothing the connection needs — the tunnel outlives
  it, and `fortivpn down` is what ends it.
- The secrets reach the detached process through a sanitized copy of the
  profile with `password` and `otp` appended, piped to root and written by root
  to `/run/fortivpn/<name>.conf` (tmpfs, root-only directory, mode 600). The
  profile is yours to edit, so root never takes it as-is: it is read once and
  every line must be a comment or an allowlisted `key = value` (see
  [Profile keys](#profile-keys)), re-rendered, and only that is piped. The file
  is deleted as soon as the handshake settles, and again by the unit when the
  tunnel stops; the profile itself never gains a password it did not already
  have.
- The handshake is logged to `/var/log/fortivpn/<uid>/<name>.log`, created by
  root and readable by your group, shown live in the window while it connects
  and left behind for when it fails. Its first error is what the failure
  notification and the panel quote as the reason.
- Nothing root reads or writes for the tunnel sits at a path you own, so
  nothing running as you can swap a file out between the sudo prompt and the
  moment root uses it.
- **Disconnect** sends `SIGINT`, which is openfortivpn's clean shutdown: it
  removes the routes and the DNS registration before exiting. It only targets
  processes running as root, so a process of yours that fakes the command line
  is neither signalled nor mistaken for a live tunnel.
- The bar widget only **reads** state — does the `fortivpn0` interface have an
  address? — so it needs no privilege at all.

## Install

```bash
omarchy plugin add https://github.com/Augusto2803/omarchy-fortivpn.git --enable
```

That is enough for the bar widget. To also get the `fortivpn` command on your
`PATH` and the **VPN** section in the Omarchy menu, run the installer from the
plugin directory:

```bash
~/.config/omarchy/plugins/omafortivpn/install.sh
```

Or, from a clone anywhere on disk, `./install.sh` does both steps at once. It
copies the plugin into `~/.config/omarchy/plugins/`, links the command, enables
the widget, and merges the menu entries.

It prints every file it will change and asks before touching any of them, so
you can say no. `--yes` accepts without prompting (and is required when there
is no terminal to ask in), `--no-menu` skips the menu entries, and `--link`
symlinks instead of copying for development. Re-running it is safe: it replaces
its own menu block rather than duplicating keys, and leaves a widget you have
already positioned where it is. [`uninstall.sh`](#uninstall) reverses all of it.

## First profile

```bash
fortivpn new
```

The wizard asks for a name, gateway host, port, and username, writes
`~/.config/fortivpn/profiles/<name>.conf` at mode 600, and offers to pin the
gateway's certificate. Non-interactively:

```bash
fortivpn new work --host vpn.example.com --username your.user
fortivpn trust work
```

`fortivpn trust` reads the certificate chain the gateway sends and checks it
against the system trust store, including that it is valid for the profile's
host. If it verifies, the leaf's SHA256 digest is pinned as `trusted-cert`.
That is the same value openfortivpn prints after refusing an unknown
certificate on a first connection — this just gets it out of the way
beforehand.

Self-signed gateways (common for FortiGate) cannot be verified that way. For
those, `fortivpn trust` shows the subject, issuer, validity dates and SHA256
fingerprint, and pins only after you confirm. Compare the fingerprint with your
VPN administrator over a channel other than the connection itself. Without a
terminal it refuses; pass `--accept-unverified` (after checking the fingerprint)
to pin non-interactively. A `trusted-cert` that is not a 64-character hex digest
can never match, and is reported and replaced the next time you pin.

Skip it and your first connection will fail with a certificate error, which is
expected; run `fortivpn trust <profile>` then and reconnect.

One `.conf` per gateway. See [`config/profile.conf.example`](config/profile.conf.example)
for every option with commentary.

### Profile keys

A profile is a plain openfortivpn config, but the connect step only passes
these keys to the root process, and refuses the profile (naming the key and
line, before any `sudo` prompt) on anything else: `host`, `port` (1–65535),
`username`, `password`, `trusted-cert` (repeatable; each must be 64 lowercase
hex digits), `realm`, `set-dns`, `use-resolvconf`, `set-routes`,
`half-internet-routes`, `pppd-use-peerdns`, `pppd-accept-remote`,
`insecure-ssl`, `seclevel-1`, `no-ftm-push` (all `0` or `1`), `cipher-list`
and `min-tls`. Comments and blank lines are fine.

Deliberately refused: `pppd-plugin`, `pppd-call`, `pppd-ipparam`, `pppd-log`
and `pinentry` (make a root process load, run or write something of your
choosing); `pppd-ifname` (the plugin sets it); `ca-file`, `user-cert`,
`user-key`, `pem-passphrase` (root would read a file you own — client
certificates are not supported); `otp` (typed at connect time), `cookie` and
`persistent`. Control characters and carriage returns in a line are rejected.
At the prompt, the 2FA token must be 4–128 letters, digits or hyphens (or
empty), and the password cannot contain a line break.

## Usage

From the bar icon, a panel:

- **Header**: state, address and uptime, the live profile, and a switch that
  connects the default profile or disconnects.
- **Profiles**: click one to connect to it. Each row offers *make default*,
  *pin certificate* (only while none is pinned), and *edit*.
- **New profile** and **Connection log**.
- When the last tunnel dropped or failed, the panel says so, when, and why.

The keyboard works too: arrows or `j`/`k` move, `Enter` activates, `r`
re-reads, `n` creates a profile, and on a profile row `s` makes it the
default, `p` pins its certificate, `e` edits it. `Tab` moves to the
neighbouring panel in the bar.

A tunnel that drops on its own — the gateway stops answering pppd's echo
requests — is announced with a notification, once, naming the reason.

The panel follows the language set under Setup > Language; English and
Brazilian Portuguese ship in [`i18n/`](i18n/).

From the Omarchy menu (`Super`), under **VPN**: Connect, Disconnect, Status
(opens the panel), and a **Profiles** submenu with Set Default, New, Edit,
Pin Certificate, Rename, and Delete.

From the terminal:

```
Connection
  fortivpn up [profile]        Connect in a floating terminal (password + 2FA token)
  fortivpn down                Disconnect, tearing down routes and DNS cleanly
  fortivpn toggle [profile]    Connect when down, disconnect when up
  fortivpn status [--json]     Profile, tunnel address, uptime
  fortivpn is-up               Exit 0 while the tunnel is up
  fortivpn log [profile]       Read the handshake log of the last attempt

Profiles  (~/.config/fortivpn/profiles/<name>.conf, mode 600)
  fortivpn list                List profiles
  fortivpn new [name] [opts]   Create a profile  (--host --port --username --dns-domain --split-tunnel)
  fortivpn edit [profile]      Open a profile in $EDITOR
  fortivpn dns <profile> <domain...>
                               Route private DNS zones through this VPN
  fortivpn delete [profile]    Delete a profile  (--yes to skip the prompt)
  fortivpn rename <old> [new]  Rename a profile
  fortivpn use [profile]       Set the default profile
  fortivpn trust [profile]     Verify and pin the gateway's certificate (--accept-unverified)
```

Omitting `[profile]` opens a `gum` picker when there is a terminal to show it
in, and falls back to the default profile everywhere else.

On the bar icon: **left click** opens the panel, **middle click** toggles the
tunnel (connect the default profile, or disconnect), **right click** forces a
re-read.

`fortivpn status --json` is what the widget consumes:

```json
{"state":"disconnected","profile":"","ip":"","iface":"fortivpn0","uptime":0,
 "default":"work","profiles":[{"name":"work","host":"vpn.example.com","default":true,"pinned":true}],
 "error":"No response to 4 echo-requests","errorKind":"dropped","errorProfile":"work","errorAt":1793970611}
```

`state` is one of `disconnected`, `connecting`, `connected`. The `error*`
fields describe how the most recent tunnel ended, and are only filled in while
disconnected and when it ended badly: `errorKind` is `dropped` for a tunnel
that came up and went away, `failed` for one that never got through the
handshake. A clean `fortivpn down` leaves them empty.

## Widget settings

In `~/.config/omarchy/shell.json`, on the widget's layout entry:

```json
{ "id": "omafortivpn", "refreshIntervalSec": 5, "alwaysShow": true }
```

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `5` | How often state is re-read. During a connection in progress the widget re-reads every second on its own. |
| `alwaysShow` | `true` | Keep the icon in the bar while disconnected, dimmed. Set to `false` to show it only while a tunnel is up. |

The widget also registers an IPC target, for keybindings and scripts:

```bash
omarchy-shell omafortivpn toggle        # open or close the panel
omarchy-shell omafortivpn toggleTunnel  # connect the default profile, or disconnect
omarchy-shell omafortivpn connect
omarchy-shell omafortivpn disconnect
omarchy-shell omafortivpn refresh
```

`open` and `close` are there too. With `alwaysShow` off, the panel opens even
while the icon is hidden, and the icon stays until it closes.

## DNS

Omarchy runs `systemd-resolved`, and `/usr/bin/resolvconf` is the `resolvectl`
shim. With `use-resolvconf = 1` in the profile, the gateway's DNS servers and
search domains are registered against `fortivpn0`, instead of overwriting
`/etc/resolv.conf`.

Some networks use private DNS zones that the gateway does not advertise as
search domains. Those names otherwise go to the Wi-Fi DNS and fail. Configure
each such zone once per profile:

```bash
# Existing profile; applies immediately when this profile is connected.
fortivpn dns work unimedsc.coop.br

# New profile; repeat --dns-domain for more than one zone.
fortivpn new work --host vpn.example.com --username your.user \
  --dns-domain unimedsc.coop.br
```

The command stores `# dns-routing-domain = …` comments in the profile, so
openfortivpn still accepts the file unchanged. Once the tunnel is connected,
the plugin adds each zone as a route-only domain (`~zone`) on `fortivpn0`,
preserving the gateway-provided search domains. It also flushes DNS cache, so
the previously failed name is retried through the VPN immediately.

To inspect the live resolver state:

```bash
resolvectl status fortivpn0
resolvectl query dataflow.unimedsc.coop.br
```

## The sudo password

Four commands in this plugin cross a privilege boundary, and these are them in
full:

```bash
# Connect — sudo prompts in the floating terminal. The transient config is
# piped to root and the log created by root, both in root-owned directories;
# then the tunnel is handed to PID 1
sudo install -d -m 0700 -o root -g root /run/fortivpn
<profile + password + otp> | sudo install -m 0600 -o root -g root /dev/stdin /run/fortivpn/<name>.conf
sudo install -d -m 0750 -o root -g <your gid> /var/log/fortivpn/<uid>
sudo install -m 0640 -o root -g <your gid> /dev/null /var/log/fortivpn/<uid>/<name>.log
sudo systemd-run --quiet --collect --unit=fortivpn-tunnel \
  --property=Type=exec --property=KillSignal=SIGINT \
  --property=Restart=no --property=TimeoutStartSec=30 --property=TimeoutStopSec=30 \
  --property=ProtectHome=yes --property=PrivateTmp=yes \
  --property=ProtectSystem=full --property=ReadWritePaths=-/etc/resolv.conf \
  --property=NoNewPrivileges=yes --property=UMask=0077 \
  --property=StandardOutput=append:/var/log/fortivpn/<uid>/<name>.log \
  --property=StandardError=append:/var/log/fortivpn/<uid>/<name>.log \
  --property=ExecStopPost="/usr/bin/rm -f -- /run/fortivpn/<name>.conf" \
  /usr/bin/openfortivpn -c /run/fortivpn/<name>.conf --pppd-ifname=fortivpn0

# Once the handshake settles — same sudo timestamp, no prompt
sudo -n rm -f -- /run/fortivpn/<name>.conf

# Split DNS (only for profiles with dns-routing-domain) — reuses the sudo
# timestamp the connect just primed, so it costs no extra prompt
sudo resolvectl domain fortivpn0 <gateway search domains> ~<zone>...
sudo resolvectl flush-caches

# Disconnect — sudo -n when a cached credential allows it, pkexec otherwise
pkill -U 0 -INT -f -- '^(/[^ ]*/)?openfortivpn( .*)? --pppd-ifname[= ]fortivpn0( |$)'
```

Nothing else needs root: creating, editing, deleting and pinning profiles never
do, and the bar widget only reads whether `fortivpn0` has an address.

`Connect` runs in a terminal, so `sudo` asks for the password right there,
once: the split-DNS step rides on the same sudo timestamp. Run unprivileged,
each `resolvectl` call would be a polkit dialog of its own, because resolved's
`auth_admin_keep` grant covers only the process that asked for it. Without a
sudo credential or a terminal to ask on, it falls back to exactly that.
`Disconnect` has no terminal: it uses `sudo -n` when it can and falls back to
`pkexec` (the polkit dialog) otherwise.

**Why `systemd-run` and not just `sudo openfortivpn &`.** Since sudo 1.9.14,
`use_pty` is the default: sudo runs its command in a pseudo-terminal, and when
that command exits it tears the pty down and kills whatever is left in its
session. A tunnel detached with `setsid` under sudo is therefore killed before
it writes its first line — which looks exactly like a connection that failed
for no reason at all. `systemd-run` sidesteps it: sudo only asks PID 1 to start
a transient unit and returns, and the tunnel belongs to systemd, outliving both
sudo and the window. `Type=exec` makes that ask wait until `openfortivpn` has
actually been exec'd, so a launch that never got off the ground is reported
here rather than as a process that mysteriously fails to appear.

The tunnel's unit is sandboxed, since it is a network-facing parser running as
root: no `/home` (`ProtectHome`), a private `/tmp`, `/usr`, `/boot` and `/etc`
read-only (`ProtectSystem=full`, with `/etc/resolv.conf` left writable for
profiles that set `use-resolvconf = 0`), `NoNewPrivileges`, `UMask=0077`, no
restart (a restart would reuse a spent token), and start/stop timeouts.

Disconnecting describes its target **by pattern**, inside the privileged call,
rather than looking up a PID first and handing that number to `sudo`. A PID
looked up a moment earlier can be recycled onto an unrelated process, and the
signal would then land on it as root. Resolving the target at signal time closes
that window.

The pattern is deliberately narrow. It is anchored at the start of the command
line, so the `sudo openfortivpn …` parent and any other program that merely
mentions the flag do not match, and it requires the interface this plugin
starts its own tunnels on — so a second user's tunnel, or one of your own on
another interface, is never signalled. `-U 0` restricts it to processes whose
real UID is root, which is what systemd starts the tunnel as: a process of
yours that copies the command line can neither receive the signal as root nor
make `status` report a tunnel that is not there.

People often ask how to make the password prompt go away with a `NOPASSWD`
sudoers rule. **This plugin does not ship one and does not recommend writing
one.** `openfortivpn` accepts `--pppd-plugin`, which loads an arbitrary shared
object as root, so a passwordless rule on that binary hands every process
running as you a route to root. Pinning the exact command line narrows it, but
profiles live in your home directory and are writable by you, so the config
that rule points at is still attacker-controlled unless you also move it to a
root-owned path. Two prompts per session is a reasonable price; if you disagree,
read `sudoers(5)` and `openfortivpn(1)` in full and own the consequences.

## Known limitations

- **No automatic reconnect.** openfortivpn's `--persistent` is deliberately
  left out: with 2FA, a reconnect would need a fresh token, and by then there is
  no terminal left to type one in. If it drops, you reconnect.
- **One tunnel at a time, on `fortivpn0`.** Status, uptime and disconnect all
  match openfortivpn processes started with `--pppd-ifname=fortivpn0`, and take
  the first. A tunnel on another interface is invisible here — deliberately, so
  this plugin never touches one it did not start. `Connect` refuses while a
  handshake for this interface is already in flight.
- **Username + password (+ 2FA) only.** For SAML/SSO, openfortivpn has
  `--saml-login`; the connect path would need that flag and the browser would
  become part of the login.

## Tests

```bash
tests/run.sh
```

Plain bash, offline, no `sudo`: it checks the profile allowlist, the port and
token validators, the disconnect pattern, and `fortivpn trust` against
throwaway local TLS servers (needs `openssl`). It uses a temporary `HOME`, so
your profiles are never read. The trust model it guards is in
[SECURITY.md](SECURITY.md).

## Uninstall

```bash
~/.config/omarchy/plugins/omafortivpn/uninstall.sh
```

It disconnects an open tunnel first, removes the bar widget, the `fortivpn`
symlink, and the menu block, and tells you where everything it left behind is.
Your profiles survive by default.

| Flag | Also does |
|---|---|
| `--profiles` | deletes `~/.config/fortivpn` and every profile in it |
| `--plugin` | deletes the installed plugin directory |
| `--all` | both of the above |
| `--yes` | skips the confirmations |

To remove the plugin files without the script:

```bash
omarchy plugin remove omafortivpn
```

## License

MIT. See [LICENSE](LICENSE).
