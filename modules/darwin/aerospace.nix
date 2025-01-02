{ pkgs, ... }: {
  
  environment.systemPackages = with pkgs; [
    aerospace
  ];

}
