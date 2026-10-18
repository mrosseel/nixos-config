{ ... }:

{
  # No nightly upgrade. The server runs only the nixpkgs in flake.lock. The
  # nightly upgrade took a newer nixpkgs than the lock, and each deploy went
  # back to the lock. Postgres then changed between glibc 2.42 and 2.44 and
  # back, and its text indexes can be in the wrong order after such a change.
  # Updates come with a lock update on nixtop and a deploy.
  system.autoUpgrade.enable = false;
}
