# Epic 1 Context: Sesión y conteo de pasos nativo

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Paul puede iniciar una caminata y el iPhone cuenta sus pasos solo, con la pantalla bloqueada, el teléfono en el bolsillo y música sonando. Lo hace con el coprocesador de movimiento, muestra métricas en vivo y reconstruye con datos exactos los intervalos que la app pasó en background. Es el corazón del producto: sin esto no importa nada más. Se construye sobre el sustrato SwiftUI nativo del Epic 8, ya terminado. Al cerrar la 1.6 corre el gate 8.4, una caminata real de 30 min, antes de los epics 2–7. Muchos criterios de `epics.md` todavía citan fuentes de Capacitor/PWA (AR-1, AR-2, AR-9, AR-10, `onSteps`, `queryPedometerData` vía plugin, tokens en px, navegación sin tab bar). Están derogados: manda lo que dice este documento.

## Stories

- Story 1.1: Iniciar sesión de caminata con cronómetro wall-clock
- Story 1.2: Conteo de pasos en vivo vía coprocesador (MotionPort)
- Story 1.3: Métricas en vivo — distancia, tiempo, ritmo y cadencia
- Story 1.4: Pausar, reanudar y finalizar sesión (controles)
- Story 1.5: Reconstrucción de intervalos en background por query al sistema
- Story 1.6: Recuperación foreground — wall-clock + Estimated Banner

## Requirements & Constraints

- **Cronómetro wall-clock:** `elapsedS = (now − startedAt) − totalPausesS`. Ningún timer es fuente de verdad: solo refrescan la UI. La pausa es solo explícita, sin auto-pausa, y cambiar de app o bloquear la pantalla nunca pausa. Si Paul pausa 2 min, esos 2 min no cuentan.
- **Aggregate `Session`:** estados `active → paused → active → finished`, más `idle` antes de iniciar. Una sesión finalizada es **inmutable** y cualquier mutación lanza un error de dominio. `stepsMeasured` y `stepsEstimated` son enteros ≥ 0 que nunca bajan de 0. `strideM` debe ser > 0 y finito: se valida en la frontera antes de crear el agregado y queda congelado al cierre. Finalizar desde pausa acumula primero la pausa abierta. `source = "ios"`. Los errores son tipados y distinguen invariante violado de input inválido.
- **Conteo:** siempre del coprocesador del sistema. El `StepDetector` de la PWA (acelerómetro a 60 Hz) queda retirado. Precisión objetivo: ≤ 10 % frente a Apple Salud en 10 min con pantalla bloqueada y música.
- **Métricas:** pasos, distancia, tiempo, ritmo y cadencia.
  - **Distancia:** se usa la del sistema si la da; si no, `(stepsMeasured + stepsEstimated) × strideM` (zancada por defecto 0,655 m). La UI no distingue la fuente.
  - **Ritmo:** `paceSecPerKm` solo con distancia ≥ 100 m; por debajo es `nil` y la UI muestra "—".
  - **Cadencia:** solo sobre tramos medidos, nunca sobre pasos estimados.
- **Reconstrucción del background:** al volver a foreground o al finalizar, los pasos del gap salen de una consulta por rango al sistema, y `stepsEstimated` sigue en 0. El `GapEstimator` es solo una degradación excepcional: `stepsEstimated += cadenceSpm × gapS/60`, y solo si la sesión está activa y hay una muestra previa de ≥ 120 s (si no, el gap es 0). Lo estimado se muestra siempre desglosado, marcado "~" y descartable; si Paul lo descarta, se recalculan distancia y ritmo.
- **Recuperación:** tras un force-quit o un paso por background, la sesión se restaura en silencio con el tiempo recalculado desde `startedAt`, y aparece el indicador "Sesión recuperada" durante 3 s. Si la sesión activa es más antigua que el umbral de sesión huérfana, se cierra recortada al último dato real del coprocesador, se marca `recovered: true` y no dispara logros ni celebración.
- **Degradación:** Motion & Fitness denegado es la **única** degradación bloqueante: muestra una pantalla explicativa con acceso a Ajustes y no arranca el núcleo.
- **Batería (medida en la 8.4):** 30 min de sesión con ≤ 5 % de caída y WalkTracker no destacado en Ajustes → Batería.
- **Validación:** siempre en el iPhone 14 físico. El simulador no tiene coprocesador y no sirve ni para el conteo ni para la reconstrucción.

