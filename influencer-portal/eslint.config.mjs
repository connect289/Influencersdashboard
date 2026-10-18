// ESLint flat config: Next's rules plus typescript-eslint's strict type-checked set. `any` is an error everywhere.
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import next from "eslint-config-next";

export default tseslint.config(
  {
    ignores: [
      ".next/**",
      "node_modules/**",
      "next-env.d.ts",
      "lib/database.types.ts",
      "playwright-report/**",
      "test-results/**",
      "supabase/**",
      "public/**",
    ],
  },
  js.configs.recommended,
  ...next,
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports", fixStyle: "inline-type-imports" },
      ],
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/restrict-template-expressions": ["error", { allowNumber: true }],
      "@typescript-eslint/no-confusing-void-expression": "off",
      "@typescript-eslint/no-misused-promises": ["error", { checksVoidReturn: { attributes: false } }],
      "no-console": ["error", { allow: ["warn", "error", "info"] }],
    },
  },
  {
    files: ["**/*.mjs", "scripts/**/*.mjs"],
    ...tseslint.configs.disableTypeChecked,
  },
);
