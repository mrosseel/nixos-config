{ ... }: {
  # Inbound mail for nightsky.pics, on the same mailserver as pifinder.eu.
  # Amazon SES sends the app mail. This server only receives mail for info@
  # and sends the replies from it. NixOS merges these lists with the ones in
  # simple-mail-server.nix, so that file does not change.
  #
  # The DNS records name only mail.nightsky.pics, never mail.pifinder.eu.
  # To move this domain to another host, import this module there, copy
  # /var/dkim/nightsky.pics.mail2026.key and /var/vmail/nightsky.pics, and
  # change the A record of mail.nightsky.pics.
  #
  # Until that move, mail apps connect to mail.pifinder.eu, because the
  # certificate has only that name.
  mailserver = {
    domains = [ "nightsky.pics" ];

    # To create the password hash, use
    # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
    accounts = {
      "info@nightsky.pics" = {
        hashedPassword = "$2b$05$48a28eMI5kZiYmshl4ynuuWO7Bqm/3WokwQjvA5YaNEBmYQUV6X82";
        # The DMARC record sends its reports to dmarc-reports@, so it must
        # exist.
        aliases = [
          "postmaster@nightsky.pics"
          "abuse@nightsky.pics"
          "dmarc-reports@nightsky.pics"
        ];
      };
    };
  };

  # The app mail comes from Amazon SES with From nightsky.pics. The contact
  # form sets Reply-To to the address of the visitor, often a freemail address.
  # rspamd then gives a score of 7, so the mail goes to Junk, and greylisting
  # holds it for 5 minutes. Mail that passes DMARC for nightsky.pics gets -10
  # and no greylisting. Only SES and this server can pass that DMARC check.
  services.rspamd.locals."whitelist.conf".text = ''
    rules {
      NIGHTSKY_DMARC {
        domains = ["nightsky.pics"];
        valid_dmarc = true;
        score = -10.0;
        description = "Mail from nightsky.pics that passes DMARC";
      }
    }
  '';
  services.rspamd.locals."greylist.conf".text = ''
    whitelist_symbols = ["NIGHTSKY_DMARC"];
  '';
}
