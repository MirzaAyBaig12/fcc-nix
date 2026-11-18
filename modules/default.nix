{ isHomeManager }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  agentSpecs = {
    claude = {
      packageAttr = "claude-code";
      binary = "claude";
    };
    codex = {
      packageAttr = "codex";
      binary = "codex";
    };
    pi = {
      packageAttr = "pi-coding-agent";
      binary = "pi";
    };
    opencode = {
      packageAttr = "opencode";
      binary = "opencode";
    };
    cline = {
      packageAttr = "cline";
      binary = "cline";
    };
    hermes = {
      packageAttr = null;
      binary = "hermes";
    };
    dsh = {
      packageAttr = null;
      binary = "dsh";
    };
    grok = {
      packageAttr = "grok-cli";
      binary = "grok";
    };
    muse = {
      packageAttr = null;
      binary = "muse";
    };
    aider = {
      packageAttr = "aider-chat";
      binary = "aider";
    };
    agy = {
      packageAttr = null;
      binary = "agy";
    };
  };
  agentNames = builtins.attrNames agentSpecs;
  agents = map (name: {
    inherit name;
    spec = agentSpecs.${name};
    cfg = config."fcc-${name}";
  }) agentNames;
  enabledAgents = builtins.filter (agent: agent.cfg.enable) agents;
  sourcedAgents = builtins.filter (agent: agent.cfg.source != null) enabledAgents;
  cfg = config.fcc;

  # Only expose server/doctor from the cached package. The selected fcc-*
  # launchers below therefore never collide with launchers from the full wheel.
  core =
    pkgs.runCommand "free-claude-code-core-${cfg.package.version}"
      {
        preferLocalBuild = true;
        meta.mainProgram = "fcc-server";
      }
      ''
        mkdir -p $out/bin
        ln -s ${cfg.package}/bin/fcc-server $out/bin/fcc-server
        ln -s ${cfg.package}/bin/fcc-doctor $out/bin/fcc-doctor
      '';

  launcher =
    agent:
    let
      inherit (agent) name spec;
      source = agent.cfg.source;
    in
    pkgs.runCommand "fcc-${name}-launcher"
      {
        preferLocalBuild = true;
        meta.mainProgram = "fcc-${name}";
      }
      ''
        if [ ! -x "${source}/bin/${spec.binary}" ]; then
          echo "fcc-${name}: the configured source does not provide bin/${spec.binary}" >&2
          echo "Install the agent normally and set fcc-${name}.source to its package." >&2
          exit 1
        fi
        mkdir -p $out/bin
        cat > $out/bin/fcc-${name} <<'EOF'
        #!${pkgs.runtimeShell}
        export PATH=${
          lib.makeBinPath [
            core
            source
          ]
        }:$PATH
        exec ${cfg.package}/bin/fcc-${name} "$@"
        EOF
        chmod +x $out/bin/fcc-${name}
      '';

  packages = [ core ] ++ map launcher sourcedAgents;
  serviceEnabled = config.fcc-server.service.enable;
  anyEnabled = config.fcc-server.enable || serviceEnabled || enabledAgents != [ ];

  serviceDefinition =
    if isHomeManager then
      {
        systemd.user.services.fcc-server-nix = {
          Unit = {
            Description = "Free Claude Code proxy (fcc-nix)";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Install.WantedBy = [ "default.target" ];
          Service = {
            ExecStart = "${core}/bin/fcc-server";
            Restart = "always";
            RestartSec = "5s";
          };
        };
      }
    else
      {
        systemd.services.fcc-server-nix = {
          description = "Free Claude Code proxy (fcc-nix)";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [ core ];
          serviceConfig = {
            User = config.fcc-server.service.user;
            ExecStart = "${core}/bin/fcc-server";
            Restart = "always";
            RestartSec = "5s";
          };
        };
      };
in
{
  options = {
    fcc.package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../packages/free-claude-code.nix { };
      defaultText = literalExpression "inputs.fcc-nix.packages.\${system}.free-claude-code";
      description = "Unmodified Free Claude Code package used by the generated launchers.";
    };

    fcc-server = {
      enable = mkEnableOption "the Free Claude Code server and doctor commands";
      service = {
        enable = mkEnableOption "the restarting fcc-server-nix systemd service";
        user = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "alice";
          description = ''
            Existing user for the NixOS system service. Required when the NixOS
            service is enabled, so FCC uses that user's configuration instead of
            root's. Ignored by Home Manager's user service.
          '';
        };
      };
    };
  }
  // builtins.listToAttrs (
    map (
      name:
      let
        spec = agentSpecs.${name};
      in
      {
        name = "fcc-${name}";
        value = {
          enable = mkEnableOption "the fcc-${name} launcher";
          source = mkOption {
            type = types.nullOr types.package;
            default = if spec.packageAttr != null then pkgs.${spec.packageAttr} or null else null;
            defaultText = literalExpression (
              if spec.packageAttr != null then "pkgs.${spec.packageAttr}" else "null"
            );
            description = ''
              Already-installed ${spec.binary} package to expose to fcc-${name}.
              This module does not add it to your profile. Its bin/${spec.binary}
              executable is checked at build time. Set this explicitly when using
              an agent from another flake or when nixpkgs has no suitable package.
            '';
          };
        };
      }
    ) agentNames
  );

  config = lib.mkMerge [
    (mkIf anyEnabled (
      {
        assertions =
          (map (agent: {
            assertion = agent.cfg.source != null;
            message = "fcc-${agent.name} is enabled, but fcc-${agent.name}.source is null. Set it to the installed ${agent.spec.binary} package.";
          }) enabledAgents)
          ++ lib.optional (!isHomeManager && serviceEnabled) {
            assertion = config.fcc-server.service.user != null;
            message = "fcc-server.service.user must name the existing user whose FCC configuration the NixOS service should use.";
          };
      }
      // (
        if isHomeManager then
          {
            home.packages = packages;
          }
        else
          {
            environment.systemPackages = packages;
          }
      )
    ))
    (mkIf serviceEnabled serviceDefinition)
  ];
}
