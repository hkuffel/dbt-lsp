if vim.g.loaded_dbt_plugin then return end
vim.g.loaded_dbt_plugin = true

vim.api.nvim_create_user_command("DbtGotoDef", function()
  require("dbt.jump").goto_definition()
end, { desc = "dbt: jump to ref/source/macro definition" })

vim.api.nvim_create_user_command("DbtCompiled", function(opts)
  local mods = opts.bang and "vsplit" or (opts.smods and opts.smods.split ~= "" and opts.smods.split or "edit")
  require("dbt.target").compiled(mods)
end, { desc = "dbt: open compiled output for current model", bang = true })

vim.api.nvim_create_user_command("DbtRun", function(opts)
  local mods = opts.bang and "vsplit" or (opts.smods and opts.smods.split ~= "" and opts.smods.split or "edit")
  require("dbt.target").run(mods)
end, { desc = "dbt: open run output for current model", bang = true })

vim.api.nvim_create_user_command("Constellation", function(opts)
  require("dbt.constellation").open({ model = opts.args ~= "" and opts.args or nil })
end, { desc = "dbt: open Constellation overlay", nargs = "?" })

vim.api.nvim_create_user_command("DbtClearCache", function()
  require("dbt.manifest").clear_cache()
  require("dbt.project").clear_cache()
  vim.notify("[dbt] cache cleared", vim.log.levels.INFO)
end, { desc = "dbt: drop cached project + manifest data" })
