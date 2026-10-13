-- Studio test runner. Synced by dev.project.json to ServerScriptService.RunTests.
--
-- Usage: `npm run build`, `npm run serve:dev`, connect Rojo in Studio, then press Run (F8).
-- Runs every *.test / *.spec module outside rbxts_include, including @Tag("Studio") tests. Tests
-- tagged "Lune" are left out (see scripts/lunit-tags.luau). Results print to the Output window.
--
-- Opt-in, because the dev place also runs the game: pressing Play should play the game, not run the
-- suite every time. Set the `RunLunitTests` attribute on ServerScriptService to true to turn it on
-- (Studio stores it in the local place file, so it survives a Rojo sync). The Lunit Test Companion
-- doesn't need it: that runs tests from edit mode without pressing Play at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local RUN_ATTRIBUTE = "RunLunitTests"

if ServerScriptService:GetAttribute(RUN_ATTRIBUTE) ~= true then
	print(
		`[tests] skipped: set the {RUN_ATTRIBUTE} attribute on ServerScriptService to run the suite on Play, `
			.. "or use the Lunit Test Companion in VS Code."
	)
	return
end

-- A sibling, not a child of this Script: the Lunit Test Companion's isolation snapshot only
-- accepts Folder/ModuleScript/service ancestors, and a ModuleScript nested under a Script
-- aborts the whole run.
local LunitTags = require(ServerScriptService:WaitForChild("LunitTags"))

local rbxtsInclude = ReplicatedStorage:WaitForChild("rbxts_include")
local TS = require(rbxtsInclude:WaitForChild("RuntimeLib"))
-- Lunit is a package (it reads `_G[script]`), so it must be loaded through TS.import.
local lunit = TS.import(script, rbxtsInclude, "node_modules", "@rbxts", "lunit", "out")

local TEST_ROOT_SERVICES = { ReplicatedStorage, ServerScriptService, StarterPlayer }

local function isTestModule(instance: Instance): boolean
	return instance:IsA("ModuleScript") and (instance.Name:match("%.test$") ~= nil or instance.Name:match("%.spec$") ~= nil)
end

local modules = {}
for _, service in TEST_ROOT_SERVICES do
	for _, root in service:GetChildren() do
		if root ~= rbxtsInclude and root ~= script then
			for _, descendant in root:GetDescendants() do
				if isTestModule(descendant) then
					table.insert(modules, descendant)
				end
			end
		end
	end
end

local classes = {}
local loadFailures = 0
local luneOnly = 0

for _, module in modules do
	local ok, result = pcall(require, module)
	if not ok then
		loadFailures += 1
		warn(`[tests] failed to load {module:GetFullName()}: {result}`)
	elseif type(result) ~= "table" then
		loadFailures += 1
		warn(`[tests] {module:GetFullName()} must \`export =\` its test class`)
	elseif LunitTags.isClassExcluded(result, "Studio") then
		luneOnly += 1
	else
		luneOnly += LunitTags.removeExcludedMethods(result, "Studio")
		if LunitTags.countTests(result) > 0 then
			table.insert(classes, result)
		end
	end
end

print(`[tests] running {#classes} test class(es) from {#modules} module(s)`)
local results = lunit.TestRunner:fromClasses(classes):run():expect()

if luneOnly > 0 then
	print(`[tests] left out {luneOnly} Lune-tagged class(es)/test(s)`)
end
if loadFailures > 0 then
	warn(`[tests] {loadFailures} test module(s) failed to load`)
end
if results.numTestsFailed > 0 or loadFailures > 0 then
	warn(`[tests] FAILED: {results.numTestsFailed} failing test(s), {loadFailures} load failure(s)`)
else
	print(`[tests] PASSED: {results.numTestsPassed} passed, {results.numTestsSkipped} skipped`)
end
