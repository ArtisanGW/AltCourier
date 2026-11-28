-- Loads the addon's files in the order its .toc lists them, as the game does.
-- Returns the shared addon table. Run from the repo root.
return function(addonName)
  local addon = {}
  for line in io.lines("AltCourier.toc") do
    line = line:gsub("\r", ""):gsub("\\", "/")
    if line:match("%.lua$") then assert(loadfile(line))(addonName, addon) end
  end
  return addon
end
