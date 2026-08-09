CREATE TABLE "participant_id_conflicts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"legacy_code" text NOT NULL,
	"participant_ids" uuid[] NOT NULL,
	"firebase_uids" text[] NOT NULL,
	"detected_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolution_note" text,
	CONSTRAINT "participant_id_conflicts_legacy_code_unique" UNIQUE("legacy_code")
);
--> statement-breakpoint
ALTER TABLE "auth_identities" ADD COLUMN "linked_providers" jsonb DEFAULT '[]'::jsonb NOT NULL;