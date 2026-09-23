{ config, pkgs, ... }: {
  # fixes dovecot2 bug in 23.11 release: https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/issues/275
  # services.dovecot2.sieve.extensions = [ "fileinto" ];
  mailserver = {
    enable = true;
    stateVersion = 3;
    fqdn = "mail.pifinder.eu";
    domains = [ "pifinder.eu" ];
    enablePop3Ssl = true;
    enableSubmission = true;

    # 2048-bit key, made on 2026-09-23 and published as
    # mail2026._domainkey.pifinder.eu. The old 1024-bit "mail" key is unused.
    dkim.defaults.selector = "mail2026";

    # A list of all login accounts. To create the password hashes, use
    # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
    accounts = {
      "info@pifinder.eu" = {
        hashedPassword = "$2b$05$JPUpRnYe4HLFYMf5v13TJepsMM7WX0aAbdSKDK0rq5FFaTibLGN/i";
        # DMARC and TLS-RPT reports go to info@. The DNS records name these
        # addresses, so they must exist.
        aliases = [
          "postmaster@pifinder.eu"
          "dmarc-reports@pifinder.eu"
          "tls-reports@pifinder.eu"
        ];
      };
    };

    # Use Let's Encrypt certificates. Note that this needs to set up a stripped
    # down nginx and opens port 80.
    # certificateScheme = "manual";
    x509.privateKeyFile = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.pifinder.eu/mail.pifinder.eu.key";
    x509.certificateFile = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.pifinder.eu/mail.pifinder.eu.crt";
  };
  # postfix-tlspol can only use the socket that its .socket unit passes to it.
  # Its sandbox blocks AF_UNIX, so it cannot open the socket itself. A switch
  # can start the service before the socket, and then it fails every 5
  # seconds until the next switch. This happened on 4 Aug, 22 Aug and 23 Sep.
  systemd.services.postfix-tlspol = {
    requires = [ "postfix-tlspol.socket" ];
    after = [ "postfix-tlspol.socket" ];
  };

  # rspamd asks the blocklists (Spamhaus, URIBL) through DNS. They refuse
  # queries from public resolvers, and resolv.conf points at Tailscale, which
  # forwards to Google. The mailserver's own kresd on 127.0.0.1 asks them
  # directly, so rspamd uses it.
  services.rspamd.locals."options.inc".text = ''
    dns {
      nameserver = ["127.0.0.1:53"];
    }
  '';

  # Caddy renews the mail certificate, but Dovecot keeps the old one in
  # memory until it reloads. Reload both mail daemons when the file changes.
  systemd.paths.mail-cert-reload = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = config.mailserver.x509.certificateFile;
  };
  systemd.services.mail-cert-reload = {
    description = "Reload Postfix and Dovecot after a certificate renewal";
    serviceConfig.Type = "oneshot";
    script = "${pkgs.systemd}/bin/systemctl reload postfix.service dovecot.service";
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "postmaster@pifinder.eu";
  environment.systemPackages = [ pkgs.dovecot_pigeonhole ];
}