## Technical Decisions

- **Capas hexagonales:** `Domain/` importa solo Foundation; un import de plataforma ahí rompe el build. El dominio nunca llama a `Date()`, `Date.now`, `random()` ni `Calendar.current`: el tiempo llega por `ClockPort`, que también expone el único `AppCalendar` (ISO-8601, lunes, zona del dispositivo). Crear una sesión y calcular métricas son funciones puras con vectores.
- **Swift idiomático, no `domain.js` transliterado:** value types `Sendable`, `throws` con errores tipados, opcionales para métricas ausentes y nombres del lenguaje ubicuo (`Session`, `Chronometer`, `MetricsCalculator`, `CalibrationProfile`, `GapEstimator`). La equivalencia con la v3 se demuestra con vectores y escenarios, y `Scripts/verify-domain.sh` en verde es **Definition of Done** de toda historia que toque `Domain/`.
- **AD-22, magnitudes con fuente:** la pantalla solo muestra magnitudes que produce el dominio. Una métrica nueva exige antes su cálculo en `Domain/` con su vector. Nada de calorías ni de puntos.
- **Escritor único:** `SessionStore` (`@MainActor @Observable`, en `Application/`) es lo único que muta la sesión. Adapters y timers solo publican eventos, y las vistas llaman a métodos de intención, nunca escriben propiedades.
- **Frontera de CoreMotion:** `MotionAdapter` es el único que conoce `CMPedometer`. El handler corre en su cola serie y copia los valores a un DTO `Sendable` dentro del propio handler; `CMPedometerData` y sus `NSNumber` no cruzan al main actor. Ninguna vista importa CoreMotion. El puerto ya existe con muestras acumuladas desde `start` (`updates(from:)`), una consulta por rango (`query(from:to:)` → muestra o `nil`) y `status`/`requestPermission()`. El permiso lo gestiona el adapter y va precedido de una pre-pantalla.
- **Cadencias de energía:** `CMPedometer` en modo continuo mientras hay sesión, y la consulta histórica solo para reconciliar (no se combinan). La UI refresca a **1 Hz** y solo redibuja la vista de sesión; las métricas derivadas se recalculan con el dato del coprocesador, no con el tick.
- **Reconciliación atómica (AD-8):**
  - Mientras dura, el store está en `reconciling`: rechaza comandos y la UI los deshabilita. `SessionStatus` no cambia.
  - Termina antes de refrescar la UI.
  - Un gap que empezó hace más de 7 días no se consulta, porque el sistema devuelve datos parciales sin avisar: pasa directo a estimación "~".
  - La operación está acotada por un **timeout de reconciliación**; al agotarse degrada y libera los comandos.
- **Constantes provisionales:** el timeout de reconciliación (1.5) y el umbral de sesión huérfana (1.6) viven en `Resources/formulas.json`, no en el código. Entran con **valores provisionales marcados como tales** y la 8.4 los reemplaza por los medidos. Las constantes del JS que se porten (p. ej. `0.655`) se consolidan en ese mismo fichero.
- **Persistencia de la sesión viva:** `activeSession.json` en Application Support, JSON `Codable` con `schemaVersion` y escritura atómica (temporal + rename). Su único dueño es `SessionStore`. Autosave cada 10 s y al pasar a background. El dominio trabaja en **segundos**; los milisegundos del formato de snapshot se convierten en el adapter de persistencia.
- **Puertos pendientes:** faltan `WakeLockPort` (`isIdleTimerDisabled`) y `StoragePort`, dentro del conjunto cerrado de 11 puertos. Nombres `XxxPort` / `XxxAdapter` / `XxxStub`.
- **Convenciones:** metros y segundos en el dominio; la conversión a km y `mm:ss` vive en `UI/Format/`. Timestamps ISO-8601 con fracción y zona. Swift Testing para dominio y aplicación. Logging con `OSLog`, sin telemetría.

## UX & Interaction Patterns

