# fcc-nix agent notes

Start here when working on this repository.

## Repository map

- `flake.nix`: packages for `x86_64-linux` and `aarch64-linux`, matching `nixosModules` and `homeManagerModules`, formatter, and checks.
- `packages/free-claude-code.nix`: FCC release wheel and its Python dependencies. The main `version`, GitHub `url`, and `hash` are updater-owned. Three small PyPI wheels handle missing/outdated nixpkgs packages.
- `modules/default.nix`: shared NixOS/Home Manager implementation, parameterized by `isHomeManager`; also defines the restarting `fcc-server-nix` system/user service.
- `tests/default.nix`: lightweight package, launcher, and service checks using a fake `claude` executable; no real agent is built.
- `scripts/update.sh`: bumps only FCC's release version and wheel hash. Supports `DRY_RUN=1`.
- `.github/workflows/update.yml`: every-four-hours update, validation, commit, and push.
- `.opencode/free-claude-code.md`: upstream-specific packaging details and gotchas.

## Public interface

Each agent has a top-level option such as:

```nix
fcc-claude = {
  enable = true;
  source = pkgs.claude-code;
};
```

The user installs the agent separately. The module adds a core symlink package (`fcc-server`, `fcc-doctor`) and selected tiny launchers only. It must **not** add agent sources to `home.packages` or `environment.systemPackages`, and it must **not** override/wrap the base FCC derivation. This avoids binary collisions and preserves cache reuse.

`source` defaults to the caller's nixpkgs package when a suitable one exists. It may point at another flake's package. A null enabled source is an evaluation assertion; a source missing its expected binary fails the tiny launcher build.

`fcc-server.service.enable` creates `fcc-server-nix` with `Restart = "always"` and a five-second restart delay. NixOS uses a system service and requires `fcc-server.service.user`; Home Manager uses a user service. Enabling the service also exposes the core commands without requiring `fcc-server.enable`.

## Validation

New untracked files are invisible to a Git flake. Until files are staged, use `path:$PWD` rather than plain `.`:

```sh
nix build path:$PWD#free-claude-code --print-build-logs
nix flake check path:$PWD --no-build
nix build path:$PWD#checks.x86_64-linux.nixos-module --print-build-logs
nix build path:$PWD#checks.x86_64-linux.home-manager-module --print-build-logs
```

Run `nixfmt` on Nix files. Do not commit or stage unless the user explicitly asks. The update workflow's Git commands are for CI, not permission to mutate the user's local Git state.
