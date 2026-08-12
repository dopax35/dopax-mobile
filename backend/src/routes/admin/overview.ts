import type { FastifyInstance } from 'fastify';
import {
  activityOverview,
  dataQualityOverview,
  enrolmentOverview,
  recentReconciliationRuns,
  uploadOverview,
} from '../../domain/admin/queries.js';
import { assessFlipReadiness } from '../../domain/admin/view.js';
import type { AdminRouteDependencies } from './index.js';

export async function adminOverviewRoutes(
  app: FastifyInstance,
  dependencies: AdminRouteDependencies,
): Promise<void> {
  app.get('/me', { config: { audit: false } }, async (request) => ({
    staff: request.staff,
  }));

  /**
   * Aggregate counts only, so it is exempt from the audit trail — the console
   * polls it, and filling audit_log with "someone looked at a total" would bury
   * the participant-level reads that the trail exists to make findable.
   */
  app.get('/overview', { config: { audit: false } }, async () => {
    const { database } = dependencies;

    const [enrolment, uploads, activity, dataQuality, runs] = await Promise.all([
      enrolmentOverview(database),
      uploadOverview(database),
      activityOverview(database),
      dataQualityOverview(database),
      recentReconciliationRuns(database, 30),
    ]);

    return {
      enrolment,
      uploads,
      activity,
      dataQuality,
      reconciliation: {
        latest: runs[0] ?? null,
        flip: assessFlipReadiness(runs),
      },
      /**
       * Why the activity panels can legitimately be empty during the migration.
       * Without this a reader cannot tell "no participant is active" from "the
       * parse pipeline has not run yet", and those call for opposite responses.
       */
      pipeline: {
        uploadsAwaitingParse: uploads.byStatus.pending ?? 0,
        activityDependsOnParse: activity.events === 0 && activity.testSessions === 0,
        // A database missing migration 0003 cannot list unattributable Drive
        // objects, and reporting zero of them would be a false all-clear.
        schemaOutOfDate: dataQuality.exceptionsAvailable
          ? null
          : { missing: 'drive_manifest_exceptions', migration: '0003_drive_manifest_exceptions' },
      },
    };
  });
}
