{ config, pkgs, ... }: {
  imports = [
    (builtins.fetchTarball {
      # Pick a release version you are interested in and set its hash, e.g.
      url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/nixos-24.05/nixos-mailserver-nixos-24.05.tar.gz";
      # To get the sha256 of the nixos-mailserver tarball, we can use the nix-prefetch-url command:
      # release="nixos-23.05"; nix-prefetch-url "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/${release}/nixos-mailserver-${release}.tar.gz" --unpack
      sha256 = "0clvw4622mqzk1aqw1qn6shl9pai097q62mq1ibzscnjayhp278b";
    })
  ];
  # fixes dovecot2 bug in 23.11 release: https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/issues/275
  # services.dovecot2.sieve.extensions = [ "fileinto" ];
  mailserver = {
    enable = true;
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
}

