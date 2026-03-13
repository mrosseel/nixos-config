{ pkgs, ... }:

{
  # environment.etc."caddy/pifinder-eu" = {
  #   source = /home/mike/pifinder-eu;
  #   mode = "0777";  # Adjust the mode according to your security requirements
  # };
 services.caddy = {
    enable = true;
    virtualHosts."www.pifinder.eu" = {
      extraConfig = ''
        redir https://pifinder.eu{uri} permanent
      '';
    };
    virtualHosts."pifinder.eu" = {
      extraConfig = ''
        encode gzip
        reverse_proxy localhost:5002
        header {
          # Strict Transport Security
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

          # XSS Protection
          X-XSS-Protection "1; mode=block"

          # MIME Type Sniffing Protection
          X-Content-Type-Options "nosniff"

          # Clickjacking Protection
          X-Frame-Options "DENY"

          # Content Security Policy with updated directives
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net https://cdn.tailwindcss.com; style-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net; font-src 'self' https://cdn.jsdelivr.net; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; upgrade-insecure-requests"

          # Referrer Policy
          Referrer-Policy "strict-origin-when-cross-origin"

          # Cache Control
          Cache-Control "public, max-age=15, must-revalidate"

          # Permissions Policy (formerly Feature Policy)
          Permissions-Policy "accelerometer=(), ambient-light-sensor=(), autoplay=(self), camera=(), encrypted-media=(), fullscreen=(self), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()"

          # Remove Server Header (if applicable)
          -Server
        }
    '';
    };
    virtualHosts."mail.pifinder.eu".extraConfig = ''
    '';
    virtualHosts."catalogs.pifinder.eu" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8100
        }

        handle /catalog_images/* {
          root * /var/www/pifinder-catalogs
          file_server

          @hotlink not header Referer *catalogs.pifinder.eu*
          respond @hotlink 403

          header Cache-Control "public, max-age=86400"
        }

        handle {
          root * /var/www/pifinder-catalogs
          @file file
          handle @file {
            file_server
          }
          handle {
            reverse_proxy localhost:8100
          }
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-XSS-Protection "1; mode=block"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; upgrade-insecure-requests"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=15, must-revalidate"
          -Server
        }
      '';
    };
    virtualHosts."blog.miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/blog
        file_server
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=3600, must-revalidate"
          -Server
        }
        @static path *.css *.js *.png *.jpg *.jpeg *.gif *.webp *.avif *.woff2
        header @static Cache-Control "public, max-age=31536000, immutable"
      '';
    };
    virtualHosts."test.pifinder.eu" = {
      extraConfig = ''
          encode gzip
          reverse_proxy localhost:5001
          header {
            # Strict Transport Security
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            # XSS Protection
            X-XSS-Protection "1; mode=block"
            # MIME Type Sniffing Protection
            X-Content-Type-Options "nosniff"
            # Clickjacking Protection
            X-Frame-Options "DENY"
            # Content Security Policy with FIXED style-src and font-src to include jsdelivr.net
            Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net https://cdn.tailwindcss.com; style-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net; font-src 'self' https://cdn.jsdelivr.net; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; upgrade-insecure-requests"

            # Referrer Policy
            Referrer-Policy "strict-origin-when-cross-origin"
            # Cache Control
            Cache-Control "public, max-age=15, must-revalidate"
            # Permissions Policy (formerly Feature Policy) - FIXED to remove ambient-light-sensor
            Permissions-Policy "accelerometer=(), autoplay=(self), camera=(), encrypted-media=(), fullscreen=(self), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()"
            # Remove Server Header (if applicable)
            -Server
          }
        '';
    };
    virtualHosts."starnightshop.miker.be" = {
      extraConfig = ''
        encode gzip
        reverse_proxy localhost:5003
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
    virtualHosts."shop.starnights.be" = {
      extraConfig = ''
        encode gzip
        reverse_proxy localhost:5003
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
  };
  networking.firewall = {
    allowedTCPPorts = [ 80 443];
    allowedUDPPorts = [ 53 ];
  };
}
