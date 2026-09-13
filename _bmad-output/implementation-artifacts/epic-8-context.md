# Epic 8 Context: Fundaciones del sustrato SwiftUI

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Levantar el sustrato sobre el que se construye todo lo demás: un proyecto Xcode SwiftUI limpio con un único árbol de producto, la capa nativa ya escrita rescatada y troceada en adapters, un arnés que demuestra que el dominio portado a Swift se comporta como el validado en producción, y la app instalada de forma duradera vía TestFlight. No cubre ningún requisito funcional, pero el sustrato corre **primero**: sin él cada epic posterior improvisa su propia versión de la verdad. La excepción es su gate final (8.4): una caminata real de 30 minutos en el iPhone 14 que demuestra precisión y consumo aceptables, y que por medir una sesión real corre **después del Epic 1** y antes de los epics 2–7. El epic se reescribió el 2026-09-12 al pivotar de Capacitor a SwiftUI nativo; todo lo que hable de WebView, plugins Capacitor, `pnpm cap run ios` o doble canal PWA está derogado y no vincula.

## Stories

- Story 8.5: Proyecto SwiftUI y limpieza del árbol
- Story 8.6: Extracción de la capa nativa desde `feature/flutter-substrate`
- Story 8.7: Sustrato de verificación del dominio
- Story 8.3: Distribución TestFlight con versionado SemVer
- Story 8.4: Gate del Success signal — batería y precisión en dispositivo físico

**Orden de ejecución: `8.5 → 8.6 → 8.7 → 8.3`, después Epic 1 (1.1–1.6) `→ 8.4`, antes de los epics 2–7.** Los números no son el orden. Las historias 8.1 y 8.2 están **anuladas** (sustrato Capacitor); sus IDs no se reutilizan y no aparecen en el tracking.

## Requirements & Constraints

- **Dominio preservado, no defectos preservados.** Los invariantes de la v3 (wall-clock, pausa explícita, sesión finalizada inmutable, zancada congelada al cierre, validación en frontera, pasos estimados siempre desglosados) vinculan; los bugs ya corregidos en la referencia JS no deben reintroducirse.
- **Hexagonal verificable:** dominio puro, puertos definidos por el núcleo, adapters en el borde. La violación se detecta en build, no en revisión.
- **Licencias:** Apache-2.0/MIT en código; CC-BY 4.0 admitido solo en fuentes de datos, con atribución visible. Copyleft fuerte bloqueante. Cero dependencias de terceros.
- **Distribución:** TestFlight como canal duradero al iPhone 14 de Paul, bundle id `com.walktracker.app`, releases con **SemVer**. Requiere cuenta Apple Developer de pago. App Store fuera de scope; la PWA ya no se despliega.
- **Toolchain congelado durante el ciclo:** **Xcode 26.3 (17C529) / Swift 6.2.4 / SDK iOS 26.2**, deployment target 26.0 — versiones verificadas en la máquina (suelo, no techo; subir dentro del ciclo 26 es seguro). No se sube a Xcode 27. El iPhone 14 se queda en iOS 26 con actualizaciones automáticas desactivadas; la primera sesión tras actualizar a iOS 27 es revalidación obligatoria del conteo y la reconstrucción.
- **Success signal (gate de 8.4, enmendado de 60 a 30 min):** caminata de **30 min** con teléfono en el bolsillo, música y pantalla bloqueada sin tocarla. Criterios: pasos y distancia a **≤ 10 %** de Apple Salud; batería con caída **≤ 5 %** en los 30 min y WalkTracker **no destacado** en Ajustes → Batería; sesión completa con **`stepsEstimated` = 0** (gaps reconstruidos por consulta al sistema, no por estimación). Si falla algún criterio, se revisa antes de seguir con los epics 2–7.
- **Validación en dispositivo físico:** el simulador no tiene coprocesador y no sirve para conteo ni reconstrucción. Sin CI, sin crash reporting ni analítica.

## Technical Decisions

