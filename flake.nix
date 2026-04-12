{
  description = "Embassy STM32F103 firmware build with Nix, Fenix, and Crane";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix.url = "github:nix-community/fenix";
    crane.url = "github:ipetkov/crane";
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
    crane,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Select toolchain from rust-toolchain.toml
        rustToolchain = fenix.packages.${system}.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-zC8E38iDVJ1oPIzCqTk/Ujo9+9kx9dXq7wAwPMpkpg0=";
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = pkgs.lib.cleanSource ./fw/.;

        # Common args for Crane
        commonCraneArgs = {
          pname = "led_ctrl";
          version = "0.1.0";
          inherit src;

          CARGO_BUILD_TARGET = "thumbv7m-none-eabi";

          nativeBuildInputs = with pkgs; [
            just
            pkg-config
            gcc-arm-embedded
            cargo-binutils
            fd
            gdb
          ];

          doCheck = false;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonCraneArgs;

        firmware = craneLib.buildPackage (commonCraneArgs
          // {
            inherit cargoArtifacts;

            # Build the elf files with cargo build, then generate .bin files from them
            buildPhase = ''
              cargo build
              cd target/thumbv7m-none-eabi/debug/
              for bin in $(fd . -t x -d 1); do arm-none-eabi-objcopy -O binary $bin $bin.bin; done
            '';

            # Install all executables in the build directory
            installPhase = ''
              mkdir -p $out/firmware
              for bin in $(fd . -t x -d 1); do cp $bin $out/firmware/$bin; done
            '';
          });

        # expression for the devshell
        devShell = pkgs.mkShell {
          name = "led-rust-dev";
          nativeBuildInputs = with pkgs; [
            rustToolchain
            llvm
            just
            pkg-config
            gdb
            stlink
            openocd
            fd
            probe-rs-tools
            cargo-binutils
            dfu-util
            can-utils
            gcc-arm-embedded
            (python3.withPackages (ps: with ps; [pyocd]))
          ];
          shellHook = ''

            export CARGO_TARGET_THUMBV7M_NONE_EABI_LINKER=arm-none-eabi-ld
            export CARGO_TARGET=thumbv7m-none-eabi
            export DEFMT_LOG=trace
            echo "🔧 Target     : $CARGO_TARGET"
            echo "just commands : $(just --summary)"
          '';
        };

        # expression for the flashing script
        flashScript = pkgs.writeShellApplication {
          name = "flash";
          runtimeInputs = [pkgs.stlink pkgs.openocd];
          text = ''
            echo "Resetting and erasing..."
            openocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "reset_config srst_only \
            srst_nogate connect_assert_srst" -c "init" -c "reset halt;" -c 'flash erase_sector 0 0 last; reset' -c 'shutdown'

            echo "Flashing firmware..."
            openocd -f interface/stlink.cfg -f target/stm32f1x.cfg \
              -c "program ${firmware}/firmware/led_ctrl verify reset exit"
            echo "done!"
          '';
        };

        # we can make this container much smaller with streamLayeredImage
        containers = pkgs.dockerTools.buildImage {
          name = "led-tools-container";
          tag = "latest";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [
              pkgs.openocd
              pkgs.bashInteractive
              firmware
              flashScript
            ];
          };
          config.Cmd = ["flash"];
        };

        # expresssion to combine and build all outputs
        combined = pkgs.runCommand "led" {} ''
          mkdir -p $out/{containers, firmware, bin}
          cp -r ${firmware}/firmware/* $out/firmware
          cp ${containers} $out/containers/led-tools-container.tar
          cp ${flashScript}/bin/* $out/bin/
        '';
      in {
        # main devshell for all development
        devShells.default = devShell;

        # seperate build artifacts
        packages.firmware = firmware;
        packages.flash = flashScript;
        packages.containers = containers;

        # scripts can be invoked with nix run .#flash
        apps.flash = flake-utils.lib.mkApp {drv = flashScript;};

        # combined multi output build
        packages.default = combined;
      }
    );
}
