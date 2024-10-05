-- In your Neovim configuration file (usually init.lua or a separate plugins.lua)
return {
   {
    "ggandor/leap.nvim",
    dependencies = { "tpope/vim-repeat" },
    config = function()
      require('leap').add_default_mappings()
    end,
  },
}
