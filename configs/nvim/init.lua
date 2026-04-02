-- bootstrap lazy.nvim, LazyVim and your plugins
local socket = vim.env.KITTY_LISTEN_ON
if socket then
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      vim.fn.system("kitty @ --to " .. vim.fn.shellescape(socket) .. " set-spacing padding=0")
    end,
  })
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      vim.fn.system("kitty @ --to " .. vim.fn.shellescape(socket) .. " set-spacing padding=default")
    end,
  })
end
require("config.lazy")
