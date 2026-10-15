-- Runs every smoke-test scenario with a few different random seeds.
-- Results are printed as GitHub annotations so they show up on the run.
local scenarios = {
  "queue", "mirror", "computer", "pocket", "medium", "monitor", "nospeaker",
  "remote", "remote_wide", "link", "link_basic",
  "wired", "pocket_nospeaker", "pocket_noisy_remote", "basic_auto",
}
local seeds = { 1, 2, 3, 4, 5 }
if (os.getenv("SCENARIOS") or "") ~= "" then
  scenarios = {}
  for name in os.getenv("SCENARIOS"):gmatch("[%w_]+") do scenarios[#scenarios + 1] = name end
end

local function escape(s)
  return (s:gsub("%%", "%%25"):gsub("\r", ""):gsub("\n", "%%0A"))
end

local failed = 0
for _, s in ipairs(scenarios) do
  local summary = {}
  for _, seed in ipairs(seeds) do
    local p = io.popen("timeout 45 lua5.2 tests/ccmock.lua " .. s .. " " .. seed .. " 2>&1; echo \"EXIT:$?\"")
    local out = p:read("*a")
    p:close()
    local code = tonumber(out:match("EXIT:(%d+)%s*$")) or -1
    out = out:gsub("EXIT:%d+%s*$", "")
    io.write(out)
    if code ~= 0 then
      failed = failed + 1
      local why = code == 124 and "timed out (stuck?)" or ("exit code " .. code)
      print("::error title=" .. s .. " seed " .. seed .. "::" .. escape(why .. "\n" .. out:sub(1, 3000)))
    else
      summary[#summary + 1] = (out:match("[^\n]+") or (s .. " ok"))
    end
  end
  if #summary > 0 then print("::notice title=" .. s .. "::" .. escape(table.concat(summary, "\n"))) end
end

print(failed == 0 and "All smoke tests passed" or (failed .. " smoke test run(s) failed"))
os.exit(failed == 0 and 0 or 1)
