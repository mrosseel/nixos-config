# overlays/vtk.nix
#
# Same gdal 3.13 const-API breakage as overlays/pdal.nix: VTK 9.5.2's
# IO/GDAL/vtkGDALRasterReader.cxx (lines 185, 881) passes gdal's now-const
# CSLConstList where a char** is expected:
#   error: invalid conversion from 'CSLConstList' {aka 'const char* const*'} to 'char**'
# -fpermissive downgrades the const-conversion to a warning so vtk builds.
#
# vtk feeds freecad -> system-path -> the nixtop system. Remove once nixpkgs
# ships a vtk patched for gdal 3.13.
final: prev: {
  vtk = prev.vtk.overrideAttrs (o: {
    NIX_CFLAGS_COMPILE = (o.NIX_CFLAGS_COMPILE or "") + " -fpermissive";
  });
}
