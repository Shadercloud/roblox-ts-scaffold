-- Runs a command-line tool compiled from tools/ under Lune.
--
--   npm run tool -- <name> [args...]         builds the tools first
--   lune run scripts/tool.luau <name> [args...]
--
-- A tool is tools/<name>.ts exporting `main(host: ToolHost): number` (see tools/host.ts). It is
-- loaded through the same virtual DataModel as the tests (scripts/lune/rbx.luau), so it runs the
-- same compiled Luau, on the same roblox-ts runtime, that Studio does.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local rbx = require("./lune/rbx")

local name = process.args[1]
if name == nil then
	print("usage: lune run scripts/tool.luau <name> [args...]")
	process.exit(2)
end

local dataModel = rbx.loadProject("tools.project.json")
local toolsFolder = dataModel.game:GetService("ReplicatedStorage"):WaitForChild("Tools"):FindFirstChild("tools")
local module = if toolsFolder then toolsFolder:FindFirstChild(name) else nil
if module == nil or module.ClassName ~= "ModuleScript" then
	stdio.ewrite(`No tool "{name}" in out-tools/tools. Is it in tools/, and have you run \`npm run build:tools\`?\n`)
	process.exit(2)
end

local host = {
	args = { table.unpack(process.args, 2) },
	readFile = function(path: string): string
		return fs.readFile(path)
	end,
	writeFile = function(path: string, contents: string)
		local parent = path:gsub("\\", "/"):match("^(.*)/[^/]*$")
		if parent ~= nil and parent ~= "" and not fs.isDir(parent) then
			fs.writeDir(parent)
		end
		fs.writeFile(path, contents)
	end,
}

local ok, result = pcall(function()
	return dataModel.require(module).main(host)
end)
if not ok then
	stdio.ewrite(stdio.color("red") .. `tool "{name}" failed: {result}\n` .. stdio.color("reset"))
	process.exit(1)
end
process.exit(if type(result) == "number" then result else 0)
