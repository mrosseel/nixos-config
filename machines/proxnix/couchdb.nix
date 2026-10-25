{ config, lib, pkgs, ... }:

{
  # TEMPORARY. CouchDB 3.5.3 (2026-10-12) fixes six CVEs published on
  # 2026-10-20, among them a pre-authentication gzip decompression bomb on
  # POST /_session (CVE-2026-90797) and an auth bypass on prefixed _users
  # and _replicator databases (CVE-2026-90800). This instance is reachable
  # from the internet for Obsidian LiveSync. nixos-unstable still has 3.5.2
  # (nixpkgs PR 572477 is open). Remove this override when
  #   nix eval --raw .#nixosConfigurations.proxnix.pkgs.couchdb3.version
  # prints 3.5.3 or newer.
  services.couchdb = {
    enable = true;
    package = pkgs.couchdb3.overrideAttrs (old: rec {
      version = "3.5.3";
      src = pkgs.fetchurl {
        url = "mirror://apache/couchdb/source/${version}/apache-couchdb-${version}.tar.gz";
        hash = "sha256-rguzdMyJkA1ssd+42OgMeZGG3PLRQ8qIYpbCMK9CCJY=";
      };
    });
    bindAddress = "0.0.0.0";

    extraConfig = {
      couchdb = {
        single_node = true;
        max_document_size = 50000000;
      };
      chttpd = {
        require_valid_user = true;
        max_http_request_size = 4294967296;
      };
      chttpd_auth = {
        require_valid_user = true;
      };
      httpd = {
        enable_cors = true;
      };
      cors = {
        origins = "*";
        credentials = true;
        methods = "GET, PUT, POST, HEAD, DELETE";
        headers = "accept, authorization, content-type, origin, referer, x-csrf-token";
      };
    };

    extraConfigFiles = [
      "/etc/couchdb/admin.ini"
    ];
  };
}
