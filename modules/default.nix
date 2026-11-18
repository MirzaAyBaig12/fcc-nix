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
    optionalString
    types
    ;

  agentSpecs = {
    claude = {
      binary = "claude";
      binaries = [ "claude" ];
      displayName = "Claude";
      rtkArgs = "--global --auto-patch";
      headroom = true;
    };
    codex = {
      binary = "codex";
      binaries = [ "codex" ];
      displayName = "Codex";
      rtkArgs = "--global --codex";
      headroom = true;
    };
    pi = {
      binary = "pi";
      binaries = [ "pi" ];
      displayName = "Pi";
      rtkArgs = "--global --agent pi";
      headroom = false;
    };
    opencode = {
      binary = "opencode";
      binaries = [
        "opencode2"
        "opencode"
      ];
      displayName = "OpenCode";
      rtkArgs = null;
      headroom = false;
    };
    cline = {
      binary = "cline";
      binaries = [ "cline" ];
      displayName = "Cline";
      rtkArgs = null;
      headroom = false;
    };
    hermes = {
      binary = "hermes";
      binaries = [ "hermes" ];
      displayName = "Hermes";
      rtkArgs = null;
      headroom = false;
    };
    dsh = {
      binary = "dsh";
      binaries = [ "dsh" ];
      displayName = "Dsh";
      rtkArgs = null;
      headroom = false;
    };
    grok = {
      binary = "grok";
      binaries = [ "grok" ];
      displayName = "Grok";
      rtkArgs = null;
      headroom = true;
    };
    muse = {
      binary = "muse";
      binaries = [ "muse" ];
      displayName = "Muse";
      rtkArgs = null;
      headroom = false;
    };
    aider = {
      binary = "aider";
      binaries = [ "aider" ];
      displayName = "Aider";
      rtkArgs = null;
      headroom = false;
    };
    agy = {
      binary = "agy";
      binaries = [ "agy" ];
      displayName = "Antigravity";
      rtkArgs = null;
      headroom = false;
    };
  };
  agentNames = builtins.attrNames agentSpecs;
  agents = map (name: {
    inherit name;
    spec = agentSpecs.${name};
    cfg = config.fcc-nix.${name};
  }) agentNames;
  enabledAgents = builtins.filter (agent: agent.cfg.enable) agents;
  cfg = config.fcc-nix;
  optimizationPackages =
    lib.optional cfg.optimizations.rtk.enable cfg.optimizations.rtk.package
    ++ lib.optional cfg.optimizations.headroom.enable cfg.optimizations.headroom.package;

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
      expectedBinaries = lib.concatStringsSep ", " (map (binary: "bin/${binary}") spec.binaries);
      detection =
        if source != null then
          ''
            for candidate in ${lib.escapeShellArgs spec.binaries}; do
              if [ -x "${source}/bin/\$candidate" ]; then
                agent="${source}/bin/\$candidate"
                selected="\$candidate"
                break
              fi
            done
          ''
        else
          ''
            for candidate in ${lib.escapeShellArgs spec.binaries}; do
              if command -v "\$candidate" >/dev/null 2>&1; then
                agent=\$(command -v "\$candidate")
                selected="\$candidate"
                break
              fi
            done
          '';
      registration =
        optionalString (cfg.optimizations.rtk.enable && spec.rtkArgs != null) ''
          rtk init ${spec.rtkArgs}
        ''
        + optionalString (cfg.optimizations.headroom.enable && spec.headroom) ''
          # Codex/Grok use marker-delimited blocks, where --force cannot replace
          # an unmarked user entry. Claude has no such ownership marker.
          if ! headroom mcp install --agent ${name}${
            optionalString (name == "codex" || name == "grok") " --force"
          }; then
            echo "fcc-${name}: Headroom left its existing MCP registration unchanged; check the headroom entry manually." >&2
          fi
        '';
    in
    pkgs.runCommand "fcc-${name}-launcher"
      {
        preferLocalBuild = true;
        meta.mainProgram = "fcc-${name}";
      }
      ''
        ${optionalString (source != null) ''
          found=false
          for binary in ${lib.escapeShellArgs spec.binaries}; do
            if [ -x "${source}/bin/$binary" ]; then
              found=true
              break
            fi
          done
          if [ "$found" != true ]; then
            echo "fcc-${name}: the configured source provides none of: ${expectedBinaries}" >&2
            echo "Set fcc-nix.${name}.source to the installed ${spec.displayName} package, or leave it null to use PATH." >&2
            exit 1
          fi
        ''}

        mkdir -p $out/bin $out/libexec/fcc-${name}

        # FCC looks up its canonical agent command on PATH. This shim forwards
        # to the command selected below, including opencode2 for OpenCode.
        cat > $out/libexec/fcc-${name}/${spec.binary} <<'EOF'
        #!${pkgs.runtimeShell}
        if [ -z "$FCC_NIX_AGENT" ]; then
          echo "fcc-${name}: internal agent path is not set" >&2
          exit 1
        fi
        exec "$FCC_NIX_AGENT" "$@"
        EOF
        chmod +x $out/libexec/fcc-${name}/${spec.binary}

        cat > $out/bin/fcc-${name} <<EOF
        #!${pkgs.runtimeShell}
        set -u
        export PATH=${
          lib.makeBinPath ([ core ] ++ optimizationPackages ++ lib.optional (source != null) source)
        }:\$PATH
        ${optionalString cfg.optimizations.rtk.enable "export RTK_TELEMETRY_DISABLED=1"}

        agent=
        selected=
        ${detection}
        if [ -z "\$agent" ]; then
          echo "fcc-${name}: could not find ${spec.displayName} on PATH (looked for ${lib.concatStringsSep ", " spec.binaries})." >&2
          echo "Install ${spec.displayName} and make its executable available on PATH, then rerun fcc-${name}." >&2
          exit 1
        fi

        ${optionalString (name == "opencode") ''
          if [ "\$selected" = opencode ]; then
            version=\$("\$agent" --version 2>/dev/null || true)
            if [[ \$version =~ (^|[^0-9])v?1(\.[0-9]+)+([^0-9]|\$) ]]; then
              echo "fcc-opencode: OpenCode 1.x is unsupported. Update to OpenCode 2 or newer." >&2
              exit 1
            fi
          fi
        ''}

        ${registration}
        export FCC_NIX_AGENT="\$agent"
        export PATH=$out/libexec/fcc-${name}:\$PATH
        exec ${cfg.package}/bin/fcc-${name} "\$@"
        EOF
        chmod +x $out/bin/fcc-${name}
      '';

  packages = [ core ] ++ map launcher enabledAgents;
  serviceEnabled = cfg.fcc-server.service.enable;
  anyEnabled = cfg.fcc-server.enable || serviceEnabled || enabledAgents != [ ];

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
            User = cfg.fcc-server.service.user;
            ExecStart = "${core}/bin/fcc-server";
            Restart = "always";
            RestartSec = "5s";
          };
        };
      };
