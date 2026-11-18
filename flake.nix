{
  description = "Declarative Free Claude Code launchers for NixOS and Home Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          free-claude-code = pkgs.callPackage ./packages/free-claude-code.nix { };
          default = free-claude-code;
        }
      );

      nixosModules = rec {
        fcc = import ./modules { isHomeManager = false; };
        default = fcc;
      };

      homeManagerModules = rec {
        fcc = import ./modules { isHomeManager = true; };
        default = fcc;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests {
          inherit (nixpkgs) lib;
          inherit pkgs system;
          fccPackage = self.packages.${system}.free-claude-code;
          nixosModule = self.nixosModules.default;
          homeManagerModule = self.homeManagerModules.default;
        }
        // {
          package = self.packages.${system}.free-claude-code;
        }
      );
    };
}
