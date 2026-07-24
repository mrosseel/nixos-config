{ ... }:

{
  programs.thunderbird = {
    enable = true;
    profiles = {
      default = {
        isDefault = true;
      };
    };
  };

  accounts.email = {
    accounts = {
      pifinder = {
        primary = true;
        address = "info@pifinder.eu";
        realName = "Mike Rosseel";
        userName = "info@pifinder.eu";

        imap = {
          host = "mail.pifinder.eu";
          port = 993;
          tls = {
            enable = true;
            useStartTls = false;
          };
        };

        smtp = {
          host = "mail.pifinder.eu";
          port = 465;
          tls = {
            enable = true;
            useStartTls = false;
          };
        };

        thunderbird = {
          enable = true;
          profiles = [ "default" ];
        };
      };

      hackerspace = {
        address = "board@hackerspace.gent";
        realName = "Hackerspace.gent board";
        userName = "board@hackerspace.gent";

        imap = {
          host = "mail.openminds.be";
          port = 993;
          tls = {
            enable = true;
            useStartTls = false;
          };
        };

        smtp = {
          host = "mail.openminds.be";
          port = 587;
          tls = {
            enable = true;
            useStartTls = true;
          };
        };

        thunderbird = {
          enable = true;
          profiles = [ "default" ];
        };
      };
    };
  };
}
