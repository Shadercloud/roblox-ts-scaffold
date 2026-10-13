// Flat-config translation of react-clean-ui's .eslintrc.json (ESLint 9 no longer reads .eslintrc),
// plus __GAME_NAME__'s layout rules.
import js from "@eslint/js";
import prettierRecommended from "eslint-plugin-prettier/recommended";
import robloxTs from "eslint-plugin-roblox-ts";
import tseslint from "typescript-eslint";

/** Globals that reach the engine, the clock or the scheduler. Pure domain code gets these injected instead. */
const ENGINE_GLOBALS = [
	"game",
	"workspace",
	"script",
	"plugin",
	"Instance",
	"task",
	"wait",
	"delay",
	"spawn",
	"tick",
	"time",
	"elapsedTime",
	"os",
].map((name) => ({
	name,
	message: "game/shared/domain is pure: no engine, clock or scheduler access. Pass what you need in as a parameter.",
}));

export default tseslint.config(
	{
		ignores: ["out/", "out-tools/", "include/", "node_modules/", "**/*.luau", "*.mjs"],
	},
	js.configs.recommended,
	...tseslint.configs.recommended,
	robloxTs.configs.recommended,
	prettierRecommended,
	{
		files: ["**/*.ts", "**/*.tsx"],
		languageOptions: {
			parser: tseslint.parser,
			parserOptions: {
				ecmaVersion: 2018,
				sourceType: "module",
				ecmaFeatures: { jsx: true },
				// Explicit projects rather than roblox-ts's default projectService: tools/ is only in tsconfig.tools.json.
				projectService: false,
				project: ["./tsconfig.json", "./tsconfig.tools.json"],
				tsconfigRootDir: import.meta.dirname,
			},
		},
		rules: {
			"prettier/prettier": "warn",
		},
	},
	{
		// Flamework networking declares events/functions as interfaces, which start out empty.
		files: ["src/**/net/**/*.ts"],
		rules: {
			"@typescript-eslint/no-empty-object-type": ["error", { allowInterfaces: "always" }],
		},
	},
	{
		// The key layout rule: pure domain logic never touches Roblox services, Instances or the scheduler,
		// which is what lets its tests run headlessly under Lune. The domain's tests live under
		// tests/game/shared/domain and are held to the same rule, so they stay runnable under Lune.
		files: [
			"src/game/shared/domain/**/*.ts",
			"src/game/shared/domain/**/*.tsx",
			"tests/game/shared/domain/**/*.ts",
			"tests/game/shared/domain/**/*.tsx",
		],
		rules: {
			"no-restricted-imports": [
				"error",
				{
					patterns: [
						{
							group: ["@rbxts/*", "!@rbxts/lunit", "@flamework/*"],
							message: "game/shared/domain is pure: no Roblox packages, services, UI or Flamework.",
						},
						{
							group: ["**/server/**", "**/client/**", "**/net/**", "**/server", "**/client", "**/net"],
							message: "game/shared/domain must not depend on server, client or networking code.",
						},
					],
				},
			],
			"no-restricted-globals": ["error", ...ENGINE_GLOBALS],
		},
	},
);
