# FreeBSD fleet scripts for CloudBSD Wayfire / desktop (pkg-only)

These helpers install and validate the **desktop Wayfire stack on freedev
hosts**. They do **not** build from source.

## Law

1. **Base** (when imaging): `cloudbsdorg/cloudbsd-src` — skill `cloudbsd-src`.
2. **Packages**: `cloudbsd-ports` → poudriere/Jenkins → **`pkg install` only**
   — skill `install-via-pkg`.
3. **Busy / unreachable hosts**: **DEFER**, never drop from the matrix
   (kernel tests, net blips). Re-run later.

## Roles

| Role | Hosts | Behavior |
|------|-------|----------|
| desktop | `$DESKTOP_HOSTS` (default freedev 001–004, 009) | persistent Ly + VOSS + Wayfire |
| transient | `$TRANSIENT_HOSTS` (default 005, 006, 008) | install → validate → **full uninstall** |

Override hosts via env. Jenkins package builds: skill `jenkins-through-mcp`
(controller hostname in that skill; credentials under `~/.creds/`, never here).

## Scripts

| Script | Purpose |
|--------|---------|
| `preflight.sh` | DRM, seatd, Ly, VOSS probes |
| `configure-ly.sh` | Ly getty + groups |
| `configure-voss.sh` | virtual_oss rc |
| `install-stack.sh` | `pkg install` stack |
| `validate.sh` | post-install asserts |
| `uninstall-stack.sh` | remove stack pkgs (transient) |
| `e2e-desktop.sh` / `e2e-transient.sh` / `run-matrix.sh` | orchestrators |

```sh
./preflight.sh --role all
./run-matrix.sh preflight
# after packages exist in the CloudBSD repo:
./e2e-desktop.sh freedev001 freedev003
./e2e-transient.sh freedev008
```
