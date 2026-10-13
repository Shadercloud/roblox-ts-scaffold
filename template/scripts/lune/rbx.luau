-- A minimal, read-only Roblox DataModel for Lune, built from a Rojo project file.
--
-- roblox-ts output for a game project finds everything through the DataModel:
--   local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
--   TS.import(script, game:GetService("ReplicatedStorage"), "Common", "constants")
-- so this module rebuilds that tree from the same Rojo project Studio uses, maps each node back to
-- its file, and loads modules with `script`, `game` and `require` pointing into the tree. The real
-- include/RuntimeLib.lua and include/Promise.lua run unchanged on top of it, so Lune executes the
-- exact Luau that Studio does.
--
-- It also injects Roblox datatypes (Vector3, CFrame, Color3, ...) from @lune/roblox as globals.
-- Instances and engine services are NOT available: only the stubs below exist.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

-- Datatypes from @lune/roblox exposed as globals, matching the engine's.
local DATATYPE_NAMES = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Enum",
	"Faces",
	"Font",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"PhysicalProperties",
	"Ray",
	"Rect",
	"Region3",
	"Region3int16",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
}

local rbx = {}

local function warn(...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	stdio.ewrite(stdio.color("yellow") .. table.concat(parts, "\t", 1, parts.n) .. stdio.color("reset") .. "\n")
end
rbx.warn = warn

-- Glob patterns from a project's globIgnorePaths, as Lua patterns over project-relative paths.
local function globToPattern(glob: string): string
	local pattern = glob:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
	pattern = pattern:gsub("%*%*/", "\0"):gsub("%*%*", "\1"):gsub("%*", "[^/]*")
	pattern = pattern:gsub("%z", ".-/?"):gsub("\1", ".*")
	return "^" .. pattern .. "$"
end

local function normalize(path: string): string
	path = path:gsub("\\", "/"):gsub("/%./", "/"):gsub("^%./", "")
	-- Collapse "a/../" segments.
	local changed = true
	while changed do
		local replaced
		path, replaced = path:gsub("[^/%.][^/]*/%.%./", "", 1)
		changed = replaced > 0
	end
	return path
end

local function join(dir: string, name: string): string
	if dir == "" or dir == "." then
		return name
	end
	return dir .. "/" .. name
end

local function dirname(path: string): string
	return path:match("^(.*)/[^/]*$") or "."
end

-- Rojo's file → instance rules, for Luau sources only (other file types are not needed here).
local function classifyFile(fileName: string): (string?, string?)
	local base = fileName:match("^(.+)%.server%.luau?$")
	if base then
		return base, "Script"
	end
	base = fileName:match("^(.+)%.client%.luau?$")
	if base then
		return base, "LocalScript"
	end
	base = fileName:match("^(.+)%.luau?$")
	if base then
		return base, "ModuleScript"
	end
	return nil, nil
end

local INIT_FILES = {
	{ "init.luau", "ModuleScript" },
	{ "init.lua", "ModuleScript" },
	{ "init.server.luau", "Script" },
	{ "init.server.lua", "Script" },
	{ "init.client.luau", "LocalScript" },
	{ "init.client.lua", "LocalScript" },
}

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

local Instance = {}
local InstanceMeta = {}

local SCRIPT_CLASSES = { ModuleScript = true, Script = true, LocalScript = true }

function InstanceMeta.__index(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	local method = Instance[key]
	if method ~= nil then
		return method
	end
	local child = Instance.FindFirstChild(self, key)
	if child ~= nil then
		return child
	end
	error(`{tostring(key)} is not a valid member of {rawget(self, "ClassName")} "{Instance.GetFullName(self)}"`, 2)
end

function InstanceMeta.__tostring(self)
	return rawget(self, "Name")
end

local function newInstance(context, name: string, className: string, parent, source: string?, dir: string?)
	return setmetatable({
		Name = name,
		ClassName = className,
		_parent = parent,
		_source = source,
		_dir = dir,
		_context = context,
		_explicit = {},
		_explicitOrder = {},
		_children = nil,
	}, InstanceMeta)
end

local function isIgnored(context, path: string): boolean
	local relative = normalize(path)
	for _, pattern in context.ignore do
		if relative:match(pattern) then
			return true
		end
	end
	return false
end

local nodeFromDirectory
local nodeFromTree

local function nodeFromFile(context, name: string?, path: string, parent)
	local base, className = classifyFile(path:match("[^/]+$") :: string)
	if base == nil then
		return nil
	end
	return newInstance(context, name or base, className :: string, parent, path, nil)
end

function nodeFromDirectory(context, name: string, path: string, parent, classNameOverride: string?)
	local nestedProject = join(path, "default.project.json")
	if fs.isFile(nestedProject) then
		return nodeFromTree(context, name, rbx.readProject(nestedProject).tree, parent, path)
	end
	for _, init in INIT_FILES do
		local initPath = join(path, init[1])
		if fs.isFile(initPath) then
			return newInstance(context, name, init[2], parent, initPath, path)
		end
	end
	return newInstance(context, name, classNameOverride or "Folder", parent, nil, path)
end

function nodeFromTree(context, name: string, tree, parent, baseDir: string)
	local node
	local path = tree["$path"]
	if type(path) == "table" then
		-- Rojo's `{ "optional": "path" }` form: fine if the path doesn't exist.
		path = path.optional
	end
	if path ~= nil then
		local resolved = normalize(join(baseDir, path))
		if fs.isDir(resolved) then
			node = nodeFromDirectory(context, name, resolved, parent, tree["$className"])
		elseif fs.isFile(resolved) then
			node = nodeFromFile(context, name, resolved, parent)
		end
	end
	if node == nil then
		-- Missing $path (e.g. not built yet) or no $path: an empty container.
		node = newInstance(context, name, tree["$className"] or "Folder", parent, nil, nil)
	end
	for key, value in tree do
		if type(key) == "string" and key:sub(1, 1) ~= "$" then
			local child = nodeFromTree(context, key, value, node, baseDir)
			node._explicit[key] = child
			table.insert(node._explicitOrder, child)
		end
	end
	return node
end

local function loadChildren(self)
	local children = rawget(self, "_children")
	if children ~= nil then
		return children
	end
	children = { byName = {}, list = {} }
	local function add(child)
		if child ~= nil and children.byName[child.Name] == nil then
			children.byName[child.Name] = child
			table.insert(children.list, child)
		end
	end
	for _, child in rawget(self, "_explicitOrder") do
		add(child)
	end
	local dir = rawget(self, "_dir")
	local context = rawget(self, "_context")
	if dir ~= nil and fs.isDir(dir) then
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local path = join(dir, entry)
			if not isIgnored(context, path) then
				if fs.isDir(path) then
					add(nodeFromDirectory(context, entry, path, self, nil))
				elseif not entry:match("^init%.") then
					add(nodeFromFile(context, nil, path, self))
				end
			end
		end
	end
	rawset(self, "_children", children)
	return children
end

function Instance.FindFirstChild(self, name: string, recursive: boolean?)
	local children = loadChildren(self)
	local found = children.byName[name]
	if found ~= nil or not recursive then
		return found
	end
	for _, child in children.list do
		found = Instance.FindFirstChild(child, name, true)
		if found ~= nil then
			return found
		end
	end
	return nil
end

function Instance.WaitForChild(self, name: string)
	local child = Instance.FindFirstChild(self, name)
	if child == nil then
		-- Studio would wait forever; headlessly the file simply doesn't exist.
		error(`{name} is not a child of "{Instance.GetFullName(self)}" (is the project built?)`, 2)
	end
	return child
end

function Instance.GetChildren(self)
	return table.clone(loadChildren(self).list)
end

function Instance.GetDescendants(self)
	local result = {}
	local function walk(node)
		for _, child in loadChildren(node).list do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(self)
	return result
end

function Instance.IsA(self, className: string): boolean
	local own = rawget(self, "ClassName")
	return own == className
		or className == "Instance"
		or (className == "LuaSourceContainer" and SCRIPT_CLASSES[own] == true)
		or (className == "BaseScript" and (own == "Script" or own == "LocalScript"))
end

function Instance.FindFirstAncestorWhichIsA(self, className: string)
	local current = rawget(self, "_parent")
	while current ~= nil do
		if Instance.IsA(current, className) then
			return current
		end
		current = rawget(current, "_parent")
	end
	return nil
end

function Instance.IsDescendantOf(self, ancestor): boolean
	local current = rawget(self, "_parent")
	while current ~= nil do
		if current == ancestor then
			return true
		end
		current = rawget(current, "_parent")
	end
	return false
end

function Instance.GetFullName(self): string
	local names = {}
	local current = self
	while current ~= nil and rawget(current, "_parent") ~= nil do
		table.insert(names, 1, rawget(current, "Name"))
		current = rawget(current, "_parent")
	end
	return table.concat(names, ".")
end

function Instance.GetService(self, name: string)
	local service = Instance.FindFirstChild(self, name)
	if service ~= nil then
		return service
	end
	local stubs = rawget(self, "_context").services
	if stubs[name] == nil then
		stubs[name] = newInstance(rawget(self, "_context"), name, name, self, nil, nil)
	end
	return stubs[name]
end

--------------------------------------------------------------------------------
-- Engine stubs: just enough for RuntimeLib and Promise to load.
--------------------------------------------------------------------------------

local function makeHeartbeat()
	local signal = {}
	function signal.Connect(_, callback)
		local connection = { Connected = true }
		function connection.Disconnect()
			connection.Connected = false
		end
		task.spawn(function()
			while connection.Connected do
				local dt = task.wait()
				if connection.Connected then
					callback(dt)
				end
			end
		end)
		return connection
	end
	function signal.Wait()
		return task.wait()
	end
	return signal
end

local function makeRunService()
	local function no()
		return false
	end
	return {
		Name = "RunService",
		ClassName = "RunService",
		Heartbeat = makeHeartbeat(),
		IsStudio = no,
		IsRunning = no,
		IsClient = no,
		IsServer = no,
		IsEdit = no,
	}
end

--------------------------------------------------------------------------------
-- Projects and module loading
--------------------------------------------------------------------------------

function rbx.readProject(projectFile: string)
	return serde.decode("json", fs.readFile(projectFile))
end

-- Builds the DataModel for `projectFile` and returns `{ game, require }`.
-- `require` loads a ModuleScript instance the way Studio's `require` would.
function rbx.loadProject(projectFile: string)
	local project = rbx.readProject(projectFile)
	local context = { ignore = {}, services = {} }
	for _, glob in project.globIgnorePaths or {} do
		table.insert(context.ignore, globToPattern(glob))
	end
	context.services.RunService = makeRunService()

	local game = nodeFromTree(context, "Game", project.tree, nil, dirname(projectFile))

	-- Scan the whole tree now. Lune's fs calls yield, and a child lookup can happen inside the
	-- __index metamethod (`script.Parent.charm`), where yielding is an error. The tree is small
	-- (a few hundred files), so eager loading costs little.
	local function preload(node)
		for _, child in loadChildren(node).list do
			preload(child)
		end
	end
	preload(game)

	local sharedG = {}
	local moduleCache = {}
	local loading = {}
	local datatypes = {}
	for _, name in DATATYPE_NAMES do
		datatypes[name] = roblox[name]
	end

	local requireModule

	-- Roblox's require-by-string, resolved in the instance tree: "./x" is a sibling of the script,
	-- "../x" a sibling of its parent, and "@self/x" a child of the script itself.
	local function resolveStringRequire(script, path: string)
		local segments = string.split(path, "/")
		local current
		local first = segments[1]
		if first == "@self" then
			current = script
		elseif first == "." then
			current = rawget(script, "_parent")
		elseif first == ".." then
			current = rawget(rawget(script, "_parent") or {}, "_parent")
		else
			error(`unsupported require path "{path}" in {Instance.GetFullName(script)}`, 3)
		end
		for i = 2, #segments do
			local segment = segments[i]
			if current == nil then
				break
			elseif segment == ".." then
				current = rawget(current, "_parent")
			elseif segment ~= "." and segment ~= "" then
				current = Instance.FindFirstChild(current, segment)
			end
		end
		if current == nil then
			error(`could not resolve require "{path}" from {Instance.GetFullName(script)}`, 3)
		end
		return current
	end

	local function environmentFor(script)
		local env = {
			script = script,
			game = game,
			workspace = Instance.FindFirstChild(game, "Workspace"),
			require = function(target)
				if type(target) == "string" then
					return requireModule(resolveStringRequire(script, target))
				end
				return requireModule(target)
			end,
			task = task,
			warn = warn,
			_G = sharedG,
			tick = os.clock,
		}
		for name, value in datatypes do
			env[name] = value
		end
		return env
	end

	function requireModule(module)
		if type(module) ~= "table" or getmetatable(module) ~= InstanceMeta then
			error(`require expects a ModuleScript, got {typeof(module)}`, 2)
		end
		local cached = moduleCache[module]
		if cached ~= nil then
			return cached.value
		end
		if rawget(module, "ClassName") ~= "ModuleScript" or rawget(module, "_source") == nil then
			error(`require expects a ModuleScript, got {rawget(module, "ClassName")} "{module:GetFullName()}"`, 2)
		end
		if loading[module] then
			error(`circular require of "{module:GetFullName()}"`, 2)
		end
		loading[module] = true
		local source = fs.readFile(rawget(module, "_source"))
		local chunk = luau.load(source, {
			debugName = rawget(module, "_source"),
			environment = environmentFor(module),
		})
		local ok, value = pcall(chunk)
		loading[module] = nil
		if not ok then
			error(value, 0)
		end
		moduleCache[module] = { value = value }
		return value
	end

	return {
		game = game,
		require = requireModule,
		-- The file a script instance was built from, or nil.
		sourcePath = function(instance): string?
			return rawget(instance, "_source")
		end,
		-- Runs a plain script (Script/LocalScript or any source) with this DataModel as its world.
		environmentFor = environmentFor,
	}
end

return rbx
