# The ArtCraft "Crafting Apps": clean-room Rust reimplementations of Adobe and
# Microsoft programs (https://github.com/storytold). Not in nixpkgs.
#
# Each release has a linux-x86_64 tarball with the GUI, a `<app>-cli` binary,
# a desktop file and icons. The binaries link only to glibc. The GUI loads the
# window system, EGL and Vulkan at run time with dlopen, so those libraries go
# in through `runtimeDependencies`.
#
# Returns an attrset with one package per app. To add an app or bump a version,
# edit `apps` and take the new hash with
#   nix store prefetch-file https://github.com/storytold/<app>/releases/download/v<version>/<app>-<version>-linux-x86_64.tar.gz
{
  autoPatchelfHook,
  dbus,
  fetchurl,
  lib,
  libGL,
  libX11,
  libXcursor,
  libXi,
  libxcb,
  libxkbcommon,
  stdenv,
  vulkan-loader,
  wayland,
}:

let
  apps = {
    lightcraft = {
      version = "0.4.0";
      hash = "sha256-wsdXgLzwWKIcSjEc5X20flnwrC9t1wRYM3aa4QA7VyM=";
      description = "Clean-room reimplementation of Adobe Lightroom in Rust";
    };
    pdfcraft = {
      version = "0.6.0";
      hash = "sha256-mhNuceN7RZ7VdG2+GaNkzoTPXZlcb2yYr2FH2Bg5ClM=";
      description = "Clean-room reimplementation of Adobe Acrobat in Rust";
    };
    photocraft = {
      version = "0.7.0";
      hash = "sha256-ZB+DElL9MbQ+4aEuVy10QuVlLC5b9iPeCFdBw3DwyR0=";
      description = "Clean-room reimplementation of Adobe Photoshop in Rust";
    };
  };

  mkApp =
    pname:
    {
      version,
      hash,
      description,
    }:
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.tar.gz";
        inherit hash;
      };

      nativeBuildInputs = [ autoPatchelfHook ];
      buildInputs = [ stdenv.cc.cc.lib ];

      # getLib, because libdbus-1.so is in the `lib` output of dbus, not `out`.
      # Without it the file dialogs cannot reach the portal.
      runtimeDependencies = map lib.getLib [
        dbus
        libGL
        libX11
        libXcursor
        libXi
        libxcb
        libxkbcommon
        vulkan-loader
        wayland
      ];

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin share $out/
        runHook postInstall
      '';

      meta = {
        inherit description;
        homepage = "https://github.com/storytold/${pname}";
        license = with lib.licenses; [
          asl20
          mit
        ];
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };
in
lib.mapAttrs mkApp apps
