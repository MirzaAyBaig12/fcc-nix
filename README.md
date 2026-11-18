# fcc-nix

Nix packaging and declarative launchers for [Free Claude Code (FCC)](https://github.com/Alishahryar1/free-claude-code), with matching **NixOS** and **Home Manager** modules.

You install each AI agent normally. Enabling its `fcc-nix.<agent>` option installs only the small FCC launcher; the agent itself is **not wrapped or added to your profile by this module**. Launchers find the installed agent on `PATH`, so no `source` option is normally needed. The base FCC derivation is also left unwrapped, so substituters remain useful.

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

  fcc-nix = {
    claude.enable = true;

    # Optional: run FCC as a restarting system service. Use the account that
    # owns your FCC configuration; no user is assumed automatically.
    fcc-server.service = {
      enable = true;
      user = "your-username";
    };

    # Optional: install fcc-server and fcc-doctor without enabling an agent
    # or service. This is not needed when either of those is enabled.
    # fcc-server.enable = true;
  };
}
```

## Home Manager

```nix
{ pkgs, inputs, ... }:
{
  imports = [ inputs.fcc-nix.homeManagerModules.default ];

  home.packages = [
    inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
  ];

  fcc-nix = {
    opencode.enable = true;

    # Optional: run FCC as a restarting systemd user service.
    fcc-server.service.enable = true;
  };
}
```

Then run `fcc-claude`, `fcc-opencode`, etc. The launcher supplies only a process-local `PATH`; your original agent commands remain untouched. FCC starts `fcc-server` when needed.

### Automatic agent detection

No `source` setting is required. Each launcher checks `PATH` when it starts:

- If the expected executable is available, FCC uses it.
- If it is missing, the launcher prints an installation/PATH error and exits.
- OpenCode detection tries `opencode2` first, then `opencode`. The selected executable is exposed privately to FCC under its expected `opencode` name.
- When the fallback `opencode` executable reports version 1.x, the launcher asks you to update to OpenCode 2 or newer. OpenCode 1 is not supported by FCC.

An optional per-agent package override remains available:

```nix
fcc-nix.claude.source = inputs.my-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
```

An explicit `source` is checked at build time and takes priority over `PATH`. It is not added to `home.packages` or `environment.systemPackages`; install it separately if you also want its original command in your profile. Without an explicit source, detection is intentionally a runtime check rather than a Nix evaluation or build check.

## Token optimizations

Both optimizations are disabled by default:

```nix
fcc-nix.optimizations = {
  rtk.enable = true;
  headroom.enable = true;
};
```

Enabled tools are added only to the launchers' process-local `PATH`; their bare commands are not installed into your profile. Launchers also set `RTK_TELEMETRY_DISABLED=1` when RTK is enabled.

Registration runs as the invoking user whenever a supported `fcc-*` launcher starts, using the upstream FCC setup commands:

| Optimization | Automatic launcher registration |
| --- | --- |
| RTK | Claude, Codex, Pi |
| Headroom MCP | Claude, Codex, Grok |

Registration is idempotent and leaves unrelated settings intact. Headroom mismatches are preserved with a warning rather than blocking the agent. `--force` is used only for Codex/Grok's marker-delimited Headroom blocks, where unmarked user-managed entries remain protected. Existing marked Codex/Grok registrations can therefore move from an old executable path to the Nix package. Headroom's pre-v2 OpenCode registrar is deliberately not used.

The packages default to `pkgs.rtk` and this flake's Headroom 0.40.0 package. They can be overridden with `fcc-nix.optimizations.rtk.package` and `fcc-nix.optimizations.headroom.package`.

## Agent options

Every agent is disabled by default and needs only `fcc-nix.<agent>.enable = true`.

| Option | Commands searched, in priority order |
| --- | --- |
| `fcc-nix.claude` | `claude` |
| `fcc-nix.codex` | `codex` |
| `fcc-nix.pi` | `pi` |
| `fcc-nix.opencode` | `opencode2`, then `opencode` (v2+) |
| `fcc-nix.cline` | `cline` |
| `fcc-nix.hermes` | `hermes` |
| `fcc-nix.dsh` | `dsh` |
| `fcc-nix.grok` | `grok` |
| `fcc-nix.muse` | `muse` |
| `fcc-nix.aider` | `aider` |
| `fcc-nix.agy` | `agy` |

`fcc-nix.package` can override the FCC package itself. `fcc-nix.fcc-server.enable = true` installs just `fcc-server` and `fcc-doctor` (plus any separately enabled launchers).

### Persistent server service

Set `fcc-nix.fcc-server.service.enable = true` to create `fcc-server-nix`, which runs `fcc-server` and restarts it five seconds after any exit:

- **NixOS:** a system service starting at `multi-user.target`. Set `fcc-nix.fcc-server.service.user` to the existing user whose FCC configuration and credentials it should use.
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

## Standalone packages

```sh
nix run github:MirzaAyBaig12/fcc-nix#free-claude-code -- --version
nix run github:MirzaAyBaig12/fcc-nix#headroom -- --version
```

The standalone FCC package contains upstream's complete command set. The modules intentionally expose only `fcc-server`, `fcc-doctor`, and the launchers you enable, avoiding profile collisions.

## Development

```sh
nix build path:$PWD#free-claude-code --print-build-logs
./result/bin/fcc-server --version
nix build path:$PWD#headroom --print-build-logs
nix flake check path:$PWD --no-build
nix build path:$PWD#checks.x86_64-linux.nixos-module
nix build path:$PWD#checks.x86_64-linux.home-manager-module
DRY_RUN=1 ./scripts/update.sh  # with curl, jq, and Nix on PATH
```

See `.opencode/README.md` for the repository map and update/maintenance notes.
