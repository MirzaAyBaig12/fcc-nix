# fcc-nix

Nix packaging and declarative launchers for [Free Claude Code (FCC)](https://github.com/Alishahryar1/free-claude-code), with matching **NixOS** and **Home Manager** modules.

You install each AI agent normally. Enabling its `fcc-*` option installs only the small FCC launcher; the agent itself is **not wrapped or added to your profile by this module**. The base FCC derivation is also left unwrapped, so substituters remain useful.

The updater checks the latest FCC GitHub release every four hours, updates the release wheel's version/hash, checks the flake, builds FCC, tests `fcc-server --version`, and only then pushes the bump.

## Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fcc-nix = {
      url = "github:MirzaAyBaig12/fcc-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

## NixOS

```nix
{ pkgs, inputs, ... }:
{
  imports = [ inputs.fcc-nix.nixosModules.default ];

  # Install agents yourself, exactly as you normally would.
  environment.systemPackages = [
    inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
  ];

  fcc-claude = {
    enable = true;
    source = inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  };

  # Optional: run FCC as a restarting system service. Use the account that
  # owns your FCC configuration; no user is assumed automatically.
  fcc-server.service = {
    enable = true;
    user = "your-username";
  };

  # Optional: install fcc-server and fcc-doctor without enabling an agent
  # or service. This is not needed when either of those is enabled.
  # fcc-server.enable = true;
}
```

## Home Manager

```nix
{ pkgs, inputs, ... }:
{
  imports = [ inputs.fcc-nix.homeManagerModules.default ];

  home.packages = [
    inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
  ];

  fcc-opencode = {
    enable = true;
    source = inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  };

  # Optional: run FCC as a restarting systemd user service.
  fcc-server.service.enable = true;
}
```

Then run `fcc-claude`, `fcc-opencode`, etc. The launcher supplies only a process-local `PATH`; your original `claude` or `opencode` command remains untouched. FCC starts `fcc-server` when needed.

### Use nixpkgs defaults

For agents available in nixpkgs, `source` defaults to the ordinary package from **your** `pkgs`, so this is enough:

```nix
environment.systemPackages = [ pkgs.claude-code ];
fcc-claude.enable = true;
```

Set `source` explicitly when using another flake or a different package. This is particularly important for OpenCode: FCC requires stable OpenCode 2, so an older nixpkgs `opencode` is not sufficient.

### Failure behavior

- Enabling an agent whose default `source` is `null` fails evaluation with a message telling you to set `fcc-<agent>.source`.
- A `source` that does not contain the expected `bin/<command>` fails the launcher build with a direct error. It never waits until you start FCC to discover a misspecified package.
- The module does not install `source` into `home.packages` or `environment.systemPackages`; keep the agent package installed there yourself if you also want its original command in your profile.

## Agent options

Every option is disabled by default.

| Option | Expected command | Default `source` |
| --- | --- | --- |
| `fcc-claude` | `claude` | `pkgs.claude-code` |
| `fcc-codex` | `codex` | `pkgs.codex` |
| `fcc-pi` | `pi` | `pkgs.pi-coding-agent` |
| `fcc-opencode` | `opencode` | `pkgs.opencode` (must be v2) |
| `fcc-cline` | `cline` | `pkgs.cline` |
| `fcc-hermes` | `hermes` | `null`; set `source` |
| `fcc-dsh` | `dsh` | `null`; set `source` |
| `fcc-grok` | `grok` | `pkgs.grok-cli` |
| `fcc-muse` | `muse` | `null`; set `source` |
| `fcc-aider` | `aider` | `pkgs.aider-chat` |
| `fcc-agy` | `agy` | `null`; set `source` |

`fcc.package` can override the FCC package itself. `fcc-server.enable = true` installs just `fcc-server` and `fcc-doctor` (plus any separately enabled launchers).

### Persistent server service

Set `fcc-server.service.enable = true` to create `fcc-server-nix`, which runs `fcc-server` and restarts it five seconds after any exit:

- **NixOS:** a system service starting at `multi-user.target`. Set `fcc-server.service.user` to the existing user whose FCC configuration and credentials it should use.
- **Home Manager:** a user service starting at `default.target`; no `user` option is needed.

Useful commands after rebuilding:

```sh
# NixOS
systemctl status fcc-server-nix
journalctl -u fcc-server-nix -f

# Home Manager
systemctl --user status fcc-server-nix
journalctl --user -u fcc-server-nix -f
```

## Standalone package

```sh
nix run github:MirzaAyBaig12/fcc-nix#free-claude-code -- --version
```

The standalone package contains upstream's complete command set. The modules intentionally expose only `fcc-server`, `fcc-doctor`, and the launchers you enable, avoiding profile collisions.

## Development

```sh
nix build path:$PWD#free-claude-code --print-build-logs
./result/bin/fcc-server --version
nix flake check path:$PWD --no-build
nix build path:$PWD#checks.x86_64-linux.nixos-module
nix build path:$PWD#checks.x86_64-linux.home-manager-module
DRY_RUN=1 ./scripts/update.sh  # with curl, jq, and Nix on PATH
```

See `.opencode/README.md` for the repository map and update/maintenance notes.
