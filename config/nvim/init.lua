-- Disable the language-host providers we don't use. These were previously
-- injected by home-manager's programs.neovim; they live here now that neovim
-- is installed without a generated init.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_python3_provider = 0

require("miker")
