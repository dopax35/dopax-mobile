CREATE TABLE "auth_identities" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"provider" text NOT NULL,
	"provider_uid" text,
	"firebase_uid" text,
	"email" text,
	"email_verified" boolean DEFAULT false NOT NULL,
	"display_name" text,
	"password_hash" text,
	"password_salt" text,
	"hash_config" jsonb,
	"created_at" timestamp with time zone,
	"last_sign_in_at" timestamp with time zone,
	CONSTRAINT "auth_identities_firebase_uid_unique" UNIQUE("firebase_uid"),
	CONSTRAINT "auth_identities_provider_uid_key" UNIQUE("provider","provider_uid")
);
--> statement-breakpoint
CREATE TABLE "consents" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"document_version" text NOT NULL,
	"document_hash" text NOT NULL,
	"signature_name" text NOT NULL,
	"granted_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"platform" text,
	"app_version" text
);
--> statement-breakpoint
CREATE TABLE "participant_profile_history" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"revision" smallint NOT NULL,
	"snapshot" jsonb NOT NULL,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "participant_profiles" (
	"participant_id" uuid PRIMARY KEY NOT NULL,
	"revision" smallint DEFAULT 1 NOT NULL,
	"age" smallint,
	"gender" text,
	"dominant_hand" text,
	"affected_side" text,
	"medications" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"signature_name" text,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_by_device" uuid
);
--> statement-breakpoint
CREATE TABLE "participants" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_code" text NOT NULL,
	"legacy_file_user_ids" text[] DEFAULT '{}'::text[] NOT NULL,
	"cohort" text,
	"status" text DEFAULT 'active' NOT NULL,
	"is_test_account" boolean DEFAULT false NOT NULL,
	"enrolled_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "participants_participant_code_unique" UNIQUE("participant_code")
);
--> statement-breakpoint
CREATE TABLE "devices" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"device_install_id" text NOT NULL,
	"platform" text NOT NULL,
	"model" text,
	"os_version" text,
	"app_version" text,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "devices_participant_install_key" UNIQUE("participant_id","device_install_id")
);
--> statement-breakpoint
CREATE TABLE "reconciliation_runs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"run_at" timestamp with time zone DEFAULT now() NOT NULL,
	"mode" text NOT NULL,
	"drive_objects" integer NOT NULL,
	"drive_bytes" bigint NOT NULL,
	"db_uploads" integer NOT NULL,
	"db_parsed" integer NOT NULL,
	"missing_in_db" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"missing_in_drive" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"mismatched" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"status" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "upload_files" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"upload_id" uuid NOT NULL,
	"path_in_zip" text NOT NULL,
	"kind" text NOT NULL,
	"row_count" integer,
	"bytes" bigint
);
--> statement-breakpoint
CREATE TABLE "uploads" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"device_id" uuid,
	"platform" text NOT NULL,
	"collection_date" date NOT NULL,
	"filename" text NOT NULL,
	"storage_backend" text DEFAULT 'gdrive' NOT NULL,
	"object_key" text,
	"legacy_drive_file_id" text,
	"bytes" bigint,
	"sha256" text,
	"upload_session_id" text,
	"source" text DEFAULT 'api' NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"received_at" timestamp with time zone,
	"parsed_at" timestamp with time zone,
	"error" text,
	CONSTRAINT "uploads_participant_date_platform_key" UNIQUE("participant_id","collection_date","platform")
);
--> statement-breakpoint
CREATE TABLE "events" (
	"id" bigserial NOT NULL,
	"participant_id" uuid NOT NULL,
	"device_id" uuid,
	"occurred_at" timestamp with time zone NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"event_type" text NOT NULL,
	"session_id" uuid,
	"app_version" text,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"dedupe_key" text NOT NULL,
	CONSTRAINT "events_id_occurred_at_pk" PRIMARY KEY("id","occurred_at")
) PARTITION BY RANGE ("occurred_at");
--> statement-breakpoint
CREATE TABLE "daily_summaries" (
	"participant_id" uuid NOT NULL,
	"day" date NOT NULL,
	"metrics" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "daily_summaries_participant_id_day_pk" PRIMARY KEY("participant_id","day")
);
--> statement-breakpoint
CREATE TABLE "heart_rate_summaries" (
	"participant_id" uuid NOT NULL,
	"day" date NOT NULL,
	"samples" integer DEFAULT 0 NOT NULL,
	"bpm_min" double precision,
	"bpm_max" double precision,
	"bpm_avg" double precision,
	"rr_sdnn_ms" double precision,
	CONSTRAINT "heart_rate_summaries_participant_id_day_pk" PRIMARY KEY("participant_id","day")
);
--> statement-breakpoint
CREATE TABLE "medication_logs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"upload_id" uuid,
	"taken_at" timestamp with time zone NOT NULL,
	"medication_name" text,
	"dosage" text,
	CONSTRAINT "medication_logs_natural_key" UNIQUE("participant_id","taken_at","medication_name")
);
--> statement-breakpoint
CREATE TABLE "physical_activity_logs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"upload_id" uuid,
	"started_at" timestamp with time zone NOT NULL,
	"activity_type" text,
	"time_of_day" text,
	"source" text,
	"external_id" text,
	"duration_min" double precision,
	"calories" double precision,
	"avg_heart_rate" double precision,
	CONSTRAINT "physical_activity_natural_key" UNIQUE("participant_id","started_at","source")
);
--> statement-breakpoint
CREATE TABLE "questionnaire_responses" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"upload_id" uuid,
	"submitted_at" timestamp with time zone NOT NULL,
	"answers" jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT "questionnaire_natural_key" UNIQUE("participant_id","submitted_at")
);
--> statement-breakpoint
CREATE TABLE "sleep_logs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"upload_id" uuid,
	"sleep_start" timestamp with time zone NOT NULL,
	"sleep_end" timestamp with time zone,
	"source" text,
	"provider" text,
	"stage_minutes" jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT "sleep_logs_natural_key" UNIQUE("participant_id","sleep_start","source")
);
--> statement-breakpoint
CREATE TABLE "test_metrics" (
	"session_id" uuid NOT NULL,
	"metric_key" text NOT NULL,
	"metric_value" double precision,
	CONSTRAINT "test_metrics_session_id_metric_key_pk" PRIMARY KEY("session_id","metric_key")
);
--> statement-breakpoint
CREATE TABLE "test_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"participant_id" uuid NOT NULL,
	"device_id" uuid,
	"upload_id" uuid,
	"test_type" text NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone,
	"duration_ms" integer,
	"side" text,
	"dominant_hand" text,
	"affected_side" text,
	"completed" boolean DEFAULT false NOT NULL,
	"metrics" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"raw_object_key" text,
	CONSTRAINT "test_sessions_natural_key" UNIQUE("participant_id","test_type","started_at")
);
--> statement-breakpoint
CREATE TABLE "audit_log" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"actor_type" text NOT NULL,
	"actor_id" text,
	"action" text NOT NULL,
	"subject" text,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"metadata" jsonb
);
--> statement-breakpoint
CREATE TABLE "staff_users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"display_name" text,
	"role" text DEFAULT 'viewer' NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone,
	CONSTRAINT "staff_users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
