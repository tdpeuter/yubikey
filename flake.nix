{
  description = "A Nix Flake for an xfce-based system with YubiKey setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    drduhConfig.url = "github:drduh/config";
    drduhConfig.flake = false;
  };

  outputs = {
    self,
    nixpkgs,
    drduhConfig,
  }: let
    mkSystem = system:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
          "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
          (
            {
              lib,
              pkgs,
              config,
              ...
            }: let
              gpgAgentConf = pkgs.runCommand "gpg-agent.conf" {} ''
                sed '/pinentry-program/d' ${drduhConfig}/gpg-agent.conf > $out
                echo "pinentry-program ${pkgs.pinentry.curses}/bin/pinentry" >> $out
              '';
              viewYubikeyGuide = pkgs.writeShellScriptBin "view-yubikey-guide" ''
                viewer="$(type -P xdg-open || true)"
                if [ -z "$viewer" ]; then
                  viewer="${pkgs.glow}/bin/glow -p"
                fi
                exec $viewer "${self}/README.md"
              '';
              shortcut = pkgs.makeDesktopItem {
                name = "yubikey-guide";
                icon = "${pkgs.yubikey-manager-qt}/share/ykman-gui/icons/ykman.png";
                desktopName = "drduh's YubiKey Guide";
                genericName = "Guide to using YubiKey for GnuPG and SSH";
                comment = "Open the guide in a reader program";
                categories = ["Documentation"];
                exec = "${viewYubikeyGuide}/bin/view-yubikey-guide";
              };
              yubikeyGuide = pkgs.symlinkJoin {
                name = "yubikey-guide";
                paths = [viewYubikeyGuide shortcut];
              };
            in {
              isoImage = {
                isoName = "yubikey-nixos-xfce-23.11.iso";
                # As of writing, zstd-based iso is 1542M, takes ~2mins to
                # compress. If you prefer a smaller image and are happy to
                # wait, delete the line below, it will default to a
                # slower-but-smaller xz (1375M in 8mins as of writing).
                squashfsCompression = "zstd";

                appendToMenuLabel = " YubiKey Live ${self.lastModifiedDate}";
                makeEfiBootable = true; # EFI booting
                makeUsbBootable = true; # USB booting
              };

              swapDevices = [];

              boot = {
                tmp.cleanOnBoot = true;
                kernel.sysctl = {"kernel.unprivileged_bpf_disabled" = 1;};
              };

              services = {
                pcscd.enable = true;
                udev.packages = [pkgs.yubikey-personalization];
                # Automatically log in at the virtual consoles.
                getty.autologinUser = "nixos";
                # Comment out to run in a console for a smaller iso and less RAM.
                xserver = {
                  enable = true;
                  desktopManager.xfce.enable = true;
                  displayManager = {
                    lightdm.enable = true;
                    autoLogin = {
                      enable = true;
                      user = "nixos";
                    };
                  };
                };
              };

              programs = {
                ssh.startAgent = false;
                gnupg.agent = {
                  enable = true;
                  enableSSHSupport = true;
                };
              };

              # Use less privileged nixos user
              users.users = {
                nixos = {
                  isNormalUser = true;
                  extraGroups = ["wheel" "video"];
                  initialHashedPassword = "";
                };
                root.initialHashedPassword = "";
              };

              security = {
                pam.services.lightdm.text = ''
                  auth sufficient pam_succeed_if.so user ingroup wheel
                '';
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
              };

              environment.systemPackages = with pkgs; [
                # Tools for backing up keys
                paperkey
                pgpdump
                parted
                cryptsetup

                # Yubico's official tools
                yubikey-manager
                yubikey-manager-qt
                yubikey-personalization
                yubikey-personalization-gui
                yubico-piv-tool
                yubioath-flutter

                # Testing
                ent
                haskellPackages.hopenpgp-tools

                # Password generation tools
                diceware
                pwgen

                # Might be useful beyond the scope of the guide
                cfssl
                pcsctools
                tmux
                htop

                # This guide itself (run `view-yubikey-guide` on the terminal
                # to open it in a non-graphical environment).
                yubikeyGuide
              ];

              # Disable networking so the system is air-gapped
              # Comment all of these lines out if you'll need internet access
              boot.initrd.network.enable = false;
              networking = {
                resolvconf.enable = false;
                dhcpcd.enable = false;
                dhcpcd.allowInterfaces = [];
                interfaces = {};
                firewall.enable = true;
                useDHCP = false;
                useNetworkd = false;
                wireless.enable = false;
                networkmanager.enable = lib.mkForce false;
              };

              # Unset history so it's never stored Set GNUPGHOME to an
              # ephemeral location and configure GPG with the guide

              environment.interactiveShellInit = ''
                unset HISTFILE
                export GNUPGHOME="/run/user/$(id -u)/gnupg"
                if [ ! -d "$GNUPGHOME" ]; then
                  echo "Creating \$GNUPGHOME…"
                  install --verbose -m=0700 --directory="$GNUPGHOME"
                fi
                [ ! -f "$GNUPGHOME/gpg.conf" ] && cp --verbose "${drduhConfig}/gpg.conf" "$GNUPGHOME/gpg.conf"
                [ ! -f "$GNUPGHOME/gpg-agent.conf" ] && cp --verbose ${gpgAgentConf} "$GNUPGHOME/gpg-agent.conf"
                echo "\$GNUPGHOME is \"$GNUPGHOME\""
              '';

              # Copy the contents of contrib to the home directory, add a
              # shortcut to the guide on the desktop, and link to the whole
              # repo in the documents folder.
              system.activationScripts.yubikeyGuide = let
                homeDir = "/home/nixos/";
                desktopDir = homeDir + "Desktop/";
                documentsDir = homeDir + "Documents/";
              in ''
                mkdir -p ${desktopDir} ${documentsDir}
                chown nixos ${homeDir} ${desktopDir} ${documentsDir}

                cp -R ${self}/contrib/* ${homeDir}
                ln -sf ${yubikeyGuide}/share/applications/yubikey-guide.desktop ${desktopDir}
                ln -sfT ${self} ${documentsDir}/YubiKey-Guide
              '';
              system.stateVersion = "23.11";
            }
          )
        ];
      };
  in {
    nixosConfigurations.yubikeyLive.x86_64-linux = mkSystem "x86_64-linux";
    nixosConfigurations.yubikeyLive.aarch64-linux = mkSystem "aarch64-linux";
    formatter.x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
    formatter.aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
  };
}
