{ pkgs, inputs, ... }:

let
  # Content-Security-Policy for rays.miker.be. All script is in app.js, with
  # no inline script and no inline handlers. Inline <style> stays.
  raysCsp = builtins.concatStringsSep "; " [
    "default-src 'self'"
    "script-src 'self'"
    "style-src 'self' 'unsafe-inline'"
    "img-src 'self' data:"
    "connect-src 'self'"
    "font-src 'self'"
    "object-src 'none'"
    "base-uri 'none'"
    "form-action 'none'"
    "frame-ancestors 'none'"
  ];
in
{
 imports = [ ./thailand-planner.nix ./thailand-drive-export.nix ];
 services.caddy = {
    enable = true;
    globalConfig = ''
      # How long a reload waits for the connections of the old server before
      # it closes them. Caddy's default is eternal, so a reload can wait for
      # ever.
      #
      # A deploy is where that bites. systemd stops a backend this host
      # proxies, and Caddy holds each waiting request against a service that
      # is down. Clients retry every few seconds, so the set of open
      # connections refills and never reaches zero. On 18 September 2026 a
      # reload on hexalon.io waited until systemd killed it ninety seconds
      # later, and the deploy reported failure on a machine that had already
      # switched. This host runs the same shape of deploy.
      #
      # Ten seconds bounds it. Every ordinary request finishes well inside
      # that, and a request cut short is one a client retries.
      grace_period 10s

      # The HTTP metrics, with a host label on each series. Without the label
      # every site on this host shares one count, and the Hexalon Health tab
      # on beta counts the errors of every other site as its own.
      metrics {
        per_host
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
        # zstd first: it beats gzip on the large CSS the shop serves, and
        # Caddy falls back to gzip for a browser that does not accept it.
        encode zstd gzip
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

          # Content Security Policy.
          # The shop serves its whole front end from /static/vendor, so no
          # other origin is needed. 'unsafe-inline' for scripts and styles
          # stays, because FastHTML and MonsterUI write inline blocks and
          # inline style attributes.
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests"

          # Referrer Policy
          Referrer-Policy "strict-origin-when-cross-origin"

          # Permissions Policy (formerly Feature Policy)
          Permissions-Policy "accelerometer=(), ambient-light-sensor=(), autoplay=(self), camera=(), encrypted-media=(), fullscreen=(self), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=()"

          # Remove Server Header (if applicable)
          -Server
        }

        # Cache-Control is not set here. Caddy keeps only one value for a
        # header across matchers, so the shop sets it per path instead.
    '';
    };
    virtualHosts."mail.pifinder.eu".extraConfig = ''
    '';
    # MTA-STS policy for inbound mail to pifinder.eu. Start in "testing":
    # senders report TLS faults to tls-reports@ but still deliver. Change to
    # "enforce" when the reports are clean, and then change the id in the
    # _mta-sts.pifinder.eu TXT record so senders fetch the policy again.
    # Needs DNS: A/AAAA mta-sts.pifinder.eu, TXT _mta-sts and _smtp._tls.
    virtualHosts."mta-sts.pifinder.eu".extraConfig = ''
      handle /.well-known/mta-sts.txt {
        header Content-Type "text/plain; charset=utf-8"
        respond <<EOF
          version: STSv1
          mode: testing
          mx: mail.pifinder.eu
          max_age: 86400
          EOF 200
      }
      respond 404
    '';
    virtualHosts."catalogs.pifinder.eu" = {
      extraConfig = ''
        encode gzip

        handle /api/* {
          reverse_proxy localhost:8100
        }

        handle /catalog_images/* {
          root * /var/www/catalogs.pifinder.eu
          file_server

          @hotlink not header Referer *catalogs.pifinder.eu*
          respond @hotlink 403

          header Cache-Control "public, max-age=86400"
        }

        handle {
          root * /var/www/catalogs.pifinder.eu
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
    # 3D dice tray: shake or tilt the phone to throw. Served top level
    # and same origin on purpose. An embedded page is refused the
    # accelerometer, which kills the only input that matters here.
    # The site is static files in ./dice, so a rebuild ships it. The 3D
    # libraries and fonts are copies in ./dice, not CDN links, so the page
    # makes no request to another host and the CSP can be strict.
    virtualHosts."dice.miker.be" = {
      extraConfig = ''
        encode gzip
        root * ${./dice}
        file_server
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          # Also stops anyone else embedding it, which would break motion.
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          # The sensors the dice need. Omit these and shake and tilt die.
          Permissions-Policy "accelerometer=(self), gyroscope=(self)"
          # No inline script or style: the page loads app.js and app.css.
          # data: is for the favicon.
          Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
          Cache-Control "no-cache, must-revalidate"
          -Server
        }
        # The version is in each file name, so these never change.
        @versioned path /vendor/* /fonts/*
        header @versioned {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }
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
        root * /var/www/blog.miker.be
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
    # Lunar ray (clair-obscur) event predictor: static page driven by a
    # precomputed event blob, plus DEM-rendered feature images. Regenerated
    # from ~/dev/LunarRays (py/lunar_rays.py generate) and rsync'd.
    virtualHosts."rays.miker.be" = {
      extraConfig = ''
        # events.bin is application/octet-stream and compresses well. The
        # webp images are compressed already and are left out.
        encode {
          zstd
          gzip
          match {
            header Content-Type text/*
            header Content-Type application/json*
            header Content-Type application/javascript*
            header Content-Type application/octet-stream*
            header Content-Type image/svg+xml*
          }
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Content-Security-Policy "${raysCsp}"
          -Server
        }
        # Thumbs up/down counter, see rays-votes.py. Vote totals change
        # all the time and must never come from a cache.
        handle /api/* {
          header {
            Cache-Control "no-store"
            defer
          }
          reverse_proxy 127.0.0.1:8322
        }
        handle {
          # Build metadata (events.build.json, assets.build.json) is for
          # the deploy script only.
          @build path *.build.json
          respond @build 404

          root * /var/www/rays.miker.be
          file_server

          # Feature images are re-rendered in place under the same slug, so
          # they cannot be immutable. Cache them for an hour, then revalidate.
          @img {
            path /img/*
            not path *.json
          }
          header @img {
            Cache-Control "public, max-age=3600, must-revalidate"
            defer
          }
          # Everything else changes in place: the page, app.js, events.bin
          # and every *.json, img/manifest.json included. The browser keeps
          # a copy and revalidates it on each use with the ETag.
          @revalidate {
            not {
              path /img/*
              not path *.json
            }
          }
          header @revalidate {
            Cache-Control "no-cache"
            defer
          }
        }
      '';
    };
    # Hidden Treasures observing scorecard: a single static page regenerated from
    # a PiFinder observation log and rsync'd from the workstation
    # (~/dev/amateur_astro/hiddentreasures.miker.be/deploy.sh).
    virtualHosts."hiddentreasures.miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/hiddentreasures.miker.be
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

    # PiFinder delta server (pifinder-differ.nix). Devices ask for byte-level
    # patches here before falling back to full downloads from the cache.
    # Only the device-facing routes are public; /warm, /status and /pairs are
    # operator surface and stay loopback-only (curl on the host / SSH).
    # NB: needs a DNS A record deltas.pifinder.eu -> this host before ACME
    # can issue the certificate.
    virtualHosts."deltas.pifinder.eu" = {
      extraConfig = ''
        @public path /delta /update-start /blobs/* /health

        # handle blocks, not a bare `respond`: respond sorts BEFORE
        # reverse_proxy in Caddy's directive order and would 403 everything.
        handle @public {
          # Patch blobs are content-addressed (base-hash_target-hash) and
          # immutable — cache forever, anywhere.
          @blobs path /blobs/*
          header @blobs Cache-Control "public, max-age=31536000, immutable"
          reverse_proxy localhost:8090
        }
        handle {
          respond 403
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
          root * /var/www/messier.miker.be
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
    # 1901 — face-to-face Diplomacy adjudicator (see 1901.nix). The Go server
    # serves both the API and the built frontend, so this is a plain proxy.
    # No CSP here: the SPA is versioned with the server, not with this file.
    virtualHosts."1901.miker.be" = {
      extraConfig = ''
        encode gzip
        reverse_proxy localhost:8190
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          # SAMEORIGIN, not DENY: the design gallery at /dev/screens shows each
          # screen in a real iframe of this same site, because a div with a
          # width on it is not a phone — media queries, 100vh and every fixed
          # sheet answer to the viewport. Other sites still cannot frame this
          # one, which is what the header is for.
          X-Frame-Options "SAMEORIGIN"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
        # Vite-hashed bundles are content-addressed by filename.
        @assets path /assets/*
        header @assets {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }
      '';
    };
    # Astropics, an astronomy image website (see astropics.nix). The API
    # also serves /media/*, the images stored on this host. The React Router
    # SSR server answers everything else. No CSP here: the pages are
    # versioned with the astropics repo, not with this file.
    # Needs a DNS A record astropics.miker.be -> this host.
    virtualHosts."astropics.miker.be" = {
      extraConfig = ''
        encode gzip
        # An upload can be 80 MB. Caddy refuses a larger body with 413.
        request_body {
          max_size 100MB
        }
        handle /api/* {
          reverse_proxy 127.0.0.1:8300
        }
        handle /media/* {
          # A stored image never changes. A new version gets a new name.
          header {
            Cache-Control "public, max-age=31536000, immutable"
            defer
          }
          reverse_proxy 127.0.0.1:8300
        }
        handle {
          reverse_proxy 127.0.0.1:8301
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
    # Testalon, the Hexalon test deployment (see testalon.nix). The Rust
    # server holds the games and the bots; the page is a second package of
    # the same revision. Caddy decides which is which, so the bundle can ask
    # its own origin and work under any host name.
    #
    # Neither half is in this closure. GitHub deploys both on a push to
    # master and moves two pointers under /var/lib/testalon, so a rebuild of
    # this machine does not disturb what is deployed, and a deploy does not
    # rebuild this machine. The page is read through the pointer on every
    # request, so it needs no reload here.
    virtualHosts."testalon.miker.be" = {
      # beta.hexalon.io is the name people are given. testalon.miker.be is
      # the name the machine has always answered to, kept so a link from
      # before this alias still opens. One certificate covers both.
      serverAliases = [ "beta.hexalon.io" ];
      extraConfig = ''
        encode gzip
        # Two handlers, and they must not share: `try_files` rewrites a path
        # that names no file to /index.html, which would rewrite the API paths
        # out from under the proxy before it ever saw them.
        @api path /public/* /private/*
        handle @api {
          # The websocket upgrade needs no special handling here: the proxy
          # carries it.
          #
          # A deploy stops the game server and starts it again, which takes
          # about three seconds. Caddy holds a request that cannot connect for
          # up to twenty seconds and dials again every 300 ms, so a restart
          # costs a player a pause rather than an error. Only a failed dial is
          # retried, so no request reaches the server twice.
          reverse_proxy localhost:8192 {
            lb_try_duration 20s
            lb_try_interval 300ms
          }
        }
        handle {
          root * /var/lib/testalon/web
          # One page, many addresses: a table lives at /?room=..., and a
          # reload must reach the same file rather than a 404.
          try_files {path} /index.html
          file_server
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          -Server
        }
        # Vite hashes every bundle into its filename, so a name never changes
        # meaning. The WebAssembly engine is hashed with them.
        @assets path /assets/*
        header @assets {
          Cache-Control "public, max-age=31536000, immutable"
          defer
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
    # Static siting guide for the 12 Aug 2026 total solar eclipse. Plain files,
    # no backend; the aerial photos and maps never change once written.
    virtualHosts."spain2026.miker.be" = {
      extraConfig = ''
        encode gzip
        root * /var/www/spain2026.miker.be
        file_server
        @immutable path /assets/*
        header @immutable {
          Cache-Control "public, max-age=31536000, immutable"
          defer
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
          Cache-Control "public, max-age=1800, must-revalidate"
          -Server
        }
      '';
    };
    # Catch-all for names that resolve here through the *.miker.be
    # wildcard but have no site of their own. Declared vhosts are more
    # specific and still win, including their automatic HTTPS redirect.
    # Over HTTPS an undeclared name still fails at the handshake: Caddy
    # holds no certificate for it, and issuing one on demand would let
    # anyone mint certificates on this box.
    virtualHosts."http://" = {
      extraConfig = ''
        respond "Not found" 404
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
    # Scorecard web root owned by mike so the rsync deploy needs no remote sudo.
    "d /var/www/hiddentreasures.miker.be 0755 mike users -"
    # Eclipse siting guide, same rsync-deploy pattern.
    "d /var/www/spain2026.miker.be 0755 mike users -"
    # Lunar rays predictor, same rsync-deploy pattern (~/dev/LunarRays/deploy.sh).
    "d /var/www/rays.miker.be 0755 mike users -"
  ];
}