ALTER TABLE "auth_identities" ADD CONSTRAINT "auth_identities_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "consents" ADD CONSTRAINT "consents_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "participant_profile_history" ADD CONSTRAINT "participant_profile_history_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "participant_profiles" ADD CONSTRAINT "participant_profiles_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "devices" ADD CONSTRAINT "devices_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "upload_files" ADD CONSTRAINT "upload_files_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "uploads" ADD CONSTRAINT "uploads_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "uploads" ADD CONSTRAINT "uploads_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "events" ADD CONSTRAINT "events_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "events" ADD CONSTRAINT "events_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "daily_summaries" ADD CONSTRAINT "daily_summaries_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "heart_rate_summaries" ADD CONSTRAINT "heart_rate_summaries_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "medication_logs" ADD CONSTRAINT "medication_logs_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "medication_logs" ADD CONSTRAINT "medication_logs_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "physical_activity_logs" ADD CONSTRAINT "physical_activity_logs_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "physical_activity_logs" ADD CONSTRAINT "physical_activity_logs_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "questionnaire_responses" ADD CONSTRAINT "questionnaire_responses_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "questionnaire_responses" ADD CONSTRAINT "questionnaire_responses_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sleep_logs" ADD CONSTRAINT "sleep_logs_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sleep_logs" ADD CONSTRAINT "sleep_logs_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "test_metrics" ADD CONSTRAINT "test_metrics_session_id_test_sessions_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."test_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "test_sessions" ADD CONSTRAINT "test_sessions_participant_id_participants_id_fk" FOREIGN KEY ("participant_id") REFERENCES "public"."participants"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "test_sessions" ADD CONSTRAINT "test_sessions_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "test_sessions" ADD CONSTRAINT "test_sessions_upload_id_uploads_id_fk" FOREIGN KEY ("upload_id") REFERENCES "public"."uploads"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "auth_identities_participant_idx" ON "auth_identities" USING btree ("participant_id");--> statement-breakpoint
CREATE INDEX "auth_identities_email_idx" ON "auth_identities" USING btree ("email");--> statement-breakpoint
CREATE INDEX "consents_participant_idx" ON "consents" USING btree ("participant_id","granted_at");--> statement-breakpoint
CREATE INDEX "profile_history_participant_idx" ON "participant_profile_history" USING btree ("participant_id","revision");--> statement-breakpoint
CREATE INDEX "participants_legacy_ids_idx" ON "participants" USING gin ("legacy_file_user_ids");--> statement-breakpoint
CREATE INDEX "participants_status_idx" ON "participants" USING btree ("status");--> statement-breakpoint
CREATE INDEX "devices_last_seen_idx" ON "devices" USING btree ("last_seen_at");--> statement-breakpoint
CREATE INDEX "reconciliation_runs_run_at_idx" ON "reconciliation_runs" USING btree ("run_at");--> statement-breakpoint
CREATE INDEX "upload_files_upload_idx" ON "upload_files" USING btree ("upload_id");--> statement-breakpoint
CREATE INDEX "upload_files_kind_idx" ON "upload_files" USING btree ("kind");--> statement-breakpoint
CREATE INDEX "uploads_status_idx" ON "uploads" USING btree ("status");--> statement-breakpoint
CREATE INDEX "uploads_participant_date_idx" ON "uploads" USING btree ("participant_id","collection_date");--> statement-breakpoint
CREATE INDEX "uploads_source_idx" ON "uploads" USING btree ("source");--> statement-breakpoint
CREATE UNIQUE INDEX "events_dedupe_idx" ON "events" USING btree ("dedupe_key","occurred_at");--> statement-breakpoint
CREATE INDEX "events_participant_time_idx" ON "events" USING btree ("participant_id","occurred_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "events_type_time_idx" ON "events" USING btree ("event_type","occurred_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "events_payload_idx" ON "events" USING gin ("payload");--> statement-breakpoint
CREATE INDEX "daily_summaries_day_idx" ON "daily_summaries" USING btree ("day");--> statement-breakpoint
CREATE INDEX "medication_logs_participant_idx" ON "medication_logs" USING btree ("participant_id","taken_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "physical_activity_participant_idx" ON "physical_activity_logs" USING btree ("participant_id","started_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "questionnaire_participant_idx" ON "questionnaire_responses" USING btree ("participant_id","submitted_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "sleep_logs_participant_idx" ON "sleep_logs" USING btree ("participant_id","sleep_start" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "test_metrics_key_idx" ON "test_metrics" USING btree ("metric_key");--> statement-breakpoint
CREATE INDEX "test_sessions_participant_time_idx" ON "test_sessions" USING btree ("participant_id","started_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "test_sessions_type_idx" ON "test_sessions" USING btree ("test_type");--> statement-breakpoint
CREATE INDEX "audit_log_occurred_idx" ON "audit_log" USING btree ("occurred_at");--> statement-breakpoint
CREATE INDEX "audit_log_actor_idx" ON "audit_log" USING btree ("actor_type","actor_id");--> statement-breakpoint
CREATE INDEX "audit_log_subject_idx" ON "audit_log" USING btree ("subject");--> statement-breakpoint
CREATE INDEX "staff_users_role_idx" ON "staff_users" USING btree ("role");--> statement-breakpoint
--
-- events partitioning. drizzle-kit cannot express PARTITION BY, so the CREATE
-- TABLE above is hand-edited and the partition machinery lives here. Later
-- `drizzle-kit generate` runs diff columns only and will not disturb this.
--
CREATE OR REPLACE FUNCTION ensure_events_partition(target_month date)
RETURNS void AS $$
DECLARE
  start_date date := date_trunc('month', target_month)::date;
  end_date   date := (date_trunc('month', target_month) + interval '1 month')::date;
  part_name  text := format('events_%s', to_char(start_date, 'YYYY_MM'));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = part_name) THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF events FOR VALUES FROM (%L) TO (%L)',
      part_name, start_date, end_date
    );
  END IF;
END;
$$ LANGUAGE plpgsql;--> statement-breakpoint
--
-- Cover the study to date (first production account was created 2026-05-26)
-- plus twelve months ahead. A scheduled job extends the window; the default
-- partition below is only a safety net and should stay empty, because a new
-- partition cannot be created while the default holds rows that belong in it.
--
DO $$
DECLARE
  m date := date '2026-05-01';
BEGIN
  WHILE m < (date_trunc('month', now()) + interval '12 months')::date LOOP
    PERFORM ensure_events_partition(m);
    m := (m + interval '1 month')::date;
  END LOOP;
END;
$$;--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "events_default" PARTITION OF "events" DEFAULT;