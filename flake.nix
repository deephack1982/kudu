{
  description = "Easily manage VMs on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          runtimePath = lib.makeBinPath (
            with pkgs;
            [
              e2fsprogs
              passt
              qemu
              xorriso
            ]
          );
        in
        {
          kudu = pkgs.rustPlatform.buildRustPackage {
            pname = "kudu";
            version = "0.3.0";

            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./Cargo.lock
                ./Cargo.toml
                ./LICENSE
                ./README.md
                ./src
              ];
            };

            cargoLock.lockFile = ./Cargo.lock;

            nativeBuildInputs = with pkgs; [
              makeWrapper
              pkg-config
            ];

            buildInputs = with pkgs; [
              openssl
            ];

            postPatch = ''
              substituteInPlace src/firmware.rs \
                --replace-fail '"fedora" | "rhel" => match arch {' '"fedora" | "rhel" | "nixos" => match arch {' \
                --replace-fail 'PathBuf::from("/usr/share/edk2/ovmf/OVMF_CODE.fd")' 'PathBuf::from("${pkgs.OVMF.fd}/FV/OVMF_CODE.fd")' \
                --replace-fail 'PathBuf::from("/usr/share/edk2/ovmf/OVMF_VARS.fd")' 'PathBuf::from("${pkgs.OVMF.fd}/FV/OVMF_VARS.fd")'
            '';

            postInstall = ''
              wrapProgram "$out/bin/kudu" \
                --prefix PATH : "${runtimePath}"
            '';

            meta = {
              description = "TUI for creating and managing VMs on Linux";
              homepage = "https://github.com/pythops/kudu";
              license = lib.licenses.gpl3Plus;
              mainProgram = "kudu";
              platforms = lib.platforms.linux;
            };
          };

          default = self.packages.${system}.kudu;
        }
      );

      apps = forAllSystems (system: {
        kudu = {
          type = "app";
          program = "${self.packages.${system}.kudu}/bin/kudu";
        };
        default = self.apps.${system}.kudu;
      });

      nixosModules = {
        kudu =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.programs.kudu;
            runtimePackages = with pkgs; [
              e2fsprogs
              passt
              qemu
              xorriso
            ];
          in
          {
            options.programs.kudu = {
              enable = lib.mkEnableOption "kudu, a TUI for creating and managing VMs";

              package = lib.mkOption {
                type = lib.types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.kudu;
                defaultText = lib.literalExpression "inputs.kudu.packages.\${pkgs.stdenv.hostPlatform.system}.kudu";
                description = "The kudu package to install.";
              };

              installRuntimeDependencies = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Install QEMU, xorriso, passt, and chattr system-wide alongside kudu.";
              };

              enableVncViewer = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Install tigervnc so kudu can launch vncviewer for VM consoles.";
              };

              extraPackages = lib.mkOption {
                type = lib.types.listOf lib.types.package;
                default = [ ];
                description = "Additional packages to install with kudu.";
              };
            };

            config = lib.mkIf cfg.enable {
              environment.systemPackages =
                [ cfg.package ]
                ++ lib.optionals cfg.installRuntimeDependencies runtimePackages
                ++ lib.optionals cfg.enableVncViewer [ pkgs.tigervnc ]
                ++ cfg.extraPackages;

              users.groups.kvm = { };
            };
          };

        default = self.nixosModules.kudu;
      };

      overlays.default = final: _prev: {
        kudu = self.packages.${final.stdenv.hostPlatform.system}.kudu;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              clippy
              rustc
              rustfmt
            ];
          };
        }
      );
    };
}
