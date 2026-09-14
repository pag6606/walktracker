# Epic 8 Context: Fundaciones del sustrato SwiftUI

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Levantar el sustrato sobre el que se construye todo lo demás: un proyecto Xcode SwiftUI limpio con un único árbol de producto, la capa nativa rescatada y troceada en adapters, un arnés que demuestra que el dominio portado a Swift se comporta como el validado en producción, y la app instalada de forma duradera vía TestFlight. No cubre requisitos funcionales, pero sin él cada epic posterior improvisa su propia versión de la verdad. **Estado actual:** el sustrato (8.5, 8.6, 8.7, 8.3) está `done`, y el Epic 1 (1.1–1.6) también, con retrospectiva `accepted-with-open-items`. Solo queda el gate final, la **8.4**: una caminata real de 30 min en el iPhone 14 que demuestra precisión y consumo aceptables sobre la sesión del Epic 1, fija las constantes que el Epic 1 dejó provisionales y zanja las dudas de CoreMotion diferidas durante ese epic. El epic se reescribió el 2026-09-12 al pivotar de Capacitor a SwiftUI nativo; lo que hable de WebView, plugins Capacitor, `pnpm cap run ios` o doble canal PWA está derogado y no vincula.

## Stories

- Story 8.5: Proyecto SwiftUI y limpieza del árbol (`done`)
- Story 8.6: Extracción de la capa nativa desde `feature/flutter-substrate` (`done`)
- Story 8.7: Sustrato de verificación del dominio (`done`)
- Story 8.3: Distribución TestFlight con versionado SemVer (`done`)
- Story 8.4: Gate del Success signal — batería y precisión en dispositivo físico (pendiente)

Orden: `8.5 → 8.6 → 8.7 → 8.3`, después Epic 1 `→ 8.4`, antes de los epics 2–7. Las historias 8.1 y 8.2 están anuladas (sustrato Capacitor); sus IDs no se reutilizan.

## Requirements & Constraints

- **Gate del Success signal (30 min, enmendado desde 60):** caminata con el teléfono en el bolsillo, música y pantalla bloqueada **sin tocarla**. Criterios:
  - pasos y distancia a **≤ 10 %** de Apple Salud;
  - batería con caída **≤ 5 %** en los 30 min y WalkTracker **no destacado** en Ajustes → Batería (el porcentaje global solo no distingue la app de la música);
  - sesión registrada completa con **`stepsEstimated = 0`**: los gaps de background se reconstruyen por consulta al sistema, no por estimación.
- **Si falla algún criterio, se revisa antes de seguir con los epics 2–7.** El riesgo se paga aquí.
- **Qué se mide:** las dos cadencias que existen tras el Epic 1, conteo continuo y UI a 1 Hz. La Live Activity por evento **no** se mide aquí.
- **Constantes provisionales a reemplazar:** `formulas.json` tiene hoy `reconciliationTimeoutS: 3` y `orphanSessionThresholdS: 21600` (6 h), las dos listadas en `provisional`. La 8.4 las sustituye por valores medidos en el iPhone 14 y deja registrada la medición de referencia.
- **Instrumentación de la caminata** (lo pide la retro del Epic 1): registrar con `OSLog`, en formato exportable, cada muestra del stream (`steps`, `distance`, `end`), cada consulta de reconciliación (rango, resultado, acumulado ya visto, duración) y cada estimación. Con esos datos hay que decidir:
  - si la consulta puede devolver **menos** que lo ya visto, lo que hoy se trata como "sin dato" y produce pasos estimados fantasma (potencialmente alto);
  - si el stream entrega **después** de una reconciliación degradada el acumulado del gap, lo que causaría doble cuenta;
  - si la distancia del sistema **alterna** entre muestras con y sin `distance`, y cómo se comporta con **fuentes mezcladas entre tramos** de pausa y reanudación.
