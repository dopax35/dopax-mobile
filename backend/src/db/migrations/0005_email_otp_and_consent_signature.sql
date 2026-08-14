-- Email sign-in codes (Figma frames 6377:2 / 6377:21) and the drawn-signature
-- fields the redesigned consent screen captures.
--
-- Both additions are additive. R1 holds: a verified code mints a Firebase custom
-- token, so Firebase is still the identity provider and no existing credential
-- is touched. Existing consents keep a NULL signature_image and stay valid as
-- given — nobody is re-consented because a newer screen collects more.

CREATE TABLE IF NOT EXISTS "email_otp_codes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"code_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"consumed_at" timestamp with time zone,
	"request_ip" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "email_otp_codes_email_idx" ON "email_otp_codes" USING btree ("email","created_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "email_otp_codes_expires_idx" ON "email_otp_codes" USING btree ("expires_at");--> statement-breakpoint

ALTER TABLE "consents" ADD COLUMN IF NOT EXISTS "signature_image" text;--> statement-breakpoint
ALTER TABLE "consents" ADD COLUMN IF NOT EXISTS "document_locale" text;
