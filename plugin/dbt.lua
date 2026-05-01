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

vim.api.nvim_create_user_command("DbtLineage", function(opts)
  require("dbt.lineage").open({ model = opts.args ~= "" and opts.args or nil })
end, {
  desc = "dbt: open lineage picker",
  nargs = "?",
  complete = function(arg_lead)
    local idx = require("dbt.manifest").load(vim.api.nvim_buf_get_name(0))
    if not idx then return {} end
    local names = {}
    for name, _ in pairs(idx.models_by_name) do
      if name:sub(1, #arg_lead) == arg_lead then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    return names
  end,
})

vim.api.nvim_create_user_command("DbtUpstream", function(opts)
  require("dbt.lineage").open({
    model = opts.args ~= "" and opts.args or nil,
    direction = "up",
  })
end, { desc = "dbt: open upstream lineage picker", nargs = "?" })

vim.api.nvim_create_user_command("DbtDownstream", function(opts)
  require("dbt.lineage").open({
    model = opts.args ~= "" and opts.args or nil,
    direction = "down",
  })
end, { desc = "dbt: open downstream lineage picker", nargs = "?" })

vim.api.nvim_create_user_command("DbtClearCache", function()
  require("dbt.manifest").clear_cache()
  require("dbt.project").clear_cache()
  require("dbt.lineage").clear_state()
  vim.notify("[dbt] cache cleared", vim.log.levels.INFO)
end, { desc = "dbt: drop cached project + manifest data" })
