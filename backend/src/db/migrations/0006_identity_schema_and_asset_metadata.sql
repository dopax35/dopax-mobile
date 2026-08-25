-- Splits the pseudo-ID↔identity map out of the research data, and gives the asset
-- catalogue the columns a researcher needs to filter on.
--
-- Both halves answer the data-analyst review in docs/DATA_CATALOG_REVIEW.md.
--
-- The separation is the important one. Until now `auth_identities` sat in `public`
-- beside every clinical table, so the only thing standing between a database
-- connection and a participant's email was application code. Moving the three
-- identifying tables into their own schema and granting the research role USAGE on
-- `public` alone makes that boundary something PostgreSQL enforces.
--
-- Nothing here is destructive and no row changes value. `ALTER TABLE ... SET SCHEMA`
-- moves a table without rewriting it, cross-schema foreign keys to
-- `public.participants` keep working untouched, and no `participant_code` is
-- renumbered. Every statement is guarded so a re-run is a no-op (R5).

CREATE SCHEMA IF NOT EXISTS "identity";--> statement-breakpoint

-- ---------------------------------------------------------------------------
-- 1. Move the identifying tables
-- ---------------------------------------------------------------------------
-- auth_identities holds email / display_name / firebase_uid — the map itself.
-- consents holds signature_name and signature_image, which identify a person as
-- directly as a name does, and the analyst's design puts consent records in the
-- locked store alongside the map.
-- email_otp_codes is a table of plaintext email addresses.

DO $$
BEGIN
  IF to_regclass('public.auth_identities') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.auth_identities SET SCHEMA "identity"';
  END IF;

  IF to_regclass('public.consents') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.consents SET SCHEMA "identity"';
  END IF;

  IF to_regclass('public.email_otp_codes') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.email_otp_codes SET SCHEMA "identity"';
  END IF;
END
$$;--> statement-breakpoint

-- ---------------------------------------------------------------------------
-- 2. The research role
-- ---------------------------------------------------------------------------
-- A NOLOGIN group role, deliberately. The migration defines what a researcher may
-- read; it does not mint a credential. Ops creates a login user with a password
-- from Key Vault and grants it membership, so no secret is ever written here.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dopax_research') THEN
    CREATE ROLE "dopax_research" NOLOGIN;
  END IF;
END
$$;--> statement-breakpoint

REVOKE ALL ON SCHEMA "identity" FROM PUBLIC;--> statement-breakpoint
REVOKE ALL ON SCHEMA "identity" FROM "dopax_research";--> statement-breakpoint

GRANT USAGE ON SCHEMA "public" TO "dopax_research";--> statement-breakpoint
GRANT SELECT ON ALL TABLES IN SCHEMA "public" TO "dopax_research";--> statement-breakpoint

-- No ALTER DEFAULT PRIVILEGES on purpose. A table added later is invisible to the
-- research role until somebody grants it explicitly, so the failure mode of
-- forgetting is "researcher cannot see new data" rather than "researcher silently
-- gained access to it".

-- ---------------------------------------------------------------------------
-- 3. Identifying columns that remain in `public`
-- ---------------------------------------------------------------------------
-- Moving whole tables does not finish the job. These three still carry identity in
-- a schema the research role can reach.
--
--   participant_profiles.signature_name  a typed legal name
--   participant_profiles.settings        an opaque jsonb passthrough of
--                                        platform-specific profile fields, so its
--                                        contents cannot be guaranteed pseudonymous
--   participant_profile_history.snapshot a whole profile including both of the above
--
-- staff_users and audit_log are withheld for a different reason: they describe our
-- own people, and audit_log.metadata quotes the subject of a staff read.

REVOKE SELECT ON "public"."participant_profiles" FROM "dopax_research";--> statement-breakpoint
REVOKE SELECT ON "public"."participant_profile_history" FROM "dopax_research";--> statement-breakpoint
REVOKE SELECT ON "public"."staff_users" FROM "dopax_research";--> statement-breakpoint
REVOKE SELECT ON "public"."audit_log" FROM "dopax_research";--> statement-breakpoint

GRANT SELECT (
  "participant_id",
  "revision",
  "age",
  "gender",
  "dominant_hand",
  "affected_side",
  "medications",
  "updated_at",
  "updated_by_device"
) ON "public"."participant_profiles" TO "dopax_research";--> statement-breakpoint

-- ---------------------------------------------------------------------------
-- 4. Asset catalogue columns
-- ---------------------------------------------------------------------------
-- captured_at is the fix for the review's headline query. `uploads.collection_date`
-- is a date on the ZIP, so the tightest join a researcher could write was
-- same-calendar-day — an order of magnitude wider than the medication window that
-- makes the question clinically meaningful. This is a real timestamp per file.
--
-- Nullable, and it stays null wherever the source carries no usable time. A guessed
-- capture time is worse than an absent one.

ALTER TABLE "upload_files" ADD COLUMN IF NOT EXISTS "captured_at" timestamp with time zone;--> statement-breakpoint

-- quality_status answers "is this analysable", which status/error/row_count never
-- did — those describe whether *parsing* worked. quality_flags keeps the specific
-- reasons so a researcher can decide rather than trust a verdict.
ALTER TABLE "upload_files" ADD COLUMN IF NOT EXISTS "quality_status" text DEFAULT 'unknown' NOT NULL;--> statement-breakpoint
ALTER TABLE "upload_files" ADD COLUMN IF NOT EXISTS "quality_flags" jsonb DEFAULT '[]'::jsonb NOT NULL;--> statement-breakpoint

-- Set only when exactly one session claims the file. A motor CSV holds many
-- START/END cycles and therefore many sessions, and picking one of them would be a
-- guess; those rows keep a null and the join goes through test_sessions.raw_object_key.
ALTER TABLE "upload_files" ADD COLUMN IF NOT EXISTS "session_id" uuid;--> statement-breakpoint

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'upload_files_session_id_test_sessions_id_fk'
  ) THEN
    ALTER TABLE "upload_files"
      ADD CONSTRAINT "upload_files_session_id_test_sessions_id_fk"
      FOREIGN KEY ("session_id") REFERENCES "public"."test_sessions"("id")
      ON DELETE SET NULL ON UPDATE NO ACTION;
  END IF;
END
$$;--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "upload_files_captured_at_idx" ON "upload_files" USING btree ("captured_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "upload_files_session_idx" ON "upload_files" USING btree ("session_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "upload_files_quality_idx" ON "upload_files" USING btree ("quality_status");
