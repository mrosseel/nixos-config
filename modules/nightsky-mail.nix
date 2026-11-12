{ config, lib, pkgs, ... }:
let
  # The site login of the Inbox tab of nightsky.pics (ADR 0128 in the nightsky
  # repo): a second password for info@ that only the site uses.
  inboxDir = "/var/lib/nightsky-inbox";
  doveadm = lib.getExe' config.services.dovecot2.package "doveadm";
in
{
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

  # The mail worker of nightsky.pics copies info@ over IMAP with read-only
  # commands (ADR 0128). It logs in as info@ with a second password. This unit
  # makes that password at the first start and keeps it in
  # /var/lib/nightsky-inbox/password (root only). systemd gives it to the mail
  # worker as a credential. Dovecot reads the hash from a second passwd file.
  # A wrong password in the first passwd file makes Dovecot try the second one,
  # so the password of the mail apps does not change. The second password works
  # only from this host.
  systemd.services.nightsky-inbox-password = {
    description = "IMAP password of the Nightsky.pics inbox copy";
    before = [ "dovecot.service" "nightsky-mail-worker.service" ];
    wantedBy = [ "dovecot.service" "nightsky-mail-worker.service" "multi-user.target" ];
    path = [ pkgs.openssl pkgs.coreutils pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      StateDirectory = "nightsky-inbox";
      StateDirectoryMode = "0711";
    };
    script = ''
      if [ ! -s ${inboxDir}/password ]; then
        openssl rand -hex 32 > ${inboxDir}/password.new
        mv ${inboxDir}/password.new ${inboxDir}/password
      fi
      hash=$(sed -n '1{p;p;q}' ${inboxDir}/password | ${doveadm} pw -s SHA512-CRYPT)
      test -n "$hash"
      printf 'info@nightsky.pics:%s::::::allow_real_nets=127.0.0.1/32,::1/128\n' "$hash" \
        > ${inboxDir}/dovecot-passwd.new
      chown dovecot2:dovecot2 ${inboxDir}/dovecot-passwd.new
      mv ${inboxDir}/dovecot-passwd.new ${inboxDir}/dovecot-passwd
    '';
  };
  # Only for IMAP: the site password cannot send mail through Postfix.
  services.dovecot2.settings."protocol imap"."passdb nightsky-site" = {
    driver = "passwd-file";
    passwd_file_path = "${inboxDir}/dovecot-passwd";
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
