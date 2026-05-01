local M = {}

local defaults = {
  -- buffer-local keymap for GoToDefinition. Set to false to disable.
  goto_definition_keymap = "gd",
  -- global keymap to open the lineage picker. Set to false to disable.
  lineage_keymap = "<leader>dl",
}

M.config = vim.deepcopy(defaults)

local function attach_buffer(bufnr)
  local jump = require("dbt.jump")
  if M.config.goto_definition_keymap then
    vim.keymap.set("n", M.config.goto_definition_keymap, function()
      if not jump.goto_definition() then
        -- fall through to default gd if our handler didn't match
        local key = vim.api.nvim_replace_termcodes(M.config.goto_definition_keymap, true, false, true)
        -- Use feedkeys with `n` so we don't recurse into our own mapping.
        vim.api.nvim_feedkeys(key, "n", false)
      end
    end, { buffer = bufnr, desc = "dbt: go to ref/source/macro definition" })
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  local group = vim.api.nvim_create_augroup("DbtPlugin", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "sql", "jinja", "jinja.sql", "sql.jinja" },
    callback = function(ev)
      local project = require("dbt.project")
      if project.info(vim.api.nvim_buf_get_name(ev.buf)) then
        attach_buffer(ev.buf)
      end
    end,
  })

  if M.config.lineage_keymap then
    vim.keymap.set("n", M.config.lineage_keymap, function()
      require("dbt.lineage").open()
    end, { desc = "dbt: open lineage picker" })
  end
end

return M
