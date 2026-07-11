{ pkgs, ... }:

{
 imports = [ ./thailand-planner.nix ];
 services.caddy = {
    enable = true;
    globalConfig = ''
      servers {
        metrics
      }
    '';
    logFormat = ''
      output file /var/log/caddy/access.log {
        roll_size 100MiB
        roll_keep 5
        mode 0640
      }
      format json
    '';
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
    virtualHosts."miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/miker.be
        file_server
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=3600, must-revalidate"
          -Server
        }
      '';
    };
    virtualHosts."mars.miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/mars.miker.be
        file_server
        # Tile pyramids, vendored Cesium, mission media: never change
        # once published — cache forever.
        @assets path /tiles/* /vendor/cesium/* /images/*
        header @assets Cache-Control "public, max-age=31536000, immutable"
        # JS / CSS / HTML / manifests: revalidate on every reload so code
        # updates ship immediately without users having to clear cache.
        @code path /index.html /*.html /js/* /css/* /locales/* /data/* /
        header @code Cache-Control "no-cache, must-revalidate"
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
    virtualHosts."www.miker.be" = {
      extraConfig = ''
        redir https://miker.be{uri} permanent
      '';
    };
    # Private family trip planner (static Vite SPA). Basic-auth gated so the
    # itinerary isn't public. Files rsync'd to /var/www/thailand.miker.be.
    virtualHosts."thailand.miker.be" = {
      extraConfig = ''
        encode gzip
        basic_auth {
          family $2a$14$s/JqG2aVwS.OmPLAcfmes.ydNHOWCjoRHs.PF80qI.HNftlvfqsde
        }
        # Plan persistence service (see thailand-planner.nix).
        handle /api/* {
          reverse_proxy localhost:8010
        }
        handle {
          root * /var/www/thailand.miker.be
          file_server
          try_files {path} /index.html
        }
        # Vite-hashed bundles are immutable, content-addressed by filename.
        @assets path /assets/*
        header @assets Cache-Control "public, max-age=31536000, immutable"
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "no-cache, must-revalidate"
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
        @static path_regexp \.(css|js|png|jpg|jpeg|gif|webp|avif|svg|woff2|pdf)$
        header @static {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }
      '';
    };
    virtualHosts."joeri.miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/joeri.miker.be
        php_fastcgi unix//run/phpfpm/joeri.sock
        file_server
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=3600, must-revalidate"
          -Server
        }
        @static path_regexp \.(css|js|png|jpg|jpeg|gif|webp|avif|svg|woff2|pdf)$
        header @static {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }
      '';
    };
    # PiFinder NixOS binary cache (Attic). See attic-service.nix.
    # Plain reverse proxy — no HTML headers/CSP because clients are the
    # Nix daemon, not browsers; large NAR/chunk uploads must not be capped.
    virtualHosts."cache.pifinder.eu" = {
      extraConfig = ''
        reverse_proxy localhost:8080 {
          # Don't buffer request bodies — push uploads can be many MB.
          flush_interval -1
        }
      '';
    };

    # PiFinder file host — tarballs + desync chunk store, served as static
    # files next to the Attic cache. Read-only over HTTPS; uploads happen over
    # SSH/rsync into the mike-owned web root (no upload daemon). browse renders
    # an auto-generated directory index — every filename is publicly listable.
    virtualHosts."files.pifinder.eu" = {
      extraConfig = ''
        encode gzip
        root * /var/www/files.pifinder.eu
        file_server browse

        # Content-addressed desync chunks never change — cache forever.
        @chunks path /castr/*
        header @chunks Cache-Control "public, max-age=31536000, immutable"

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=300, must-revalidate"
          -Server
        }
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
    virtualHosts."astro.miker.be" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8003
        }

        handle {
          root * /var/www/astro.miker.be
          file_server
          try_files {path} /index.html
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
    virtualHosts."sun.miker.be" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8004
        }

        handle {
          root * /var/www/sun.miker.be
          file_server
          try_files {path} /index.html
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
    virtualHosts."messier.miker.be" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8001
        }

        handle {
          root * /var/www/messier
          file_server
          try_files {path} /index.html
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
      '';
    };
    virtualHosts."asterisms.miker.be" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8002
        }

        handle {
          root * /var/www/asterisms.miker.be
          file_server
          try_files {path} /index.html
        }

        # Vite-hashed bundles (immutable, content-addressed by filename).
        @assets path /assets/*
        header @assets {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }

        # Per-asterism images: id is content-derived, file body never changes once written.
        @asterism_imgs path /img/*
        header @asterism_imgs {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }

        # Catalog JSON + PiFinder lists: stable URLs but mutable content. Short cache.
        @data path /data/* /pifinder/*
        header @data {
          Cache-Control "public, max-age=120, must-revalidate"
          defer
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=300, must-revalidate"
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

  # Pre-create the mars.miker.be web root owned by mike so the kiosk asset
  # rsync from the workstation doesn't need remote sudo.
  systemd.tmpfiles.rules = [
    "d /var/www/mars.miker.be 0755 mike users -"
    # Trip planner web root owned by mike so dist rsync needs no remote sudo.
    "d /var/www/thailand.miker.be 0755 mike users -"
    # PiFinder file host (files.pifinder.eu): web root + desync chunk store,
    # owned by mike so rsync uploads from the workstation need no remote sudo.
    "d /var/www/files.pifinder.eu 0755 mike users -"
    "d /var/www/files.pifinder.eu/castr 0755 mike users -"
  ];
}
