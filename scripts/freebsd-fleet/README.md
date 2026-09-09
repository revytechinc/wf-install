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
| desktop | 001 002 003 004 009 | persistent Ly + virtual_oss + Wayfire pkgs |
| transient | 005 006 008 | install → validate → **uninstall completely** |

Jenkins for package builds: `https://jenkins.cloudbsd.org` (jail on **freedev005**
today; migrate to 008 later). Drive via `jenkins-through-mcp` when the CI MCP
is up; otherwise API + `~/.creds/jenkins-admin` / `jenkins-build`.

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
