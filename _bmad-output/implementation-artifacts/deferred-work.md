# Deferred Work

- source_spec: `_bmad-output/implementation-artifacts/spec-8-6-extraccion-de-la-capa-nativa.md`
  summary: Borrar `WalkTracker/UI/Diagnostics/NativeLayerDiagnosticsView.swift` cuando exista la UI de sesión, y con ella deshacer su cableado — devolver `RootView` a no genérica (sin el parámetro `Diagnostics`, su `NavigationLink` ni la extensión `where Diagnostics == Never`) y quitar la rama `#if DEBUG` de `WalkTrackerApp`.
  evidence: La pantalla de diagnóstico es la superficie temporal de verificación en el iPhone de los cuatro adapters de la 8.6 (decisión de Paul, 2026-09-12); la UI de sesión la sustituye como consumidor real de los puertos.
- source_spec: `_bmad-output/implementation-artifacts/spec-8-6-extraccion-de-la-capa-nativa.md`
  summary: Probar que `FeedbackAdapter.fire` solo reproduce sonido cuando `soundEnabled` es `true`, y con el `SystemSoundID` del evento.
  evidence: Hueco de verificación de la revisión de la 8.6 (V6): invertir la condición no lo detecta ningún test ni check manual. Falta un hook inyectable para `AudioServicesPlaySystemSound`; encaja con la historia 4.2, dueña de la preferencia de sonido.
