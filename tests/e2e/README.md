# M6 real ISO installation checks

`.github/workflows/m6-e2e.yml` runs nightly at 02:17 UTC, on relevant pull
requests, and manually. All privileged work runs in a disposable Actions
container/VM; never run `prepare.sh` or `install.sh` on a development host.
Dawn's existing GUI/stand-in regression tests remain enabled on every push.

The job verifies the pinned published repository database with the public key
from the pinned packaging checkout, then verifies the four LuminOS package
hashes against that database. It builds the real `luminos-live` and downloads
the complete ISO dependency closure into one local repository. Public Arch
mirrors are used only to populate this snapshot. Both mkarchiso and Dawn's
online installation consume that same snapshot; guests have no public mirror
URLs. `SHA256SUMS` and source commits are retained with the serial logs.
The Arch package versions are refreshed at preparation time and then frozen
for all scenarios in that run; this is not a historical Arch Linux Archive pin.

The production releng profile and published Dawn binary are used. Only a
copied test profile gets fast zstd compression, a local pacman config, `jq`,
and a fixture generator/installer. The fixture service is generated under
`/run`, requires the live archiso environment, a scenario credential and the
VM disk's dedicated serial. Fixtures are removed from the installed root after
Dawn completes. No fixture is added to production media.

Each scenario creates a fresh 48 GiB sparse disk and throwaway OVMF variables:

- Online: pacstrap the real base and desktop from the local snapshot.
- Offline: no NIC is attached; install from the actual ISO squashfs.
- Secure Boot: start in OVMF Setup Mode, install online, keep the enrolled
  variables, and require `SecureBoot=1` after reboot.

For each reboot, detach the ISO and stop the mirror, log in as the created
user with the configured password, and verify base/desktop/keyring, keyboard
configuration, enabled greetd/NetworkManager, no live user, installer or
archiso hooks, and no live autologin drop-ins. Plain scenarios require
`SecureBoot=0`. Password leakage, timeout or any failed assertion fails CI.
Later scenarios still run after an earlier scenario fails.

The published M5 database is signed, but its four package entries currently
have no embedded or detached package signatures. Authenticating their hashes
with the signed database is sufficient for this isolated test snapshot; it
is not a replacement for signing packages or enforcing release signature
policy. Production `pacman.conf` is unchanged.

Run in the disposable CI environment:

```sh
tests/e2e/prepare.sh "$PWD/published-repository" \
  "$PWD/package-sources/luminos-keyring/luminos.gpg"
export DAWN_SOURCE_DIR="$PWD/dawn-source"
tests/e2e/run.sh online
tests/e2e/run.sh offline
tests/e2e/run.sh secure-boot
```

Update the workflow's immutable repository/recipe/helper revisions deliberately
when publishing new packages or changing test helpers. A failed nightly run
retains its logs and manifest; reproduce with those exact package versions
rather than quietly resolving a different dependency set.
