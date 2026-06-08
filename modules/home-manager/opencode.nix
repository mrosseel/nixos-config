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
          "qwen3.6:27b-q4_K_M" = {};
          "qwen3.6:35b" = {};
        };
      };
    };
  };
}
