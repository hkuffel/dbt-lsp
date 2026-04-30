-- Minimal self-contained test for dbt.jump.detect.
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/jump_detect_spec.lua" -c "qa"

local jump = require("dbt.jump")

local failed = 0
local passed = 0

local function assert_eq(actual, expected, label)
  local function dump(v)
    if type(v) == "table" then return vim.inspect(v) end
    return tostring(v)
  end
  if vim.deep_equal(actual, expected) then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL %s\n  expected: %s\n  actual:   %s", label, dump(expected), dump(actual)))
  end
end

-- col is 0-indexed (matches nvim_win_get_cursor)
local function check(line, col, expected, label)
  assert_eq(jump.detect(line, col), expected, label)
end

-- ref('foo')
check("select * from {{ ref('orders') }}", 21,
  { kind = "ref", args = { "orders" } }, "ref('orders') cursor on name")

-- ref with two args
check("{{ ref('pkg', 'orders') }}", 16,
  { kind = "ref", args = { "pkg", "orders" } }, "ref('pkg','orders')")

-- ref with double quotes
check([[from {{ ref("orders") }}]], 13,
  { kind = "ref", args = { "orders" } }, "ref with double quotes")

-- source('raw','users')
check("from {{ source('raw', 'users') }}", 18,
  { kind = "source", args = { "raw", "users" } }, "source(raw,users)")

-- macro inside {{ }}
check("{{ generate_schema_name('foo') }}", 7,
  { kind = "macro", args = { "generate_schema_name" } }, "macro inside {{ }}")

-- not on a ref/macro -> nil
check("select 1 as x", 5, nil, "plain SQL returns nil")

-- cursor outside the ref() span
check("select * from {{ ref('orders') }}", 0, nil, "cursor before ref returns nil")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then vim.cmd("cq") end
