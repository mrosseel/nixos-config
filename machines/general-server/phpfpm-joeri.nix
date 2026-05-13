{ pkgs, ... }:

# PHP-FPM pool for joeri.miker.be (Arte Vista preview site).
# The site is a static Eleventy build with one PHP entrypoint
# (mailinglist.php) for the newsletter signup form.
{
  services.phpfpm.pools.joeri = {
    user = "caddy";
    group = "caddy";
    phpPackage = pkgs.php83;
    settings = {
      "listen" = "/run/phpfpm/joeri.sock";
      "listen.owner" = "caddy";
      "listen.group" = "caddy";
      "listen.mode" = "0660";
      "pm" = "ondemand";
      "pm.max_children" = 5;
      "pm.process_idle_timeout" = "60s";
      "pm.max_requests" = 500;
    };
  };
}
