# overlays/pdal.nix
#
# pdal 2.9.3 fails to compile against gdal 3.13, which made several C API
# signatures const (CSLConstList). pdal/private/gdal/Raster.cpp:704 passes the
# result where a char** is expected:
#   error: invalid conversion from 'CSLConstList' {aka 'const char* const*'} to 'char**'
# gcc 15 rejects this by default. -fpermissive downgrades the const-conversion
# to a warning so pdal builds; the upstream fix is a proper const-correct patch.
#
# pdal feeds vtk -> freecad -> system-path -> the nixtop system, so without this
# the whole rebuild fails. Remove once nixpkgs ships a pdal patched for gdal 3.13.
final: prev: {
  pdal = prev.pdal.overrideAttrs (o: {
    NIX_CFLAGS_COMPILE = (o.NIX_CFLAGS_COMPILE or "") + " -fpermissive";
  });
}
