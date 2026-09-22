{ config, lib, pkgs, ... }:

# The GitHub runner that deploys testalon, and the limits that keep a build
# from taking the rest of this machine with it.
#
# A push to hexagonia's master wakes this runner. It checks the commit out,
# builds the two packages here and moves the pointers testalon.nix reads. No
# key exists that reaches this machine from outside, and nothing is copied
# in.
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

let
  # Runs before every job, and a failure here fails the job before its first
  # step. A workflow on any branch can ask for this runner by its label, so
  # this is what keeps it to the one workflow it exists for.
  #
  # The runner sets these variables, and a workflow cannot overwrite a
  # GITHUB_ variable. The name ends in .sh because the runner picks the
  # interpreter by the extension.
  jobStarted = pkgs.writeShellScript "testalon-job-started.sh" ''
    want=mrosseel/hexagonia/.github/workflows/testalon.yml@refs/heads/master
    echo "job: $GITHUB_EVENT_NAME $GITHUB_WORKFLOW_REF by $GITHUB_ACTOR"
    if [[ $GITHUB_WORKFLOW_REF != "$want" ]]; then
      echo "refused: this runner runs testalon.yml from master only" >&2
      exit 1
    fi
    if [[ $GITHUB_EVENT_NAME != push && $GITHUB_EVENT_NAME != workflow_dispatch ]]; then
      echo "refused: $GITHUB_EVENT_NAME does not start a beta deploy" >&2
      exit 1
    fi
  '';
in
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
    # On disk, not in RAM.
    #
    # Left alone the runner works in its systemd runtime directory, which is
    # /run, which is tmpfs. A Rust target directory of several gigabytes
    # then lives in memory: a run died with "No space left on device" at
    # 1.5 GB, and the one before it crawled because those files were
    # counted against the service's own memory allowance.
    #
    # The module empties this directory every time the service starts. The
    # checkout and its Rust target directory go with it, so the first run
    # after a restart compiles from zero: about 13 minutes, against 5 when
    # the target directory is there.
    workDir = "/var/lib/github-runner/testalon-work";
    # The service runs with an environment of its own, and the system's
    # nix.conf does not reach it: a job's first `nix develop` failed with
    # nix-command disabled while /etc/nix/nix.conf enabled it. Saying it here
    # settles it for every job.
    extraEnvironment = {
      NIX_CONFIG = "experimental-features = nix-command flakes";
      # Two compilers at a time. Cargo otherwise starts one per core and
      # four rustc processes at opt-level 3 do not fit in this machine.
      CARGO_BUILD_JOBS = "2";
      # See jobStarted above.
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${jobStarted}";
    };
    serviceOverrides = {
      # sudo needs a process that can gain root. The module's sandbox stops
      # that in four ways, and each one is off here:
      #
      #   - NoNewPrivileges. systemd sets it again, whatever the unit says,
      #     for a non-root service with a seccomp filter or a kernel
      #     protection. The process showed NoNewPrivs 1 with the flag off.
      #   - The seccomp filters: SystemCallFilter, RestrictAddressFamilies,
      #     RestrictNamespaces, RestrictRealtime and RestrictSUIDSGID.
      #   - The kernel protections: PrivateDevices, ProtectClock and the
      #     three ProtectKernel settings.
      #   - An empty capability bounding set, and a private user namespace.
      #     Root has no rights in either.
      #
      # The rest of the sandbox stays. What sudo may run is the one script
      # the sudoers rule in testalon.nix names.
      NoNewPrivileges = false;
      SystemCallFilter = lib.mkForce [ ];
      RestrictAddressFamilies = lib.mkForce [ ];
      RestrictNamespaces = false;
      RestrictRealtime = false;
      RestrictSUIDSGID = false;
      PrivateDevices = false;
      ProtectClock = false;
      ProtectKernelLogs = false;
      ProtectKernelModules = false;
      ProtectKernelTunables = false;
      CapabilityBoundingSet = lib.mkForce [ ];
      PrivateUsers = false;
      # The sandbox mounts the file system read-only. The deploy script
      # moves symlinks in these two directories, which its group owns, and
      # the first run stopped with "Read-only file system" on the first one.
      ReadWritePaths = [ "/var/lib/testalon" "/nix/var/nix/gcroots/testalon" ];
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
    "d /var/lib/github-runner/testalon-work 0750 github-runner github-runner - -"
  ];

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