- **Privacidad:** sin telemetría, analítica ni red para la instrumentación. El registro vive en el dispositivo y se exporta a mano.
- **Solo dispositivo físico:** el simulador no tiene coprocesador. La build llega por TestFlight. El iPhone 14 sigue en iOS 26 con actualizaciones automáticas desactivadas.
- **Dominio preservado, no defectos preservados.** Los invariantes de la v3 vinculan, y los bugs corregidos en la referencia JS no se reintroducen. Licencias Apache-2.0/MIT en código (CC-BY 4.0 solo en datos, con atribución). Cero dependencias de terceros.

## Technical Decisions

- **Sustrato:** SwiftUI nativo contra el SDK de iOS 26, deployment target 26.0, **prohibido** `if #available` hacia atrás. Bundle id `com.walktracker.app`. Tres targets: app, `Shared` y Widget Extension (solo render). Toolchain congelado: Xcode 26.3 / Swift 6.2.4 / SDK iOS 26.2, verificado como suelo. No se sube a Xcode 27.
- **Capas hexagonales:** `Domain/` solo Foundation, sin `Date()` ni aleatorios (van por `ClockPort`/`RandomPort`); conjunto cerrado de 11 puertos; nombres `XxxPort` / `XxxAdapter` / `XxxStub`. Concurrencia estricta de Swift 6: `CMPedometerData` se traduce a un DTO `Sendable` dentro del handler, y `SessionStore` es el único escritor en el main actor.
- **Reconciliación atómica y acotada:** mientras reconcilia, el store rechaza comandos. Al agotar el timeout se degrada a estimación marcada "~" y descartable. Un gap que empieza hace más de 7 días no se consulta. El timeout debe cubrir con margen la duración real de la consulta en el dispositivo.
- **Sesión huérfana:** al arrancar con sesión activa persistida, se compara `now − startedAt` con el umbral. Por debajo se restaura; por encima se cierra recortada al último dato real, `recovered: true`, sin logros ni celebración. Hoy la regla solo corre al arrancar, no al volver de una suspensión larga; es una decisión abierta que el umbral medido debe tener en cuenta.
- **Presupuesto de energía:** conteo con `CMPedometer` continuo mientras hay sesión, con la consulta histórica reservada a la reconciliación ("no se combinan" significa no sumar fuentes); UI a 1 Hz redibujando solo la vista de sesión; métricas recalculadas con el dato del coprocesador, no con el tick.
- **Verificación:** `Scripts/verify-domain.sh` en verde es Definition of Done de toda historia que toque `Domain/`. Sin CI. Tests con Swift Testing; XCUITest diferido.
- **Logging:** `OSLog` con subsistema propio; nada de telemetría ni terceros.

## Cross-Story Dependencies

- **La 8.4 depende del Epic 1** (1.1–1.6 `done`) y del canal TestFlight de la 8.3, y **bloquea a los epics 2–7**. El Epic 8 sigue `in-progress` hasta que cierre.
- **Dependencia circular rota por diseño:** 1.5 y 1.6 usan el timeout y el umbral de huérfana con valores provisionales; la 8.4 los reemplaza.
- **Lo que la 8.4 decida alimenta decisiones abiertas del Epic 1:** si la consulta puede dar menos que lo visto, se revisa la regla de "sin dato" de la 1.5 (¿toda respuesta no nil cuenta como dato?). El umbral medido pesa en si la regla de huérfana y un tope de estimación deben aplicarse también al volver de una suspensión larga.
- **Trabajo pendiente del Epic 1 antes del Epic 2**, independiente del gate: refactor de `SessionStore` (clase dios de 750 líneas) y un chore de correcciones entre historias. Ninguno lo hace la 8.4.
- **La 7.2 recomprueba la batería** (≤ 5 % en 30 min, WalkTracker no destacado) con la Live Activity activa, porque la 8.4 no puede medirla.
- **La 8.7 es precondición permanente:** su script es DoD de toda historia posterior que toque el dominio.
