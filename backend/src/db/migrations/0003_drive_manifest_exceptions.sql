CREATE TABLE "drive_manifest_exceptions" (
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
);
--> statement-breakpoint
ALTER TABLE "uploads" ADD COLUMN "drive_md5" text;--> statement-breakpoint
CREATE INDEX "drive_manifest_exceptions_reason_idx" ON "drive_manifest_exceptions" USING btree ("reason");--> statement-breakpoint
CREATE INDEX "drive_manifest_exceptions_unresolved_idx" ON "drive_manifest_exceptions" USING btree ("resolved_at");