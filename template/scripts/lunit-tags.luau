--!strict
-- __GAME_NAME__'s runtime tags for Lunit tests, shared by the Lune runner (scripts/test.luau)
-- and the Studio runner (scripts/studio/run-tests.server.luau).
--
--   @Tag("Studio")  needs the engine (Instances, services, React mounting): not run under Lune.
--   @Tag("Lune")    only meaningful headlessly: not run in Studio.
--   untagged        runs in both.
--
-- Lunit's own `tags` run option can only include tags, not exclude them, so excluded tests are
-- removed from the class before it runs, and the runner reports how many were left out.
-- (Marking them disabled instead makes Lunit's summary list them under "Failures".)

export type Runtime = "Lune" | "Studio"

local LunitTags = {}

local function hasTag(tags: { string }?, tag: string): boolean
	if tags == nil then
		return false
	end
	return table.find(tags, tag) ~= nil
end

function LunitTags.excludedTag(runtime: Runtime): string
	return if runtime == "Lune" then "Studio" else "Lune"
end

-- True when the whole class is tagged to be left out of `runtime`.
function LunitTags.isClassExcluded(ctor: any, runtime: Runtime): boolean
	local classMetadata = ctor["lunit:class"]
	return classMetadata ~= nil and hasTag(classMetadata.tags, LunitTags.excludedTag(runtime))
end

-- Removes every test method tagged to be left out of `runtime`. Returns how many were removed.
function LunitTags.removeExcludedMethods(ctor: any, runtime: Runtime): number
	local excluded = LunitTags.excludedTag(runtime)
	local methods = ctor["lunit:method:test"]
	if methods == nil then
		return 0
	end
	local removed = 0
	for name, method in methods do
		if method.options.isTest and hasTag(method.options.tags, excluded) then
			methods[name] = nil
			removed += 1
		end
	end
	return removed
end

-- Number of test methods on a class.
function LunitTags.countTests(ctor: any): number
	local count = 0
	for _, method in ctor["lunit:method:test"] or {} do
		if method.options.isTest then
			count += 1
		end
	end
	return count
end

-- True when compiled Luau source declares its test class with a class-level @Tag(tag). roblox-ts
-- compiles `@Tag("Studio") class X {}` to `X = Tag("Studio")(X) or X`. The Lune runner uses this to
-- avoid even loading Studio-only modules, which may touch the engine at load time.
function LunitTags.sourceHasClassTag(source: string, tag: string): boolean
	for className in source:gmatch(`Tag%(%s*"{tag}"%s*%)%(%s*([%w_]+)%s*%)`) do
		if source:find(`{className}%s*=%s*Tag%(%s*"{tag}"%s*%)%(%s*{className}%s*%)%s*or%s*{className}`) then
			return true
		end
	end
	return false
end

return LunitTags
