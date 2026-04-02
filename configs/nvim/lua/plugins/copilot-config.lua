return {
  {
    "zbirenbaum/copilot.lua",
    opts = {
      suggestion = { enabled = true },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
      },
      server_opts_overrides = {
        settings = {
          telemetry = {
            telemetryLevel = "off",
          },
        },
      },
    },
    config = function(_, opts)
      require("copilot").setup(opts)

      -- Disable Copilot notifications
      vim.notify = function() end
    end,
  },
}
