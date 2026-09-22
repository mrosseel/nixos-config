{ config, lib, pkgs, ... }:

# The GitHub runner that deploys testalon, and the limits that keep a build
# from taking the rest of this machine with it.
#
# A push to hexagonia's master wakes this runner. It checks the commit out,
# builds the two packages here and moves the pointers testalon.nix reads. No
# key exists that reaches this machine from outside, and nothing is copied
# in: see testalon.nix, where the deploy used to arrive over SSH.
#
# **The limits belong on the nix daemon, not on the runner.** A build does not
# run in the process that asked for it. `nix build` hands the work to
# `nix-daemon.service`, so a cap on the runner would bound a process that does
# nothing while the daemon uses the whole machine.
#
# This box is the tighter of the two: four cores and about four gigabytes
# free, against production's seven, and it carries Caddy, the mail server,
# 1901 and the rest beside. The same build peaked at three gigabytes on
# production, so `MemoryHigh` sits below that on purpose. A squeezed build is
# slower. A killed mail server is worse.

{
  services.github-runners.testalon = {
    enable = true;
    url = "https://github.com/mrosseel/hexagonia";
    # A registration token, written once by hand. The runner trades it for
    # credentials of its own at first start and does not read it again.
    tokenFile = "/var/lib/github-runner/testalon.token";
    name = "testalon-beta";
    extraLabels = [ "testalon-beta" ];
    replace = true;
    user = "github-runner";
    group = "github-runner";
    extraPackages = [ pkgs.git pkgs.nix pkgs.openssh ];
    # The service runs with an environment of its own, and the system's
    # nix.conf does not reach it: a job's first `nix develop` failed with
    # nix-command disabled while /etc/nix/nix.conf enabled it. Saying it here
    # settles it for every job.
    extraEnvironment = {
      NIX_CONFIG = "experimental-features = nix-command flakes";
      # Two compilers at a time. Cargo otherwise starts one per core and
      # four rustc processes at opt-level 3 do not fit in this machine.
      CARGO_BUILD_JOBS = "2";
    };
    serviceOverrides = {
      CPUWeight = 20;
      IOWeight = 20;
      # The tests compile here, not in the daemon: `cargo test` runs inside
      # `nix develop`, which is this service's own child. A run capped at
      # 512 MB crawled for over an hour and finished nothing.
      MemoryHigh = "2500M";
      MemoryMax = "3500M";
    };
  };

  users.users.github-runner = {
    isSystemUser = true;
    group = "github-runner";
    home = "/var/lib/github-runner";
    # It hands the built paths to the deploy script testalon.nix installs,
    # which is what moves the pointers and restarts the unit.
    extraGroups = [ "testalon-deploy" ];
  };
  users.groups.github-runner = { };

  # The runner writes under its own home. Without this the directory is
  # root's, systemd still makes the state directory inside it, and the
  # runner fails at its first write with a permission error.
  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner 0750 github-runner github-runner - -"
  ];

  # It builds unsigned paths and hands them straight to the store here, the
  # same right the SSH key had before it.
  nix.settings.trusted-users = [ "github-runner" ];

  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 20;
    IOWeight = 20;
    MemoryHigh = "2500M";
    MemoryMax = "3500M";
  };

  # Two builds at a time, two threads each, of four cores.
  nix.settings = {
    max-jobs = 2;
    cores = 2;
  };
}
