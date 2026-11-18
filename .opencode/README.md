# fcc-nix agent notes

Start here when working on this repository.

## Repository map

- `flake.nix`: FCC and Headroom packages for `x86_64-linux` and `aarch64-linux`, matching `nixosModules` and `homeManagerModules`, formatter, and checks.
- `packages/free-claude-code.nix`: FCC release wheel and its Python dependencies. The main `version`, GitHub `url`, and `hash` are updater-owned. Three small PyPI wheels handle missing/outdated nixpkgs packages.
- `packages/headroom.nix`: Headroom 0.40.0 release wheel, its native-library fixup, and MCP 1.28.1 for Headroom's `<2` dependency.
- `modules/default.nix`: shared NixOS/Home Manager implementation, parameterized by `isHomeManager`; defines runtime agent detection, optional optimization registration, and the restarting `fcc-server-nix` system/user service.
- `tests/default.nix`: lightweight package, automatic/override launcher, OpenCode selection/version, optimization registration, disabled-default, and service checks using fake executables; no real agent is built.
- `scripts/update.sh`: bumps only FCC's release version and wheel hash. Supports `DRY_RUN=1`.
- `.github/workflows/update.yml`: every-four-hours update, validation, commit, and push.
- `.opencode/free-claude-code.md`: upstream-specific packaging details and gotchas.

## Public interface

All options live under the single `fcc-nix` namespace. Agent names do not have an `fcc-` prefix in the configuration:

```nix
fcc-nix = {
  claude.enable = true;
  opencode.enable = true;
  optimizations = {
    rtk.enable = true;
    headroom.enable = true;
  };
  fcc-server.service.enable = true;
};
```

The user installs the agent separately. The module adds a core symlink package (`fcc-server`, `fcc-doctor`) and selected tiny launchers only. It must **not** add agent sources or optimization tools to `home.packages` or `environment.systemPackages`, and it must **not** override/wrap the base FCC derivation. This avoids binary collisions and preserves cache reuse.

With the default `source = null`, launchers discover the expected command on their runtime `PATH`. OpenCode prefers `opencode2`, falls back to `opencode`, and rejects a v1 fallback. A private canonical-name shim lets FCC invoke a selected `opencode2` without changing the user's profile. Missing commands are runtime errors. An explicit package `source` overrides detection, is checked at build time, and is still not installed into the profile.

`fcc-nix.optimizations.{rtk,headroom}.enable` adds the selected packages to launcher-local `PATH` values. RTK telemetry is disabled in launchers. Supported launchers rerun upstream's idempotent registration as the invoking user: RTK for Claude/Codex/Pi and Headroom MCP for Claude/Codex/Grok. Never enable Headroom's pre-v2 OpenCode registrar. Do not use Headroom `--force` for Claude: its registrar can replace unmarked user configuration. Codex/Grok marker blocks permit safe forced updates of owned entries. Registration failures must preserve the existing configuration and warn rather than overwrite it.

`fcc-nix.fcc-server.service.enable` creates `fcc-server-nix` with `Restart = "always"` and a five-second restart delay. NixOS uses a system service and requires `fcc-nix.fcc-server.service.user`; Home Manager uses a user service. Enabling the service also exposes the core commands without requiring `fcc-nix.fcc-server.enable`.

## Validation

New untracked files are invisible to a Git flake. Until files are staged, use `path:$PWD` rather than plain `.`:

```sh
nix build path:$PWD#free-claude-code --print-build-logs
nix build path:$PWD#headroom --print-build-logs
nix flake check path:$PWD --no-build
nix build path:$PWD#checks.x86_64-linux.nixos-module --print-build-logs
nix build path:$PWD#checks.x86_64-linux.home-manager-module --print-build-logs
```

Run `nixfmt` on Nix files. Do not commit or stage unless the user explicitly asks. The update workflow's Git commands are for CI, not permission to mutate the user's local Git state.
