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
}
