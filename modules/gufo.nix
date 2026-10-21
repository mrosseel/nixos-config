# Gufo: an LLM inference engine for AMD Strix Halo (gfx1151). nixtop only.
# Upstream: https://github.com/gufo-org/gufo
#
# Each model is a systemd service with an OpenAI-compatible API on localhost.
# The services do not start at boot. Start one by hand:
#   sudo systemctl start gufo-qwen27b-q4    # http://127.0.0.1:8080/v1
#   sudo systemctl start gufo-flash-next    # http://127.0.0.1:8081/v1
#   sudo systemctl start gufo-qwen27b-q8    # http://127.0.0.1:8082/v1
#
# Flash-Next loads about 104 GiB of weights. The services conflict, so a start
# of one stops the others. Stop ollama models first (`ollama stop <model>`) to
# free their memory.
#
# The weights are not in the Nix store. They live in /var/lib/gufo-models.
# ollama-qwen3.8-27b-q8_0.gguf and ollama-mmproj.gguf are hard links to the
# ollama blobs of qwen3.8:27b-q8_0, so they take no extra disk space. If ollama
# deletes that model, the links keep the files. Download the other files with:
#   cd /var/lib/gufo-models
#   nix shell nixpkgs#python3Packages.huggingface-hub -c hf download \
#     unsloth/Qwen3.8-Flash-Next-GGUF \
#     --revision 38bb39ee97821de2c9009abb7e93950eec396e66 \
#     --include "UD-Q4_K_XL/*" --include "MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" \
#     --include "mmproj-BF16.gguf" --local-dir qwen3.8-flash-next
#   nix shell nixpkgs#python3Packages.huggingface-hub -c hf download \
#     z-lab/Qwen3.8-27B-DFlash2-GGUF \
#     --revision 2d9571f8ce46e151f61c6499c99dee6079e1d610 \
#     Qwen3.8-27B-DFlash2-Q4_K_M.gguf --local-dir qwen3.8-27b
#   nix shell nixpkgs#python3Packages.huggingface-hub -c hf download \
#     unsloth/Qwen3.8-27B-GGUF \
#     --revision 4ca720788d1e01f1bff70c033e0d0028fd02e502 \
#     Qwen3.8-27B-UD-Q4_K_XL.gguf --local-dir qwen3.8-27b
{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  gufo = inputs.gufo.packages.${system}.default;
  mkServe = inputs.gufo.lib.${system}.mkServe;
  models = "/var/lib/gufo-models";

  mkGufoService = { description, conflicts, serve }: {
    inherit description conflicts;
    after = [ "network.target" ];
    environment.HOME = "/var/lib/gufo";
    serviceConfig = {
      ExecStart = mkServe ({
        gufoPackage = gufo;
        host = "127.0.0.1";
        sessions = 2;
        context = 32768;
      } // serve);
      DynamicUser = true;
      StateDirectory = "gufo";
      SupplementaryGroups = [ "render" "video" ];
      LimitMEMLOCK = "infinity";
      Restart = "on-failure";
      RestartSec = 10;
      # Loading a large model takes minutes.
      TimeoutStartSec = 600;
    };
  };

  # Only one gufo model fits in memory next to the desktop, so every service
  # conflicts with the others.
  mkQwen27b = { quant, port, file }:
    mkGufoService {
      description = "Gufo Qwen3.8 27B (${quant}, DFlash2)";
      conflicts = map (q: "gufo-qwen27b-${q}.service")
        (builtins.filter (q: q != quant) [ "q4" "q8" ])
        ++ [ "gufo-flash-next.service" ];
      serve = {
        inherit port;
        servedModelName = "qwen3.8-27b-${quant}";
        cacheDisk = "/var/lib/gufo/cache-qwen27b-${quant}";
        model = "${models}/qwen3.8-27b/${file}";
        speculative = "dflash2";
        dflashModel = "${models}/qwen3.8-27b/Qwen3.8-27B-DFlash2-Q4_K_M.gguf";
        extraArgs = [ "--mmproj" "${models}/qwen3.8-27b/ollama-mmproj.gguf" ];
      };
    };
in
{
  environment.systemPackages = [ gufo ];

  # mike owns the model directory so that downloads need no sudo.
  systemd.tmpfiles.rules = [ "d ${models} 0755 mike users -" ];

  # The Q4 and Q8 services differ only in the target file. Q4 is about 1.6x
  # faster in the gufo benchmarks and uses 13 GiB less memory. The model name
  # carries the quantization, so opencode shows which one answers.
  systemd.services.gufo-qwen27b-q4 = mkQwen27b {
    quant = "q4";
    port = 8080;
    file = "Qwen3.8-27B-UD-Q4_K_XL.gguf";
  };

  systemd.services.gufo-qwen27b-q8 = mkQwen27b {
    quant = "q8";
    port = 8082;
    file = "ollama-qwen3.8-27b-q8_0.gguf";
  };

  systemd.services.gufo-flash-next = mkGufoService {
    description = "Gufo Qwen3.8 Flash-Next (Q4, MTP)";
    conflicts = [ "gufo-qwen27b-q4.service" "gufo-qwen27b-q8.service" ];
    serve = {
      port = 8081;
      servedModelName = "qwen3.8-flash-next";
      cacheDisk = "/var/lib/gufo/cache-flash-next";
      model = "${models}/qwen3.8-flash-next/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
      speculative = "mtp";
      mtpModel = "${models}/qwen3.8-flash-next/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
    };
  };
}
