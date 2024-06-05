{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-overlay, crane, ... }: 
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        unstableRustTarget = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
          extensions = [ "rust-src" "miri" "rustfmt" ];
          targets = ["riscv32imc-unknown-none-elf"];
        });

        unstableCraneLib = (crane.mkLib pkgs).overrideToolchain unstableRustTarget;

        tomlInfo = unstableCraneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; };
        inherit (tomlInfo) pname version;
        src = ./.;

        rustfmt' = pkgs.writeShellScriptBin "rustfmt" ''
          exec "${unstableRustTarget}/bin/rustfmt" "$@"
        '';

        cargoArtifacts = unstableCraneLib.buildDepsOnly {
          inherit src;
          cargoExtraArgs = "--all-features --all";
        };

        package = unstableCraneLib.buildPackage {
          inherit cargoArtifacts src version;
          cargoExtraArgs = "--all-features --all";
        };
      in
      {
        checks = {
          inherit package;

          package-clippy = unstableCraneLib.cargoClippy {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--all --all-features";
            cargoClippyExtraArgs = "-- --deny warnings";
          };

          package-fmt = unstableCraneLib.cargoFmt {
            inherit src;
          };
        };

        packages = rec {
          inherit package;
          default = package;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ ];

          nativeBuildInputs = [
            rustfmt'
            unstableRustTarget

            pkgs.probe-rs
          ];
        };
      }
    );
}
