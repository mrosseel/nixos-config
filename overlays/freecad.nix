# overlays/freecad.nix
#
# freecad 1.1.1's XDGData/FreeCAD.thumbnailer.in carries a path-prefixed command:
#   TryExec=@CMAKE_INSTALL_BINDIR@/freecad-thumbnailer
#   Exec=@CMAKE_INSTALL_BINDIR@/freecad-thumbnailer -s %s %i %o
# so the installed FreeCAD.thumbnailer ends up with e.g. TryExec=bin/freecad-thumbnailer.
# nixpkgs' thumbnailer fixup rewrites the bare "TryExec=freecad-thumbnailer" during
# installPhase, and since substituteInPlace now hard-fails on a missing pattern the
# whole freecad build dies:
#   substituteStream() ... ERROR: pattern TryExec=freecad-thumbnailer doesn't match
#
# Strip the @CMAKE_INSTALL_BINDIR@/ prefix in the template (postPatch, well before
# install) so the generated file has the bare command the fixup looks for; the fixup
# then turns it into an absolute store path. Remove once nixpkgs' thumbnailer fixup
# handles the path-prefixed form.
final: prev: {
  freecad = prev.freecad.overrideAttrs (o: {
    postPatch = (o.postPatch or "") + ''
      substituteInPlace src/XDGData/FreeCAD.thumbnailer.in \
        --replace-fail '@CMAKE_INSTALL_BINDIR@/freecad-thumbnailer' 'freecad-thumbnailer'
    '';
  });
}
