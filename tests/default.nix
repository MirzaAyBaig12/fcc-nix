{
  lib,
  pkgs,
  system,
  fccPackage,
  nixosModule,
  homeManagerModule,
}:

let
  fakeAgent = pkgs.writeShellScriptBin "claude" ''
    printf 'claude:%s\n' "$*"
  '';
  fakeOpenCode = pkgs.writeShellScriptBin "opencode" ''
    if [ "''${1:-}" = "--version" ]; then
      echo "opencode v2.3.1"
    else
      printf 'opencode:%s\n' "$*"
    fi
  '';
  fakeOpenCode1 = pkgs.writeShellScriptBin "opencode" ''
    if [ "''${1:-}" = "--version" ]; then
      echo "opencode v1.9.7"
    else
      printf 'opencode1:%s\n' "$*"
    fi
  '';
  fakeOpenCode2 = pkgs.writeShellScriptBin "opencode2" ''
    if [ "''${1:-}" = "--version" ]; then
      echo "opencode v2.3.1"
    else
      printf 'opencode2:%s\n' "$*"
    fi
  '';
  fakeRtk = pkgs.writeShellScriptBin "rtk" ''
    printf 'rtk:%s:telemetry=%s\n' "$*" "$RTK_TELEMETRY_DISABLED" >> "$FCC_TEST_LOG"
  '';
  fakeHeadroom = pkgs.writeShellScriptBin "headroom" ''
    printf 'headroom:%s\n' "$*" >> "$FCC_TEST_LOG"
  '';
  fakeFcc =
    (pkgs.buildEnv {
      name = "fake-fcc";
      paths = [
        (pkgs.writeShellScriptBin "fcc-server" ''
          if [ "''${1:-}" = "--version" ]; then
            echo "${fccPackage.version}"
          fi
        '')
        (pkgs.writeShellScriptBin "fcc-doctor" "")
        (pkgs.writeShellScriptBin "fcc-claude" ''exec claude "$@"'')
        (pkgs.writeShellScriptBin "fcc-opencode" ''exec opencode "$@"'')
      ];
    })
    // {
      version = fccPackage.version;
    };

  nixosEval = lib.nixosSystem {
    inherit system;
    modules = [
      nixosModule
      {
        fcc-nix = {
          package = fakeFcc;
          claude = {
            enable = true;
            source = fakeAgent;
          };
          opencode = {
            enable = true;
            source = fakeOpenCode2;
          };
          fcc-server.service = {
            enable = true;
            user = "test";
          };
        };
        system.stateVersion = "26.05";
      }
    ];
  };

  homeOptions = {
    options = {
      home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
      systemd.user.services = lib.mkOption {
        type = lib.types.attrsOf lib.types.unspecified;
        default = { };
      };
    };
  };

  homeEval = lib.evalModules {
    modules = [
      homeOptions
      {
        config = {
          _module.args.pkgs = pkgs;
          fcc-nix = {
            package = fakeFcc;
            claude.enable = true;
            opencode.enable = true;
            optimizations = {
              rtk = {
                enable = true;
                package = fakeRtk;
              };
              headroom = {
                enable = true;
                package = fakeHeadroom;
              };
            };
            fcc-server.service.enable = true;
          };
        };
      }
      homeManagerModule
    ];
  };

  disabledEval = lib.evalModules {
    modules = [
      homeOptions
      { config._module.args.pkgs = pkgs; }
      homeManagerModule
    ];
  };

  mkModuleCheck =
    name: packages: extraCheck:
    pkgs.buildEnv {
      inherit name;
      paths = packages;
      postBuild = ''
        test -x $out/bin/fcc-server
        test -x $out/bin/fcc-doctor
        test -x $out/bin/fcc-claude
        test -x $out/bin/fcc-opencode
        test ! -e $out/bin/claude
        test ! -e $out/bin/opencode
        test ! -e $out/bin/opencode2
        test ! -e $out/bin/rtk
        test ! -e $out/bin/headroom
        $out/bin/fcc-server --version | grep -F ${fccPackage.version}
        ${extraCheck}
      '';
    };
in
{
  nixos-module =
    assert nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.Restart == "always";
    assert nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.User == "test";
    assert lib.hasSuffix "/bin/fcc-server"
      nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.ExecStart;
    mkModuleCheck "fcc-nixos-module-test" nixosEval.config.environment.systemPackages ''
      grep -F '${fakeAgent}/bin' $out/bin/fcc-claude >/dev/null
      grep -F '${fakeOpenCode2}/bin' $out/bin/fcc-opencode >/dev/null

      output=$(PATH=/nonexistent $out/bin/fcc-claude from-source)
      test "$output" = "claude:from-source"
      output=$(PATH=/nonexistent $out/bin/fcc-opencode from-source)
      test "$output" = "opencode2:from-source"
    '';

  home-manager-module =
    assert homeEval.config.systemd.user.services.fcc-server-nix.Service.Restart == "always";
    assert lib.hasSuffix "/bin/fcc-server"
      homeEval.config.systemd.user.services.fcc-server-nix.Service.ExecStart;
    assert !disabledEval.config.fcc-nix.optimizations.rtk.enable;
    assert !disabledEval.config.fcc-nix.optimizations.headroom.enable;
    assert disabledEval.config.home.packages == [ ];
    mkModuleCheck "fcc-home-manager-module-test" homeEval.config.home.packages ''
      if grep -F '${fakeAgent}/bin' $out/bin/fcc-claude >/dev/null; then
        echo "automatic launcher unexpectedly captured an agent source" >&2
        exit 1
      fi
      grep -F '${fakeRtk}/bin' $out/bin/fcc-claude >/dev/null
      grep -F '${fakeHeadroom}/bin' $out/bin/fcc-claude >/dev/null

      log=$TMPDIR/fcc-registration.log
      : > "$log"
      output=$(PATH=${fakeAgent}/bin FCC_TEST_LOG="$log" $out/bin/fcc-claude automatic)
      test "$output" = "claude:automatic"
      cat > $TMPDIR/expected-registration <<EOF
      rtk:init --global --auto-patch:telemetry=1
      headroom:mcp install --agent claude
      EOF
      diff -u $TMPDIR/expected-registration "$log"

      : > "$log"
      output=$(PATH=${fakeOpenCode}/bin FCC_TEST_LOG="$log" $out/bin/fcc-opencode fallback)
      test "$output" = "opencode:fallback"
      test ! -s "$log"

      output=$(PATH=${fakeOpenCode1}/bin:${fakeOpenCode2}/bin FCC_TEST_LOG="$log" $out/bin/fcc-opencode priority)
      test "$output" = "opencode2:priority"

      if output=$(PATH=${fakeOpenCode1}/bin FCC_TEST_LOG="$log" $out/bin/fcc-opencode rejected 2>&1); then
        echo "OpenCode 1 was not rejected" >&2
        exit 1
      fi
      echo "$output" | grep -F "Update to OpenCode 2 or newer" >/dev/null
      if echo "$output" | grep -F "opencode2" >/dev/null; then
        echo "OpenCode 1 error mentioned the alternate executable" >&2
        exit 1
      fi

      if output=$(PATH=/nonexistent FCC_TEST_LOG="$log" $out/bin/fcc-claude missing 2>&1); then
        echo "missing Claude executable was not rejected" >&2
        exit 1
      fi
      echo "$output" | grep -F "could not find Claude on PATH" >/dev/null
    '';
}
