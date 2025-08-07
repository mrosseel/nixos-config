{ config, pkgs, ... }: {
  # fixes dovecot2 bug in 23.11 release: https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/issues/275
  # services.dovecot2.sieve.extensions = [ "fileinto" ];
  mailserver = {
    enable = true;
    stateVersion = 3;
    fqdn = "mail.pifinder.eu";
    domains = [ "pifinder.eu" ];
    enablePop3Ssl = true;

    # A list of all login accounts. To create the password hashes, use
    # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
    loginAccounts = {
      "info@pifinder.eu" = {
        hashedPassword = "$2b$05$JPUpRnYe4HLFYMf5v13TJepsMM7WX0aAbdSKDK0rq5FFaTibLGN/i";
        aliases = ["postmaster@pifinder.eu"];
      };
    };

    # Use Let's Encrypt certificates. Note that this needs to set up a stripped
    # down nginx and opens port 80.
    certificateScheme = "manual";
    keyFile = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.pifinder.eu/mail.pifinder.eu.key";
    certificateFile = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.pifinder.eu/mail.pifinder.eu.crt";
  };
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "postmaster@pifinder.eu";
  environment.systemPackages = [ pkgs.dovecot_pigeonhole ];
}

