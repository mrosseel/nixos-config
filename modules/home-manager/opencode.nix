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
    };
  };
}
