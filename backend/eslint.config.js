import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  // .tmp holds throwaway build output; linting it reports errors in generated
  // JavaScript and hides the real ones.
  { ignores: ['dist/**', '.tmp/**', 'node_modules/**', 'src/db/migrations/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  {
    // CLI entrypoints report progress on stdout; that is their interface.
    files: ['src/db/migrate.ts', 'scripts/**/*.ts'],
    rules: { 'no-console': 'off' },
  },
);
