CREATE TABLE "migration_steps" (
	"name" text PRIMARY KEY NOT NULL,
	"status" text NOT NULL,
	"input_checksum" text,
	"rows_written" integer,
	"attempts" integer DEFAULT 0 NOT NULL,
	"run_id" uuid,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"duration_ms" integer,
	"error" text,
	"detail" jsonb DEFAULT '{}'::jsonb NOT NULL
);
--> statement-breakpoint
CREATE INDEX "migration_steps_status_idx" ON "migration_steps" USING btree ("status");