import { z } from 'zod';

/**
 * Environment is parsed once at boot and fails loudly. A misconfigured
 * BOTH_ARCH or STORAGE_BACKEND must never be discovered halfway through an
 * ingestion run.
 */

/** Accepts the shapes an env var realistically arrives in, yields a real boolean. */
const booleanish = z
  .enum(['true', 'false', '1', '0'])
  .transform((v) => v === 'true' || v === '1');

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(8080),
    LOG_LEVEL: z
      .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace'])
      .default('info'),

    // R3 — see backend/docs/MIGRATION_PLAN.md §4.2
    BOTH_ARCH: booleanish.default(true),
    LEGACY_DRIVE_DRAIN: booleanish.default(true),

    DATABASE_URL: z.string().url(),

    // Inspected read-only by `npm run db:inspect -- --remote`. Never used by the
    // running server, and never by a migration: R5 requires production to
    // migrate itself.
    RAILWAY_DATABASE_URL: z.string().url().optional().or(z.literal('')),

    STORAGE_BACKEND: z.enum(['gdrive', 'minio', 's3', 'azure']).default('gdrive'),
    S3_ENDPOINT: z.string().url().optional(),
    S3_REGION: z.string().default('us-east-1'),
    S3_BUCKET: z.string().optional(),
    S3_ACCESS_KEY_ID: z.string().optional(),
    S3_SECRET_ACCESS_KEY: z.string().optional(),
    S3_FORCE_PATH_STYLE: booleanish.default(false),
    AZURE_STORAGE_CONNECTION_STRING: z.string().optional(),
    AZURE_STORAGE_CONTAINER: z.string().optional(),

    FIREBASE_PROJECT_ID: z.string().min(1),
    GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
    AUTH_DEV_BYPASS: booleanish.default(false),

    LEGACY_DRIVE_FOLDER_ID: z.string().optional(),
    LEGACY_APPS_SCRIPT_URL: z.string().url().optional().or(z.literal('')),

    // R5 — where the first-run bootstrap reads the production exports from.
    // Resolved against the process working directory, so the default reaches
    // the repository root only because the npm scripts run from `backend/`.
    // Production should set an absolute path to wherever they are mounted.
    MIGRATION_SOURCE_DIR: z.string().default('..'),

    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    JWT_ACCESS_TTL: z.coerce.number().int().positive().default(900),
    JWT_REFRESH_TTL: z.coerce.number().int().positive().default(2_592_000),

    // The staff console reads participant data, so it is opt-in per environment
    // rather than on by default.
    ADMIN_API_ENABLED: booleanish.default(false),
    ADMIN_JWT_SECRET: z.string().optional(),
    ADMIN_SESSION_TTL: z.coerce.number().int().positive().default(3_600),
    ADMIN_DEV_LOGIN: booleanish.default(false),
  })
  .superRefine((env, ctx) => {
    if (env.AUTH_DEV_BYPASS && env.NODE_ENV !== 'development') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['AUTH_DEV_BYPASS'],
        message: 'AUTH_DEV_BYPASS may only be enabled when NODE_ENV=development',
      });
    }

    if (env.ADMIN_API_ENABLED) {
      if (!env.ADMIN_JWT_SECRET || env.ADMIN_JWT_SECRET.length < 32) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['ADMIN_JWT_SECRET'],
          message:
            'ADMIN_JWT_SECRET must be at least 32 characters when ADMIN_API_ENABLED=true',
        });
      }

      // Sharing the secret would make a participant token and a staff token
      // interchangeable, which is the one failure this split is here to prevent.
      if (env.ADMIN_JWT_SECRET && env.ADMIN_JWT_SECRET === env.JWT_SECRET) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['ADMIN_JWT_SECRET'],
          message: 'ADMIN_JWT_SECRET must differ from JWT_SECRET',
        });
      }
    }

    if (env.ADMIN_DEV_LOGIN && !(env.NODE_ENV === 'development' && env.AUTH_DEV_BYPASS)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['ADMIN_DEV_LOGIN'],
        message:
          'ADMIN_DEV_LOGIN requires NODE_ENV=development and AUTH_DEV_BYPASS=true',
      });
    }

    if (env.STORAGE_BACKEND === 'minio' || env.STORAGE_BACKEND === 's3') {
      for (const key of ['S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY'] as const) {
        if (!env[key]) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: [key],
            message: `${key} is required when STORAGE_BACKEND=${env.STORAGE_BACKEND}`,
          });
        }
      }
    }

    if (env.STORAGE_BACKEND === 'azure' && !env.AZURE_STORAGE_CONNECTION_STRING) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['AZURE_STORAGE_CONNECTION_STRING'],
        message: 'AZURE_STORAGE_CONNECTION_STRING is required when STORAGE_BACKEND=azure',
      });
    }

    // Drive passthrough and the drain worker both read the legacy folder.
    if ((env.STORAGE_BACKEND === 'gdrive' || env.LEGACY_DRIVE_DRAIN) && !env.LEGACY_DRIVE_FOLDER_ID) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['LEGACY_DRIVE_FOLDER_ID'],
        message:
          'LEGACY_DRIVE_FOLDER_ID is required when STORAGE_BACKEND=gdrive or LEGACY_DRIVE_DRAIN=true',
      });
    }
  });

export type Env = z.infer<typeof schema>;

let cached: Env | undefined;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);

  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `  ${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${details}`);
  }

  return parsed.data;
}

export function env(): Env {
  cached ??= loadEnv();
  return cached;
}
