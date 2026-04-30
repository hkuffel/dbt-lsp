local M = {}

function M.check()
  local h = vim.health
  h.start("dbt")

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then buf_path = vim.fn.getcwd() end

  local info = require("dbt.project").info(buf_path)
  if not info then
    h.warn("not in a dbt project (no dbt_project.yml found upward from " .. buf_path .. ")")
  else
    h.ok("project root: " .. info.root)
    h.ok("project name: " .. info.name)
    h.ok("target dir: " .. info.target_dir)

    local stat = vim.uv.fs_stat(info.manifest_path)
    if stat then
      local age = os.time() - stat.mtime.sec
      h.ok(string.format("manifest.json present (%.1f min old)", age / 60))
    else
      h.error("manifest.json not found at " .. info.manifest_path, { "Run `dbt parse` or `dbt compile` to generate it" })
    end
  end

  if vim.fn.executable("cst") == 1 then
    h.ok("`cst` (Constellation) found on $PATH")
  else
    h.warn("`cst` not on $PATH — Constellation overlay will not work", {
      "Install Constellation from https://github.com/<user>/constellation",
    })
  end
end

return M
