return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-cmdline",
            "hrsh7th/nvim-cmp",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
            "j-hui/fidget.nvim",
        },

        config = function()
            require("fidget").setup()
            require("mason").setup()
            require("mason-lspconfig").setup({
                ensured_installed = {
                    "bashls",
                    "lua_ls",
                    "dockerls",
                    "pyright",
                    "rust_analyzer",
                    "vimls",
                    "yamlls",
                },
                handlers = {
                    function (server_name)
                        require("lspconfig")[server_name].setup {}
                    end
                }
            })
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
            vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
            vim.keymap.set("n", "[d", vim.diagnostic.goto_next, opts)
            vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, opts)
            vim.keymap.set("n", "<leader>vca", vim.lsp.buf.code_action, opts)
            vim.keymap.set("n", "<leader>vrr", vim.lsp.buf.references, opts)
            vim.keymap.set("n", "<leader>vrn", vim.lsp.buf.rename, opts)
            vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)
            local cmp = require('cmp')
            local cmp_select = { behavior = cmp.SelectBehavior.Select }
            cmp.setup({
                snippet = {
                    expand = function(args)
                        require('luasnip').lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                  ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
                  ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
                  ['<C-y>'] = cmp.mapping.confirm({ select = true }),
                  ["<C-Space>"] = cm
              }),
                sources = {
                    { name = 'nvim_lsp' },
                    { name = 'buffer' },
                    { name = 'luasnip' },
                }

            })

            -- disable completion with tab
            -- this helps with copilot setup
            -- cmp_mappings['<Tab>'] = nil
            -- cmp_mappings['<S-Tab>'] = nil

        end
    }
}
