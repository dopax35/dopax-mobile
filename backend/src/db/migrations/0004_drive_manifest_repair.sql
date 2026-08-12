-- Repairs databases that recorded a migration at ordinal 0003 which never reached
-- version control. Drizzle applies migrations strictly by timestamp, so the
-- committed 0003_drive_manifest_exceptions is skipped forever on any database
-- whose ledger already passed it, leaving no table and no drive_md5 column.
--
-- Every statement is conditional, so this is a no-op on a database that applied
-- the committed 0003 normally. Nothing is dropped: the orphaned column stays put
-- until someone confirms nothing reads it.

CREATE TABLE IF NOT EXISTS "drive_manifest_exceptions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"drive_file_id" text NOT NULL,
	"filename" text NOT NULL,
	"bytes" bigint,
	"drive_md5" text,
	"reason" text NOT NULL,
	"detail" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolution_note" text,
	CONSTRAINT "drive_manifest_exceptions_drive_file_id_unique" UNIQUE("drive_file_id")
);--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "drive_manifest_exceptions_reason_idx" ON "drive_manifest_exceptions" USING btree ("reason");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "drive_manifest_exceptions_unresolved_idx" ON "drive_manifest_exceptions" USING btree ("resolved_at");--> statement-breakpoint

ALTER TABLE "uploads" ADD COLUMN IF NOT EXISTS "drive_md5" text;--> statement-breakpoint

-- The shadowed migration stored the same checksum under a different name. Carried
-- across so reconciliation does not have to re-read every object from Drive.
-- Dynamic because "legacy_drive_md5" does not exist on a correctly migrated
-- database, and a static reference to a missing column fails at parse time.
DO $$
BEGIN
	IF EXISTS (
		SELECT 1 FROM information_schema.columns
		WHERE table_name = 'uploads' AND column_name = 'legacy_drive_md5'
	) THEN
		EXECUTE 'UPDATE uploads SET drive_md5 = legacy_drive_md5
		         WHERE drive_md5 IS NULL AND legacy_drive_md5 IS NOT NULL';
	END IF;
END $$;
