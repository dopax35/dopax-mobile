package com.pdcollect.app.service

// ScreenCaptureService was removed (July 2026 review).
//
// It previously used MediaProjection to periodically capture full-resolution
// screenshots of WHATEVER app the participant was using and save them as JPEGs
// on-device whenever more than ~0.01% of sampled pixels changed between frames
// — in practice, on almost every screen update. That's real screen recording,
// not the lightweight "did the screen content change" signal the feature was
// meant to provide, and it was never something we want participants' devices
// doing.
//
// It was also fully inert: this service was never declared in
// AndroidManifest.xml, nothing in the app ever called
// ScreenCaptureService.start(...), the FOREGROUND_SERVICE_MEDIA_PROJECTION
// permission it would need on Android 14+ had already been deliberately
// removed from the manifest, and the "Visual Context" toggle that used to sit
// in Profile Setup only ever flipped a stored preference that nothing read.
//
// If a lightweight "screen changed" event signal is needed again to help
// timestamp/correlate other passive sensor streams, DataAccessibilityService
// already broadcasts ACTION_FOREGROUND_APP_CHANGED whenever the foreground
// app changes — that's the existing, already-wired, non-image-capturing
// mechanism for that purpose. Re-implementing in-app content-change detection
// beyond that would need a fresh design, not a revival of this file.
