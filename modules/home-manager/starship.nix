{ pkgs, ... }:
{
  programs.starship.enable = true;
  programs.starship.enableZshIntegration = true;
  programs.starship.enableNushellIntegration = true;
  programs.starship.settings = {
    add_newline = false;
    format = "$character";  # A minimal left prompt
    # move the rest of the prompt to the right
    right_format = "$shlvl$shell$username$hostname$nix_shell$git_branch$git_commit$git_state$git_status$directory$jobs$cmd_duration";
    shlvl = {
      disabled = false;
      symbol = "ﰬ";
      style = "bright-red bold";
      threshold = 2;
      # repeat_offset = 2;
    };
    shell = {
      disabled = false;
      format = "$indicator";
      fish_indicator = "";
      bash_indicator = "[BASH](bright-white) ";
      zsh_indicator = "";
      nu_indicator = "";
    };
    username = {
      style_user = "bright-white bold";
      style_root = "bright-red bold";
    };
    hostname = {
      style = "bright-green bold";
      ssh_only = true;
    };
    nix_shell = {
      symbol = "";
      format = "[$symbol$name]($style) ";
      style = "bright-purple bold";
      heuristic = false;
    };
    git_branch = {
      only_attached = true;
      format = "[$symbol$branch]($style) ";
      style = "bright-yellow bold";
    };
    git_commit = {
      only_detached = true;
      format = "[ﰖ$hash]($style) ";
      style = "bright-yellow bold";
    };
    git_state = {
      style = "bright-purple bold";
    };
    git_status = {
      style = "bright-green bold";
    };
    directory = {
      read_only = " ";
      truncation_length = 0;
    };
    #cmd_duration = {
    #  format = "[$duration]($style) ";
    #  style = "bright-blue";
    #};
    jobs = {
      style = "bright-green bold";
    };
    character = {
      success_symbol = "[\\$](bright-green bold)";
      error_symbol = "[\\$](bright-red bold)";
    };
  };
}
