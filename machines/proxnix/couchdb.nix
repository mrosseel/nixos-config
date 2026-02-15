{ config, lib, pkgs, ... }:

{
  services.couchdb = {
    enable = true;
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