- **El vocabulario visual está en código, y es la fuente:** `WalkTracker/UI/Style/DesignTokens.swift` (chore de tokens, 2026-09-18). Espaciado (`Spacing`, la escala 4/8/12/16/24 de UX-DR3), margen y objetivo táctil de 44 pt (`LayoutMetrics`), radio de tarjeta (`Radius.card`, 20), relleno de tarjeta (`Surface`, 16/12), los dos roles tipográficos que el sistema no nombra (`Typography`) y los dos colores propios (`Colors.accent` verde lima / oliva, `Colors.estimated` para lo estimado), los dos como colorset con variante clara y oscura y contraste medido. **Ninguna vista los reteclea:** la sección 12 de `Scripts/check-project-shape.sh` falla si dentro de `WalkTracker/UI/` aparece un lado de marco numérico (`minHeight: 44`, `.frame(height: 44)`), un radio de esquina numérico (`cornerRadius: 16`, `.cornerRadius(16)`), un color en hexadecimal o por componentes, `.orange`, o un peldaño de la escala —4, 8, 12, 16, 24— escrito a mano en `spacing:`, `minLength:` o `.padding(…)`. Lo que la spec decide no tokenizar (`spacing: 0`, `spacing: 2`, `.padding(.top, 48)`) sigue pasando. La misma sección comprueba que `project.yml` mantenga `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`: sin esa key el acento vuelve al azul del sistema.
- La sesión activa es un **modo**: se presenta como `fullScreenCover` sobre un `TabView` de 4 pestañas (Inicio · Historial · Logros · Ajustes). No es una quinta pestaña. "Iniciar caminata" es el CTA principal de Inicio.
- Controles nativos de SwiftUI con Liquid Glass heredado. Colores del sistema, sin hex cableados, y claro/oscuro. SF Symbols en el chrome, sin emoji. Textos en español en `Localizable.xcstrings`, con su capitalización final.
- La métrica principal domina con estilos de texto del sistema y Dynamic Type sin recortes, **sin tamaños fijos**. Una sola señal de "en curso", nunca pill + badge a la vez. La pausa se ve en la propia pantalla de sesión, con los controles Reanudar / Finalizar.
- Targets ≥ 44 pt. **Finalizar sesión** y **descartar pasos estimados** son irreversibles: exigen confirmación explícita y salen de una superficie declarada. Nada de un segundo botón "✕" ambiguo junto a Finalizar.
- Cuando hay pasos estimados, un Estimated Banner descartable los muestra desglosados con "~". El indicador "Sesión recuperada" dura 3 s y no bloquea ni muestra pantalla de carga. Motion Denied es una pantalla completa con explicación y enlace a Ajustes.
- Accesibilidad: VoiceOver lee la magnitud completa ("3,2 kilómetros") y anuncia los pasos estimados como estimados. Se respeta Reduce Motion. Tono "celebrar, nunca culpar".
- Los mockups de `ux-walktracker-native` son **dirección visual, no contrato de build**: su fixture es aritméticamente incoherente y muestran kcal, ritmo con menos de 100 m y doble indicador de directo. Se toma la jerarquía (número enorme + rejilla de métricas, distancia atenuada en pausa), no sus números ni sus extras.

## Cross-Story Dependencies

- Orden `1.1 → 1.6`. 1.2 y 1.3 alimentan el agregado de 1.1; 1.4 cierra el ciclo de estados; 1.5 depende del conteo (1.2) y de la cadencia (1.3); 1.6 depende de 1.5 (reconciliar antes de refrescar) y de la persistencia de `activeSession.json`.
- **Gate 8.4:** requiere 1.1–1.6 en `done` e instaladas por TestFlight. Mide el conteo y la UI a 1 Hz, exige `stepsEstimated = 0` y sustituye las dos constantes provisionales. Los epics 2–7 no arrancan sin superarlo.
- **Epic 8 (hecho):** proyecto XcodeGen (regenerar tras añadir ficheros; `Scripts/check-project-shape.sh`), puertos `Clock`, `Motion`, `Feedback`, `Health` y `LiveActivity` con sus adapters, y `verify-domain.sh`.
- **Epics posteriores que consumen este:** la sesión finalizada alimenta clima/frase (2), logros y meta (3, evaluados al finalizar), feedback (4), historial y la persistencia completa `StoragePort` (5.1), escritura en Salud (6) y Live Activity por evento (7).
