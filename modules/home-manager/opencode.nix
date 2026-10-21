{ ... }:

{
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    provider = {
      ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama";
        options = {
          baseURL = "http://localhost:11434/v1";
        };
        models = {
          # mtp = multi-token prediction. Fastest of the local models measured
          # (13.6 tok/s vs 7.6 for q8_0), so it is the default workhorse.
          "qwen3.8:27b-mtp-q4_K_M" = {};
          # Kept for work where answer quality beats latency.
          "qwen3.8:27b-q8_0" = {};
          "qwen3.6:35b" = {};
        };
      };
      # Gufo services on nixtop (modules/gufo.nix). Only one runs at a time,
      # so only one of these models answers.
      gufo-27b-q4 = {
        npm = "@ai-sdk/openai-compatible";
        name = "Gufo 27B Q4";
        options = {
          baseURL = "http://127.0.0.1:8080/v1";
        };
        models = {
          "qwen3.8-27b-q4" = {};
        };
      };
      gufo-27b-q8 = {
        npm = "@ai-sdk/openai-compatible";
        name = "Gufo 27B Q8";
        options = {
          baseURL = "http://127.0.0.1:8082/v1";
        };
        models = {
          "qwen3.8-27b-q8" = {};
        };
      };
      gufo-flash-next = {
        npm = "@ai-sdk/openai-compatible";
        name = "Gufo Flash-Next";
        options = {
          baseURL = "http://127.0.0.1:8081/v1";
        };
        models = {
          "qwen3.8-flash-next" = {};
        };
      };
    };
  };
}
