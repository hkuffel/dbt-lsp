local project = require("dbt.project")

local M = {}

local function notify(msg, level)
  vim.notify("[dbt] " .. msg, level or vim.log.levels.WARN)
end

-- Map the current buffer's path to the corresponding compiled/run output.
-- e.g. <root>/models/marts/foo.sql -> <root>/target/{compiled,run}/<project>/models/marts/foo.sql
local function output_path(kind, buf_path)
  local info = project.info(buf_path)
  if not info then return nil, "not in a dbt project" end
  if not buf_path:find(info.root, 1, true) then
    return nil, "current file is not under the dbt project root"
  end
  local rel = buf_path:sub(#info.root + 2)
  if not (rel:match("^models/") or rel:match("^snapshots/") or rel:match("^seeds/") or rel:match("^analyses/") or rel:match("^tests/")) then
    return nil, "current file does not look like a dbt model/snapshot/seed/analysis/test"
  end
  return info.target_dir .. "/" .. kind .. "/" .. info.name .. "/" .. rel
end

local function go(kind, mods)
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then notify("no file in current buffer"); return end
  local path, err = output_path(kind, buf_path)
  if err then notify(err); return end
  if vim.uv.fs_stat(path) == nil then
    notify(string.format("%s output not found at %s (run `dbt compile` or `dbt run`)", kind, path))
    return
  end
  local cmd = mods == "split" and "split" or (mods == "vsplit" and "vsplit" or "edit")
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
end

function M.compiled(mods) go("compiled", mods) end
function M.run(mods) go("run", mods) end

return M
