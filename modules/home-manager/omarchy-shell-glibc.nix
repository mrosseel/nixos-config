{ pkgs, lib, options, ... }:
let
  # The omarchy home-manager module defines config.omarchy.*; nixair and the
  # servers pull modules/home-manager without it.
  hasOmarchy = options ? omarchy;
in
{
  # The Omarchy shell is the lock screen, and it loads the PAM modules from
  # /etc/pam.d when you type the password. A rebuild that moves glibc forward
  # points those files at modules that need the new glibc. The shell still runs
  # on the old glibc, so it cannot load them and rejects every password.
  #
  # After each switch, compare the glibc of the running shell with the newest
  # glibc symbol version that the lock PAM modules need. If the shell is too
  # old, restart it. omarchy-restart-shell locks the session again if it was
  # locked. It refuses while the old locker is active, so stop that one first.
  home.activation.restartOmarchyShellOnGlibcChange = lib.mkIf hasOmarchy (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      export PATH="$HOME/.local/share/omarchy/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      shellDir="$HOME/.local/share/omarchy/shell"
      pamFile=/etc/pam.d/omarchy-lock-password
      shellPid=$(${pkgs.procps}/bin/pgrep -o -u "$USER" -f "quickshell -n -p $shellDir" || true)

      if [ -n "$shellPid" ] && [ -r "$pamFile" ]; then
        runningGlibc=$(${pkgs.gnugrep}/bin/grep -o '/nix/store/[^ ]*-glibc-[0-9.]*-[^/]*/lib/libc\.so\.6' "/proc/$shellPid/maps" 2>/dev/null \
          | ${pkgs.gnused}/bin/sed -n 's|.*-glibc-\([0-9]*\.[0-9]*\).*|\1|p' | head -n 1)
        neededGlibc=$(${pkgs.gnugrep}/bin/grep -o '/nix/store/[^ ]*\.so' "$pamFile" | sort -u \
          | while read -r module; do ${pkgs.binutils-unwrapped}/bin/readelf -V --wide "$module" 2>/dev/null; done \
          | ${pkgs.gnugrep}/bin/grep -o 'GLIBC_[0-9.]*' | ${pkgs.gnused}/bin/sed 's/GLIBC_//' | sort -V | tail -n 1)

        if [ -n "$runningGlibc" ] && [ -n "$neededGlibc" ] \
          && [ "$(printf '%s\n%s\n' "$runningGlibc" "$neededGlibc" | sort -V | head -n 1)" != "$neededGlibc" ]; then
          echo "Omarchy shell runs glibc $runningGlibc, but the lock PAM modules need $neededGlibc. Restarting the shell."
          run timeout 5 quickshell kill -p "$shellDir" --any-display || true
          run omarchy-restart-shell || echo "Could not restart the Omarchy shell. Run omarchy-restart-shell yourself."
        fi
      fi
    ''
  );
}