in
{
  options.fcc-nix = {
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../packages/free-claude-code.nix { };
      defaultText = literalExpression "inputs.fcc-nix.packages.\${system}.free-claude-code";
      description = "Unmodified Free Claude Code package used by the generated launchers.";
    };

    optimizations = {
      rtk = {
        enable = mkEnableOption "RTK token optimization for supported FCC launchers";
        package = mkOption {
          type = types.package;
          default = pkgs.rtk;
          defaultText = literalExpression "pkgs.rtk";
          description = "RTK package used for launcher PATH integration and idempotent registration.";
        };
      };
      headroom = {
        enable = mkEnableOption "Headroom token optimization for supported FCC launchers";
        package = mkOption {
          type = types.package;
          default = pkgs.callPackage ../packages/headroom.nix { };
          defaultText = literalExpression "inputs.fcc-nix.packages.\${system}.headroom";
          description = "Headroom package used for launcher PATH integration and MCP registration.";
        };
      };
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
        inherit name;
        value = {
          enable = mkEnableOption "the fcc-${name} launcher";
          source = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = ''
              Optional ${spec.displayName} package override. By default, fcc-${name}
              finds ${lib.concatStringsSep ", " spec.binaries} on PATH when it starts.
              An explicit source is checked at build time but is not added to your profile.
            '';
          };
        };
      }
    ) agentNames
  );

  config = lib.mkMerge [
    (mkIf anyEnabled (
      {
        assertions = lib.optional (!isHomeManager && serviceEnabled) {
          assertion = cfg.fcc-server.service.user != null;
          message = "fcc-nix.fcc-server.service.user must name the existing user whose FCC configuration the NixOS service should use.";
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
