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
    echo fake-claude
  '';

  nixosEval = lib.nixosSystem {
    inherit system;
    modules = [
      nixosModule
      {
        fcc-claude = {
          enable = true;
          source = fakeAgent;
        };
        fcc-server.service = {
          enable = true;
          user = "test";
        };
        system.stateVersion = "26.05";
      }
    ];
  };

  homeEval = lib.evalModules {
    modules = [
      {
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
        config = {
          _module.args.pkgs = pkgs;
          fcc-claude = {
            enable = true;
            source = fakeAgent;
          };
          fcc-server.service.enable = true;
        };
      }
      homeManagerModule
    ];
  };

  mkModuleCheck =
    name: packages:
    pkgs.buildEnv {
      inherit name;
      paths = packages;
      postBuild = ''
        test -x $out/bin/fcc-server
        test -x $out/bin/fcc-doctor
        test -x $out/bin/fcc-claude
        test ! -e $out/bin/claude
        $out/bin/fcc-server --version | grep -F ${fccPackage.version}
        grep -F '${fakeAgent}/bin' $out/bin/fcc-claude >/dev/null
      '';
    };
in
{
  nixos-module =
    assert nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.Restart == "always";
    assert nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.User == "test";
    assert lib.hasSuffix "/bin/fcc-server"
      nixosEval.config.systemd.services.fcc-server-nix.serviceConfig.ExecStart;
    mkModuleCheck "fcc-nixos-module-test" nixosEval.config.environment.systemPackages;
  home-manager-module =
    assert homeEval.config.systemd.user.services.fcc-server-nix.Service.Restart == "always";
    assert lib.hasSuffix "/bin/fcc-server"
      homeEval.config.systemd.user.services.fcc-server-nix.Service.ExecStart;
    mkModuleCheck "fcc-home-manager-module-test" homeEval.config.home.packages;
}
