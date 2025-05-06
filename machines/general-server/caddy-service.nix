{ pkgs, ... }:

{
  # environment.etc."caddy/pifinder-eu" = {
  #   source = /home/mike/pifinder-eu;
  #   mode = "0777";  # Adjust the mode according to your security requirements
  # };
 services.caddy = {
    enable = true;
    virtualHosts."pifinder.eu" = {
      serverAliases = [ "www.pifinder.eu" ];
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

          # Content Security Policy with updated directives
          Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net https://cdn.tailwindcss.com; style-src 'self' 'unsafe-inline' https://unpkg.com; connect-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'self'; upgrade-insecure-requests"

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
  };
  networking.firewall = {
    allowedTCPPorts = [ 80 443];
    allowedUDPPorts = [ 53 ];
  };
}
