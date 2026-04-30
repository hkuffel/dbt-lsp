local manifest = require("dbt.manifest")
local jump = require("dbt.jump")

local M = {}

local state = { win = nil, buf = nil }

local function notify(msg, level)
  vim.notify("[dbt] " .. msg, level or vim.log.levels.WARN)
end

local function model_under_cursor()
  -- Prefer a ref() the cursor is inside.
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local hit = jump.detect(line, col)
  if hit and hit.kind == "ref" then
    return hit.args[#hit.args]
  end
  -- Fall back to: current buffer's file maps to a model.
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then return nil end
  local idx = manifest.load(buf_path)
  if not idx then return nil end
  local uid = idx.path_to_unique_id[buf_path]
  if not uid then return nil end
  for _, entry in pairs(idx.models_by_pkg_name) do
    if entry.unique_id == uid then return entry.name end
  end
  return nil
end

local function close_float()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win, state.buf = nil, nil
end

function M.open(opts)
  opts = opts or {}
  if vim.fn.executable("cst") == 0 then
    notify("`cst` (Constellation) not found on $PATH")
    return
  end

  local model = opts.model or model_under_cursor()
  local cmd = { "cst" }
  if model then table.insert(cmd, "+" .. model .. "+") end

  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = model and (" constellation: " .. model .. " ") or " constellation ",
    title_pos = "center",
  })
  state.win, state.buf = win, buf

  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function()
      vim.schedule(close_float)
    end,
  })

  vim.keymap.set({ "n", "t" }, "<Esc>", close_float, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", close_float, { buffer = buf, nowait = true })

  vim.cmd.startinsert()
end

return M