- **Sustrato y suelo:** SwiftUI nativo contra el SDK de iOS 26, sin WebView/Capacitor/Flutter. **Prohibido** cualquier `if #available` hacia versiones anteriores. Bundle id inmutable.
- **Un solo árbol:** el producto vive en `WalkTracker/`. `domain.js`, `motivation.js`, `climate.js`, `storage.js` y `test/` se conservan **congelados** como referencia de contraste, no como código vivo.
- **Tres targets:** app, `Shared` (contrato de la Live Activity y su formateo) y Widget Extension (solo render, importa solo `Shared`). `Info.plist` con usage strings de Motion, Salud y Ubicación, `NSSupportsLiveActivities` y entitlement de HealthKit.
- **Capas:** `Domain/` solo Foundation; `Application/` → Domain; `Adapters/` implementan puertos de Domain; `UI/` → Application y Domain (lectura). El dominio nunca llama a `Date()` ni a aleatorios: llegan por `ClockPort`/`RandomPort`. Conjunto cerrado de 11 puertos (`Motion`, `Location`, `Weather`, `Health`, `Feedback`, `Notification`, `LiveActivity`, `WakeLock`, `Storage`, `Clock`, `Random`). Nombres `XxxPort` / `XxxAdapter` / `XxxStub`.
- **Concurrencia estricta completa (Swift 6):** tipos de dominio value types `Sendable`; `@unchecked Sendable` exige justificación en código. `CMPedometerData` y sus `NSNumber` se traducen a un DTO `Sendable` propio **dentro del handler** de CoreMotion; solo ese DTO cruza al main actor, donde `SessionStore` es el único escritor.
- **Capa nativa por extracción, no merge:** el `AppDelegate.swift` de `feature/flutter-substrate` (`d9d3fbc`, no ancestro de `HEAD`) entra por checkout de ese fichero y se trocea en adapters; no queda lógica de sistema en el delegado.
- **Equivalencia con la v3:** la suite JS se reparte en vectores de datos (ejecutados por ambos runtimes), escenarios portados a mano a Swift Testing y excluidos declarados (agregada v1 de vueltas). Vectores de `GoalEngine` y de los 14 logros escritos de nuevo. Solo **dos** divergencias declaradas: hora local en vez de UTC y lluvia por código WMO en vez de regex. `Scripts/verify-domain.sh` en verde es **Definition of Done** de toda historia que toque `Domain/`.
- **Catálogo de logros en datos, evaluación en Swift:** `Resources/achievements.json` con `schemaVersion`, clave estable, `metric` de enum cerrado, `threshold` y `comparison` (`gte · lte · eq · gt · lt · between`, `between` inclusivo). Evaluador con `switch` exhaustivo; el arranque valida 14 entradas y **falla ruidosamente**, nunca degrada.
- **Presupuesto de energía (tres cadencias):** conteo continuo con `CMPedometer` mientras hay sesión (la query histórica solo para reconciliar), UI a 1 Hz redibujando solo la vista de sesión, Live Activity solo por evento con el reloj animado por `Text(timerInterval:)`. La 8.4 mide las dos primeras; la cadencia de la Live Activity la recomprueba la 7.2 con el mismo umbral de batería.
- **Constantes provisionales:** el timeout de reconciliación y el umbral de sesión huérfana viven en `formulas.json`. Las historias 1.5 y 1.6 los introducen con **valores provisionales marcados**; la 8.4 los **reemplaza** por los medidos en el iPhone 14.
- **Atribución:** Open-Meteo (CC-BY 4.0) se atribuye en Ajustes → Acerca de.

## Cross-Story Dependencies

- **El sustrato (8.5, 8.6, 8.7, 8.3) bloquea a los demás epics** — ya está completo. **La 8.4 es la excepción:** no bloquea al Epic 1, sino que depende de él (1.1–1.6 en `done`) y bloquea a los epics 2–7. El Epic 8 sigue `in-progress` hasta que la 8.4 cierre.
- Dependencia circular rota por diseño: la 8.4 fija el timeout de reconciliación y el umbral de sesión huérfana que 1.5 y 1.6 usan; el Epic 1 arranca con valores provisionales y la 8.4 los sustituye.
- `8.4` requiere la app instalada en el iPhone 14 por TestFlight (canal de `8.3`) con la sesión real del Epic 1.
- `8.7` es precondición permanente: su script es DoD de toda historia posterior que toque el dominio (sesión, metas/logros, calibración, historial).
- `8.6` adelantó trabajo de feedback háptico (Epic 4), Apple Salud (Epic 6) y Live Activity (Epic 7); lo que no funcionó en dispositivo cuenta como coste adicional de Epic 6 y 7.
- La 7.2 recomprueba la batería (≤ 5 % en 30 min, WalkTracker no destacado) con la Live Activity activa, porque la 8.4 no puede medirla.
- El wake lock de la anulada 8.2 sobrevive como `WakeLockPort` dentro de Epic 1.
