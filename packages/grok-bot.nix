# Grok Bot, xAI's desktop agent. Not in nixpkgs; nixpkgs has grok-build, which
# is the CLI, a different product.
#
# The app is a Cursor build, so it ships only as a .deb — no AppImage, no
# tarball. x.ai/bot advertises macOS and Windows only, and links just the macOS
# dmg, but the Linux debs are published and reachable:
#
#   https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54
#   https://api2.cursor.sh/updates/download/stable/linux-arm64/grok-bot-<its own id>
#
# Those redirect to downloads.cursor.com under a build sha, which is why `commit`
# sits beside `version` below. To bump: follow the linux-x64 redirect, take the
# new sha, version and hash. The arm64 id is not known; add it when needed.
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemdLibs,
  xdg-utils,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbfile,
  libxrandr,
  libxscrnsaver,
  libxtst,
}:

let
  version = "0.36.0";
  commit = "9465f3ae75550511296fabbb7a4b6fc8afe9e408";

  sources = {
    x86_64-linux = {
      arch = "x64";
      deb = "amd64";
      hash = "sha256-lItBd2Z9mgORXBruSX58VDhwU5PagIOmrwF3KIUS0H4=";
    };
    aarch64-linux = {
      arch = "arm64";
      deb = "arm64";
      hash = "sha256-us7L3xxPMJarZyTJDnD4D+kHIa4Ft/2Z0FdNRwbCe7I=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "grok-bot: no build for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "grok-bot";
  inherit version;

  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/${commit}/linux/${source.arch}/grok-bot_${version}_${source.deb}.deb";
    inherit (source) hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    libxkbcommon
    nspr
    nss
    pango
    systemdLibs
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbfile
    libxrandr
    libxscrnsaver
    libxtst
  ];

  # wrapGAppsHook3 would wrap the 210 MB Electron binary in place; the wrapper
  # below does that instead, so the hook only has to export the GTK variables.
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/grok-bot $out/bin
    cp -r "opt/Grok Bot/." $out/share/grok-bot/
    cp -r usr/share/applications usr/share/icons $out/share/

    # chrome-sandbox needs setuid root, which the store cannot grant. Electron
    # falls back to the user-namespace sandbox, which NixOS allows.
    rm -f $out/share/grok-bot/chrome-sandbox

    substituteInPlace $out/share/applications/grok-bot.desktop \
      --replace-fail "Exec=grok-bot" "Exec=$out/bin/grok-bot"

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/share/grok-bot/grok-bot $out/bin/grok-bot \
      "''${gappsWrapperArgs[@]}" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Desktop agent by xAI, built on Cursor";
    homepage = "https://x.ai/bot";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = lib.attrNames sources;
    mainProgram = "grok-bot";
  };
}
