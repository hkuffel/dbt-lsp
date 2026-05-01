local manifest = require("dbt.manifest")
local jump = require("dbt.jump")

local M = {}

-- Resolve the model the user is currently focused on.
-- Order: ref() under cursor, then current buffer's path → manifest entry.
-- Returns a node entry { unique_id, name, package, path, resource_type } or nil.
function M.focal_model(start_path)
  start_path = start_path or vim.api.nvim_buf_get_name(0)

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local hit = jump.detect(line, col)
  if hit and hit.kind == "ref" then
    local entry
    if #hit.args == 1 then
      entry = manifest.get_model(hit.args[1], nil, start_path)
    elseif #hit.args >= 2 then
      entry = manifest.get_model(hit.args[2], hit.args[1], start_path)
    end
    if entry then return entry end
  end

  if start_path == "" then return nil end
  local idx = manifest.load(start_path)
  if not idx then return nil end
  local uid = idx.path_to_unique_id[start_path]
  if not uid then return nil end
  return idx.nodes_by_uid[uid]
end

return M
