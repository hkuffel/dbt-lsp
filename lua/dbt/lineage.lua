local manifest = require("dbt.manifest")
local cursor = require("dbt.cursor")

local M = {}

local function notify(msg, level)
  vim.notify("[dbt] " .. msg, level or vim.log.levels.WARN)
end

local function has_more(adj, uid, direction)
  local map = direction == "up" and adj.parent_map or adj.child_map
  for _, u in ipairs(map[uid] or {}) do
    if adj.nodes_by_uid[u] then return true end
  end
  return false
end

local function neighbors(adj, uid, direction)
  local map = direction == "up" and adj.parent_map or adj.child_map
  local result = {}
  for _, u in ipairs(map[uid] or {}) do
    local entry = adj.nodes_by_uid[u]
    if entry then result[#result + 1] = entry end
  end
  return result
end

local function display_label(entry)
  if entry.resource_type == "source" then
    return "[src] " .. (entry.source_name or "?") .. "." .. entry.name
  end
  return (entry.package or "?") .. "." .. entry.name
end

local function entry_to_item(entry, direction, level, expanded, more, cyclic)
  return {
    text = display_label(entry),
    file = entry.path,
    unique_id = entry.unique_id,
    name = entry.name,
    package = entry.package,
    source_name = entry.source_name,
    resource_type = entry.resource_type,
    level = level,
    direction = direction,
    expanded = expanded,
    has_more = more,
    cyclic = cyclic or false,
  }
end

local function walk_up(adj, uid, expanded, items, depth, visited)
  for _, parent in ipairs(neighbors(adj, uid, "up")) do
    local p_uid = parent.unique_id
    if visited[p_uid] then
      items[#items + 1] = entry_to_item(parent, "up", -depth, false, false, true)
    else
      visited[p_uid] = true
      local is_exp = expanded["up:" .. p_uid] == true
      local more = has_more(adj, p_uid, "up")
      if is_exp then
        walk_up(adj, p_uid, expanded, items, depth + 1, visited)
      end
      items[#items + 1] = entry_to_item(parent, "up", -depth, is_exp, more, false)
      visited[p_uid] = nil
    end
  end
end

local function walk_down(adj, uid, expanded, items, depth, visited)
  for _, child in ipairs(neighbors(adj, uid, "down")) do
    local c_uid = child.unique_id
    if visited[c_uid] then
      items[#items + 1] = entry_to_item(child, "down", depth, false, false, true)
    else
      visited[c_uid] = true
      local is_exp = expanded["down:" .. c_uid] == true
      local more = has_more(adj, c_uid, "down")
      items[#items + 1] = entry_to_item(child, "down", depth, is_exp, more, false)
      if is_exp then
        walk_down(adj, c_uid, expanded, items, depth + 1, visited)
      end
      visited[c_uid] = nil
    end
  end
end

local function build_items(state)
  local items = {}
  local adj = state.adj
  local focal = state.focal

  if state.direction ~= "down" then
    walk_up(adj, focal.unique_id, state.expanded, items, 1, {})
  end

  items[#items + 1] = entry_to_item(focal, "focal", 0, true, false, false)

  if state.direction ~= "up" then
    walk_down(adj, focal.unique_id, state.expanded, items, 1, {})
  end

  return items
end

local function format_item(item, _picker)
  local indent = string.rep("  ", math.abs(item.level or 0))
  local glyph
  if item.cyclic then
    glyph = "↻"
  elseif item.has_more then
    glyph = item.expanded and "▾" or "▸"
  else
    glyph = " "
  end
  local arrow
  if item.direction == "up" then
    arrow = "↑"
  elseif item.direction == "down" then
    arrow = "↓"
  else
    arrow = "●"
  end

  local line = indent .. glyph .. " " .. arrow .. " " .. display_label(item)
  if item.cyclic then line = line .. "  (seen above)" end

  local hl
  if item.direction == "focal" then
    hl = "Title"
  elseif item.cyclic then
    hl = "Comment"
  elseif item.resource_type == "source" then
    hl = "Type"
  end

  return { { line, hl } }
end

local state = {}

function M.clear_state()
  state = {}
end

function M.open(opts)
  opts = opts or {}
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    notify("snacks.picker is required for :DbtLineage")
    return
  end

  local start_path = vim.api.nvim_buf_get_name(0)

  local focal
  if opts.model then
    local entry, err = manifest.get_model(opts.model, nil, start_path)
    if err then notify(err); return end
    if not entry then
      notify("model '" .. opts.model .. "' not found in manifest")
      return
    end
    focal = entry
  else
    focal = cursor.focal_model(start_path)
    if not focal then
      notify("no model under cursor and current buffer is not a dbt model")
      return
    end
  end

  local adj, err = manifest.adjacency(start_path)
  if not adj then notify(err or "failed to load adjacency"); return end

  state = {
    focal = focal,
    adj = adj,
    expanded = {},
    direction = opts.direction or "both",
    cursor_target = { uid = focal.unique_id, direction = "focal" },
  }

  Snacks.picker.pick({
    source = "dbt_lineage",
    finder = function(_, ctx)
      local items = build_items(state)
      local target_idx
      for i, item in ipairs(items) do
        if item.unique_id == state.cursor_target.uid
          and item.direction == state.cursor_target.direction then
          target_idx = i
          break
        end
      end
      if not target_idx then
        for i, item in ipairs(items) do
          if item.direction == "focal" then
            target_idx = i
            break
          end
        end
      end
      if target_idx and ctx and ctx.picker and ctx.picker.list then
        ctx.picker.list:set_target(target_idx, nil, { force = true })
      end
      return items
    end,
    format = format_item,
    preview = "file",
    layout = { preset = "telescope" },
    title = "dbt lineage: " .. display_label(focal),
    win = {
      input = {
        keys = {
          ["<Tab>"]  = { "lineage_toggle", desc = "Expand/collapse node", mode = { "i", "n" } },
          ["<C-u>"]  = { "lineage_only_upstream", desc = "Filter upstream", mode = { "i", "n" } },
          ["<C-d>"]  = { "lineage_only_downstream", desc = "Filter downstream", mode = { "i", "n" } },
          ["<C-b>"]  = { "lineage_both", desc = "Show both directions", mode = { "i", "n" } },
        },
      },
      list = {
        keys = {
          ["<Tab>"] = "lineage_toggle",
        },
      },
    },
    actions = {
      lineage_toggle = function(picker, item)
        if not item or item.direction == "focal" then return end
        if not item.has_more and not item.expanded then return end
        local key = item.direction .. ":" .. item.unique_id
        state.expanded[key] = not state.expanded[key] or nil
        state.cursor_target = { uid = item.unique_id, direction = item.direction }
        picker:find({ refresh = true })
      end,
      lineage_only_upstream = function(picker)
        state.direction = "up"
        state.cursor_target = { uid = state.focal.unique_id, direction = "focal" }
        picker:find({ refresh = true })
      end,
      lineage_only_downstream = function(picker)
        state.direction = "down"
        state.cursor_target = { uid = state.focal.unique_id, direction = "focal" }
        picker:find({ refresh = true })
      end,
      lineage_both = function(picker)
        state.direction = "both"
        state.cursor_target = { uid = state.focal.unique_id, direction = "focal" }
        picker:find({ refresh = true })
      end,
    },
  })
end

return M
