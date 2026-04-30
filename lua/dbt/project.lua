local M = {}

local cache = {}

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local content = fd:read("*a")
  fd:close()
  return content
end

local function parse_project_name(yml_text)
  for line in yml_text:gmatch("[^\r\n]+") do
    local name = line:match("^%s*name%s*:%s*['\"]?([%w_%-]+)['\"]?")
    if name then return name end
  end
  return nil
end

local function parse_target_path(yml_text)
  for line in yml_text:gmatch("[^\r\n]+") do
    local tp = line:match("^%s*target%-path%s*:%s*['\"]?([^'\"%s]+)['\"]?")
    if tp then return tp end
  end
  return nil
end

function M.find_root(start_path)
  local found = vim.fs.find("dbt_project.yml", {
    upward = true,
    path = start_path or vim.fn.expand("%:p:h"),
    type = "file",
    stop = vim.fn.expand("$HOME"),
  })[1]
  if not found then return nil end
  return vim.fs.dirname(found)
end

function M.info(start_path)
  local root = M.find_root(start_path)
  if not root then return nil end
  if cache[root] then return cache[root] end

  local yml = read_file(root .. "/dbt_project.yml")
  if not yml then return nil end

  local project_name = parse_project_name(yml)
  if not project_name then return nil end

  local target_dir = parse_target_path(yml) or "target"
  if not target_dir:match("^/") then
    target_dir = root .. "/" .. target_dir
  end

  local info = {
    root = root,
    name = project_name,
    target_dir = target_dir,
    manifest_path = target_dir .. "/manifest.json",
  }
  cache[root] = info
  return info
end

function M.clear_cache()
  cache = {}
end

return M
