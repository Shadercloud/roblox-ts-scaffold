-- Headless test runner: `npm test` (which builds first), or `lune run scripts/test.luau [filter]`.
--
-- Loads the compiled project through the same Rojo tree Studio uses (dev.project.json), finds every
-- ModuleScript named *.test / *.spec outside rbxts_include, and runs them with Lunit. Tests tagged
-- "Studio" are skipped (see scripts/lunit-tags.luau). Exits 1 if any test fails, any test module
-- fails to load, or no tests are found.
--
-- An optional filter (case-insensitive substring of the module's full name) runs a subset.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local LunitTags = require("./lunit-tags")
local rbx = require("./lune/rbx")
local reporter = require("../node_modules/@rbxts/lunit/scripts/lune-reporter")

local PROJECT = "dev.project.json"
local TEST_ROOT_SERVICES = { "ReplicatedStorage", "ServerScriptService", "StarterPlayer" }

local filter = if process.args[1] then string.lower(process.args[1]) else nil

local dataModel = rbx.loadProject(PROJECT)
local game = dataModel.game

-- The real roblox-ts runtime, loaded through the virtual DataModel. Lunit is a package (it reads
-- `_G[script]`), so it must be imported through TS.import, which registers the runtime for it.
local rbxtsInclude = game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include")
local TS = dataModel.require(rbxtsInclude:WaitForChild("RuntimeLib"))
local lunit = TS.import(rbxtsInclude, rbxtsInclude, "node_modules", "@rbxts", "lunit", "out")

local function isTestModule(instance): boolean
	if instance.ClassName ~= "ModuleScript" then
		return false
	end
	return instance.Name:match("%.test$") ~= nil or instance.Name:match("%.spec$") ~= nil
end

local function discover()
	local found = {}
	for _, serviceName in TEST_ROOT_SERVICES do
		local service = game:GetService(serviceName)
		for _, root in service:GetChildren() do
			if root.Name ~= "rbxts_include" then
				if isTestModule(root) then
					table.insert(found, root)
				end
				for _, descendant in root:GetDescendants() do
					if isTestModule(descendant) then
						table.insert(found, descendant)
					end
				end
			end
		end
	end
	return found
end

local function report(kind: "error" | "note", text: string)
	local prefix = if kind == "error" then stdio.color("red") else stdio.style("dim")
	stdio.ewrite(prefix .. text .. stdio.color("reset") .. stdio.style("reset") .. "\n")
end

local modules = discover()
local classes = {}
local loadFailures = 0
local studioModules = 0
local studioTests = 0

for _, module in modules do
	local fullName = module:GetFullName()
	if filter == nil or string.find(string.lower(fullName), filter, 1, true) ~= nil then
		local source = fs.readFile(dataModel.sourcePath(module))
		if LunitTags.sourceHasClassTag(source, "Studio") then
			studioModules += 1
		else
			local ok, result = pcall(dataModel.require, module)
			if not ok then
				loadFailures += 1
				report("error", `[error] failed to load test module {fullName}:\n  {result}`)
			elseif type(result) ~= "table" then
				loadFailures += 1
				report("error", `[error] {fullName} must \`export =\` its test class`)
			elseif LunitTags.isClassExcluded(result, "Lune") then
				studioModules += 1
			else
				studioTests += LunitTags.removeExcludedMethods(result, "Lune")
				if LunitTags.countTests(result) > 0 then
					table.insert(classes, result)
				end
			end
		end
	end
end

if #classes == 0 and loadFailures == 0 then
	print(if filter then `No Lune tests match "{filter}".` else "No Lune tests found.")
	process.exit(1)
end

local results = if #classes > 0 then lunit.TestRunner:fromClasses(classes):run({ reporter = reporter }):expect() else nil

if studioModules > 0 or studioTests > 0 then
	report("note", `Left out {studioModules} Studio-tagged test class(es) and {studioTests} Studio-tagged test(s): run them in Studio.`)
end
if loadFailures > 0 then
	report("error", `{loadFailures} test module(s) failed to load.`)
end

local failed = (results ~= nil and results.numTestsFailed > 0) or loadFailures > 0
process.exit(if failed then 1 else 0)
