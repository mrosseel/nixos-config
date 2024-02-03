local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("miker.lazy")

-- Example using a list of specs with the default options
vim.g.mapleader = " " -- Make sure to set `mapleader` before lazy so your mappings are correct

-- require("lazy").setup({
--
--     use('nvim-treesitter/playground')
--     -- git plugins
--     use('tpope/vim-fugitive')
--     use 'tpope/vim-rhubarb'
--     use 'lewis6991/gitsigns.nvim'
--
--     use {
--         'nvim-lualine/lualine.nvim',
--         requires = { 'kyazdani42/nvim-web-devicons', opt = true }
--     }
--     use('AndrewRadev/linediff.vim')
--     use {
--         'numToStr/Comment.nvim',
--         config = function()
--             require('Comment').setup()
--         end
--     }
--
--     use {
--         'VonHeikemen/lsp-zero.nvim',
--         requires = {
--             -- LSP Support
--             { 'neovim/nvim-lspconfig' },
--             { 'williamboman/mason.nvim' },
--             { 'williamboman/mason-lspconfig.nvim' },
--
--             -- Autocompletion
--             { 'hrsh7th/nvim-cmp' },
--             { 'hrsh7th/cmp-buffer' },
--             { 'hrsh7th/cmp-path' },
--             { 'saadparwaiz1/cmp_luasnip' },
--             { 'hrsh7th/cmp-nvim-lsp' },
--             { 'hrsh7th/cmp-nvim-lua' },
--
--             -- Snippets
--             { 'L3MON4D3/LuaSnip' },
--             { 'rafamadriz/friendly-snippets' },
--         }
--     }
--
--
-- end)
--
