# Security

This plugin drives `openfortivpn`, which needs root. This page says what runs
as root, what it is allowed to consume, and what the plugin does not protect
against. The commands themselves are listed in full in the README, under
[The sudo password](README.md#the-sudo-password).

## What runs as root, and when

Only two things, and only after you have authenticated with `sudo` (in the
connect terminal) or `pkexec` (disconnect, when there is no cached `sudo`
credential):

- **Connect** — creates the root-owned runtime and log directories, installs
  the transient config, and starts `/usr/bin/openfortivpn` as a transient
  systemd unit.
- **Disconnect** — signals that process, and deletes the transient config.

Creating, editing, deleting, renaming and pinning profiles, and everything the
bar widget does, run as you. There is no daemon, no setuid helper, no sudoers
rule and no polkit rule: nothing is installed that lets a process of yours
reach root without a prompt.

## Nothing root consumes is yours to modify

The profile lives in your home directory, so root never reads it directly.

- **Config.** The profile is read once, filtered, and the re-rendered result is
  piped to root, which writes it to `/run/fortivpn/<name>.conf` (root-owned
  directory, mode 600). It is removed once the handshake settles and again when
  the unit stops.
- **Directories.** `/run/fortivpn` and `/var/log/fortivpn/<uid>` are created by
  root. The log directory is group-readable, never writable by you.
- **Binary.** `/usr/bin/openfortivpn` by absolute path, not looked up on
  `PATH`.

## Profile allowlist

`openfortivpn` has options that make a root process load a shared object
(`pppd-plugin`), run a peer file (`pppd-call`), write to a chosen path
(`pppd-log`) or read a file you own (`ca-file`, `user-cert`, `user-key`).
Only an explicit list of keys, each with a value of the shape that key can
take, reaches root. Anything else, including options added to openfortivpn in
the future, is refused until it is reviewed and added. Lines with control
characters (carriage returns included) are refused, so a value cannot smuggle
in a second setting. `otp` and `persistent` are refused too: a token is only
ever typed at the prompt, and there is no reconnect.

## Unit sandbox

The tunnel is a network-facing parser running as root, so its unit runs with
`ProtectHome`, `PrivateTmp`, `ProtectSystem=full` (with `/etc/resolv.conf`
writable), `NoNewPrivileges`, `UMask=0077` and `Restart=no`.

## Matching the tunnel

Disconnect and status identify the tunnel by an anchored command-line pattern
for the `fortivpn0` interface, resolved at signal time rather than from an
earlier PID, and restricted to processes whose real UID is root (`-U 0`).
A process of yours that copies the command line is neither signalled with
root's authority nor taken for a live tunnel.

## Pinning the gateway certificate

`fortivpn trust` fetches the certificate chain and verifies it against the
system trust store, for the profile's host. If it verifies, the SHA256 of the
leaf is pinned. If it does not (a self-signed FortiGate is the usual case, and
a hostname that is not in the certificate counts too), the fingerprint is shown
and pinned only after you confirm it matches what your administrator gave you
over another channel, or pass `--accept-unverified` yourself. Without a
terminal and without the flag it refuses. The flag skips the check you are
meant to do, so use it only after comparing the fingerprint.

## Out of scope

- A compromised account that can already run commands as you and has your
  sudo password or your 2FA token.
- Anything root on the machine can do.
- A password stored in a profile (`password = …`) is plain text at mode 600;
  that is the trade-off of storing it at all.
- Vulnerabilities in `openfortivpn`, `pppd`, `systemd` or `sudo` themselves;
  report those upstream.

## Reporting a vulnerability

Use [GitHub security advisories](https://github.com/Augusto2803/omafortivpn/security/advisories/new)
on Augusto2803/omafortivpn. Please do not open a public issue for it, and
do not post passwords, tokens, certificate fingerprints or gateway addresses
anywhere public, including in the advisory's title.

Regression tests for the checks above live in `tests/`; see the README.
