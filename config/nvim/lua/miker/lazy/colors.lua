-- Colours come from the current Omarchy theme. Each theme ships a neovim.lua
-- written for LazyVim: plugin specs plus a LazyVim spec that names the
-- colorscheme. This config does not use LazyVim, so we keep the plugin specs
-- and apply the named colorscheme ourselves.
local theme_file = vim.fn.expand("~/.local/state/omarchy/current/theme/neovim.lua")

local specs = {}
local colorscheme = "rose-pine"

local ok, theme = pcall(dofile, theme_file)
if ok and type(theme) == "table" then
	for _, spec in ipairs(theme) do
		if spec[1] == "LazyVim/LazyVim" then
			colorscheme = spec.opts and spec.opts.colorscheme or colorscheme
		else
			spec.lazy = false
			spec.priority = 1000
			table.insert(specs, spec)
		end
	end
end

if #specs == 0 then
	table.insert(specs, {
		"rose-pine/neovim",
		name = "rose-pine",
		lazy = false,
		priority = 1000,
		opts = { disable_background = true },
	})
end

function ColorMyPencils(color)
	pcall(vim.cmd.colorscheme, color or colorscheme)
end

vim.api.nvim_create_autocmd("User", {
	pattern = "LazyDone",
	once = true,
	callback = function()
		ColorMyPencils()
	end,
})

return specs
