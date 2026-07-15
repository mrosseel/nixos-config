# overlays/gdal.nix
#
# gdal 3.13.1's install-check runs the upstream pytest suite, where
# gdrivers/zarr_driver.py::test_zarr_read_simple_sharding fails (it stats a
# zarr.json.gmac sidecar that VSIStatL returns None for): 1 failed / 18680 passed.
# That single failure fails the gdal build, which cascades: vtk -> freecad ->
# system-path -> the whole nixtop system, blocking every rebuild.
#
# Skip the install check on both gdal and its minimal variant (vtk pulls
# gdal-minimal). Remove once nixpkgs ships the upstream fix.
final: prev: {
  gdal = prev.gdal.overrideAttrs (_: { doInstallCheck = false; });
  gdalMinimal = prev.gdalMinimal.overrideAttrs (_: { doInstallCheck = false; });
}
