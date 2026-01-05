return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "L3MON4D3/LuaSnip",
            "j-hui/fidget.nvim",
        },

        config = function()
            local capabilities = require('blink.cmp').get_lsp_capabilities()
            require("fidget").setup()
            require("mason").setup()
            require("mason-lspconfig").setup({
                capabilities = capabilities,
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
            local opts = { buffer = 0 }
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
        end
    }
}
