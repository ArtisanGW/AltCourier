-- The release: what the zip holds and what the game reads. From the repo root:
-- luajit tests/release_test.lua (run.sh runs it).
local function readFile(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
local toc = readFile("AltCourier.toc"):gsub("\r", "")
assert(toc:match("## Version: @project%-version@"), "the version comes from the tag")
assert(toc:match("## IconTexture: Interface\\AddOns\\AltCourier\\Media\\icon%-64%.png"), "its icon in the AddOns list")
assert(not toc:find("OptionalDeps", 1, true) and not toc:find("Dependencies", 1, true), "no other addon")
assert(readFile("Media/icon-64.png"):sub(2, 4) == "PNG", "the icon is a PNG")
local packaging = readFile(".pkgmeta")
for _, ignored in ipairs({ "tests", "CURSEFORGE.md", "Media/icon.svg", "Media/icon-400.png", "Media/alternatives" }) do
    assert(packaging:find("\n  - " .. ignored .. "\n", 1, true), ignored .. " left out of the zip")
end
assert(packaging:find("manual%-changelog:"), "the hand-written changelog")
assert(readFile("CHANGELOG.md"):find("\n## %d+%.%d+%.%d+\n"), "a Major.Minor.Patch section")
assert(readFile("LICENSE"):find("Apache License", 1, true), "Apache 2.0")
print("release_test: ok")
