# Deferred Work

- source_spec: `_bmad-output/implementation-artifacts/spec-8-6-extraccion-de-la-capa-nativa.md`
  summary: Borrar `WalkTracker/UI/Diagnostics/NativeLayerDiagnosticsView.swift` cuando exista la UI de sesión, y con ella deshacer su cableado — devolver `RootView` a no genérica (sin el parámetro `Diagnostics`, su `NavigationLink` ni la extensión `where Diagnostics == Never`) y quitar la rama `#if DEBUG` de `WalkTrackerApp`.
  evidence: La pantalla de diagnóstico es la superficie temporal de verificación en el iPhone de los cuatro adapters de la 8.6 (decisión de Paul, 2026-09-12); la UI de sesión la sustituye como consumidor real de los puertos.
- source_spec: `_bmad-output/implementation-artifacts/spec-8-6-extraccion-de-la-capa-nativa.md`
  summary: Probar que `FeedbackAdapter.fire` solo reproduce sonido cuando `soundEnabled` es `true`, y con el `SystemSoundID` del evento.
  evidence: Hueco de verificación de la revisión de la 8.6 (V6): invertir la condición no lo detecta ningún test ni check manual. Falta un hook inyectable para `AudioServicesPlaySystemSound`; encaja con la historia 4.2, dueña de la preferencia de sonido.
- source_spec: `_bmad-output/implementation-artifacts/spec-8-7-sustrato-de-verificacion-del-dominio.md`
  summary: Portar a mano a Swift Testing los escenarios de AD-6 —64 sitios de aserción / 163 ejecutadas, todos en `test/session-v3-tests.js` (secuencias de comandos sobre el agregado de sesión)—, cada uno en la historia del Epic 1 que porta la parte del agregado que ejercita. Reparto, según `WalkTrackerTests/Vectors/inventory.json`: 1.1: 14 · 1.2: 8 · 1.3: 11 · 1.4: 18 · 1.5: 3 · 1.6: 10.
  evidence: Separado de la 8.7 por decisión de Paul (2026-09-12): sin `Session` en Swift no hay runtime contra el que ejecutarlos, y portarlos en la 8.7 obligaría a escribir antes el agregado de las historias 1.1–1.4. La 8.7 los deja clasificados y citados, no portados.
- source_spec: `_bmad-output/implementation-artifacts/spec-8-7-sustrato-de-verificacion-del-dominio.md`
  summary: Probar que el arranque termina (y nunca devuelve un catálogo parcial o vacío) cuando `achievements.json` no valida.
  evidence: Hueco de verificación de la revisión de la 8.7 (V3): sustituir el `fatalError` de `CompositionRoot.bundledAchievementCatalogOrTerminate()` por un catálogo vacío deja todos los tests en verde. Hace falta una costura (bundle y terminación inyectables); encaja cuando el Epic 3 lea el catálogo por primera vez.
- source_spec: `_bmad-output/implementation-artifacts/spec-8-3-distribucion-testflight-con-versionado-semver.md`
  summary: Comprobar en `release-testflight.sh`, tras archivar, que `PrivacyInfo.xcprivacy` está dentro de `WalkTracker.app` y que su `Info.plist` lleva `ITSAppUsesNonExemptEncryption = false`.
  evidence: Hueco de verificación de la revisión de la 8.3 (V4): hoy solo se comprobó a mano en el archivo real. Se vuelve importante con la primera historia que use una API con motivo obligatorio (el manifiesto deja de estar vacío) o que añada red (clima).
