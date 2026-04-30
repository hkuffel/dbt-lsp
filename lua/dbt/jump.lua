local manifest = require("dbt.manifest")

local M = {}

local function notify(msg, level)
  vim.notify("[dbt] " .. msg, level or vim.log.levels.WARN)
end

local function quoted(s)
  local result = s:gsub("^['\"]", ""):gsub("['\"]$", "")
  return result
end

-- Given line text and 0-indexed cursor column, find the dbt call that
-- contains the cursor. Returns one of:
--   { kind = "ref",    args = { "name" } | { "pkg", "name" } }
--   { kind = "source", args = { "src", "name" } }
--   { kind = "macro",  args = { "name" } | { "pkg", "name" } }
-- or nil.
function M.detect(line, col)
  -- Scan all ref/source occurrences and check if the cursor falls inside.
  local patterns = {
    { kind = "ref",    pat = "ref%s*%(%s*([^)]-)%s*%)" },
    { kind = "source", pat = "source%s*%(%s*([^)]-)%s*%)" },
  }
  for _, p in ipairs(patterns) do
    local init = 1
    while true do
      local s, e, inner = line:find(p.pat, init)
      if not s then break end
      if col >= s - 1 and col <= e - 1 then
        local args = {}
        for arg in inner:gmatch("[^,]+") do
          local trimmed = arg:gsub("^%s+", ""):gsub("%s+$", "")
          table.insert(args, quoted(trimmed))
        end
        return { kind = p.kind, args = args }
      end
      init = e + 1
    end
  end

  -- Macro: cursor on an identifier inside `{{ ... }}` (or a `{% ... %}` block).
  -- Walk backward from the cursor to find the start of a word.
  local left = line:sub(1, col + 1)
  local word_start = left:find("[%w_%.]+$")
  if not word_start then return nil end
  local right = line:sub(col + 1)
  local word_end = right:find("[^%w_%.]") or (#right + 1)
  local word = line:sub(word_start, col + word_end - 1)

  -- Only treat as a macro reference if it appears inside a jinja delimiter on this line.
  -- Cheap check: there's a `{{` or `{%` before the word and a matching `}}` / `%}` after.
  local before = line:sub(1, word_start - 1)
  local after = line:sub(col + word_end)
  local in_jinja = (before:match("{{[^}]*$") or before:match("{%%[^%%]*$"))
    and (after:match("^[^{]-}}") or after:match("^[^{]-%%}"))
  if not in_jinja then return nil end

  -- Skip dotted attribute access where the cursor isn't on the leading segment.
  local parts = vim.split(word, ".", { plain = true })
  if #parts == 1 then
    return { kind = "macro", args = { parts[1] } }
  elseif #parts == 2 then
    return { kind = "macro", args = parts }
  end
  return nil
end

local function open(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.goto_definition()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local hit = M.detect(line, col)
  if not hit then
    notify("no ref/source/macro under cursor")
    return false
  end

  local start_path = vim.api.nvim_buf_get_name(0)
  local node, err
  if hit.kind == "ref" then
    if #hit.args == 1 then
      node, err = manifest.get_model(hit.args[1], nil, start_path)
    else
      node, err = manifest.get_model(hit.args[2], hit.args[1], start_path)
    end
  elseif hit.kind == "source" then
    if #hit.args ~= 2 then
      notify("source() needs two args")
      return false
    end
    node, err = manifest.get_source(hit.args[1], hit.args[2], start_path)
  elseif hit.kind == "macro" then
    if #hit.args == 1 then
      node, err = manifest.get_macro(hit.args[1], nil, start_path)
    else
      node, err = manifest.get_macro(hit.args[2], hit.args[1], start_path)
    end
  end

  if err then notify(err); return false end
  if not node then
    notify(string.format("%s '%s' not found in manifest", hit.kind, table.concat(hit.args, ".")))
    return false
  end
  open(node.path)
  return true
end

return M
