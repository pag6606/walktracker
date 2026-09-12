# Epic 8 Context: Fundaciones del sustrato SwiftUI

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Levantar el sustrato sobre el que se construye todo lo demás: un proyecto Xcode SwiftUI limpio con un único árbol de producto, la capa nativa ya escrita rescatada y troceada en adapters, y un arnés que demuestre que el dominio portado a Swift se comporta como el que ya está validado en producción. Es sustrato puro —no cubre ningún requisito funcional— pero corre **primero**: sin él cada epic posterior improvisa su propia versión de la verdad. Cierra con dos puertas de realidad en hardware: la app instalada de forma duradera y una caminata de 60 minutos que demuestre precisión y consumo aceptables. Este epic se reescribió el 2026-09-12 cuando el proyecto pivotó de Capacitor a SwiftUI nativo; todo lo que hable de WebView, plugins Capacitor o doble canal PWA está derogado y no vincula.

## Stories

- Story 8.5: Proyecto SwiftUI y limpieza del árbol
- Story 8.6: Extracción de la capa nativa desde `feature/flutter-substrate`
- Story 8.7: Sustrato de verificación del dominio
- Story 8.3: Distribución TestFlight con versionado SemVer
- Story 8.4: Gate del Success signal — batería y precisión en dispositivo físico

**Orden de ejecución: `8.5 → 8.6 → 8.7 → 8.3 → 8.4`.** Los números no son el orden: es el precio de no reciclar IDs. Las historias 8.1 y 8.2 están **anuladas** (montaje Capacitor y build local con `pnpm cap run ios`); sus ficheros se conservan con banner como registro histórico, no como contrato, y sus IDs no se reutilizan.

## Requirements & Constraints

- **Dominio preservado, no defectos preservados.** Los invariantes de la v3 (wall-clock, pausa explícita, sesión finalizada inmutable, zancada congelada al cierre, validación en frontera, pasos estimados siempre desglosados) siguen vinculando. Pero hay divergencias obligatorias respecto al código de referencia, y hay bugs de la v3 ya corregidos en la referencia que el port no debe reintroducir.
- **Arquitectura hexagonal verificable.** Dominio puro sin frameworks de plataforma; puertos definidos por el núcleo, adapters en el borde. La violación se detecta en build, no en revisión.
- **Licencias:** Apache-2.0/MIT en código; en fuentes de datos se admite CC-BY 4.0 con atribución visible. Copyleft fuerte sigue bloqueante. Sin dependencias de terceros.
- **Batería y precisión (criterio de éxito del producto):** una sesión de 60 minutos con conteo continuo en background, pantalla bloqueada y teléfono en el bolsillo, sin degradación notoria de batería y con pasos y distancia dentro del ±10 % de lo que reporta Apple Salud. En esa sesión los pasos estimados deben ser **cero**: los intervalos en background se reconstruyen por consulta al sistema, no por estimación.
- **Toolchain congelado durante el ciclo:** Xcode 26.6 / Swift 6.3.3 contra el SDK de iOS 26; el iPhone 14 de validación se queda en iOS 26 y no se actualiza. El simulador no sirve para nada que dependa del coprocesador: la validación es en dispositivo físico.
- **Fuera de scope:** App Store (TestFlight o build local bastan) y cualquier despliegue de la PWA como canal secundario.

## Technical Decisions

- **Sustrato y suelo:** app SwiftUI nativa, sin WebView ni capa híbrida. Deployment target **26.0**, y está **prohibido** cualquier `if #available` hacia versiones anteriores. Bundle id `com.walktracker.app`, inmutable.
- **Un solo árbol de producto:** el producto vive bajo `WalkTracker/`. Se eliminan los restos de los sustratos anteriores (proyecto Capacitor, bundle web, adapters JS, config de Capacitor, plugin local). Los ficheros JS del dominio y su suite de tests **se conservan congelados** como referencia de contraste, no como código vivo.
- **Tres targets:** app, `Shared` (contrato de la Live Activity y su formateo) y la Widget Extension. Usage strings de Motion, Salud y Ubicación, soporte declarado de Live Activities y entitlement de HealthKit.
- **Dirección de dependencias hacia dentro:** el dominio solo importa Foundation. No conoce SwiftUI, CoreMotion, HealthKit, ActivityKit, CoreLocation ni UIKit, y **nunca** llama al reloj del sistema ni a un generador aleatorio: llegan por puerto. Un import de plataforma en el dominio es fallo de build.
- **Concurrencia estricta completa (Swift 6):** los tipos del dominio son value types `Sendable`; un `@unchecked Sendable` exige justificación en el propio código. Los tipos de framework que no son `Sendable` se traducen a un DTO propio **en el borde, dentro del handler** que los recibe; pasarlos a través de una frontera de aislamiento es error de compilación, no observación de estilo.
- **Capa nativa por extracción, no por merge:** las ~446 líneas de Swift que ya implementan podómetro, háptica, escritura de workout y Live Activity viven en una rama que no es ancestro de HEAD. Entran por checkout de ese único fichero y se trocean en los adapters que les corresponden, cada uno detrás de su puerto; no queda lógica de sistema en el delegado de la app. Ese código está escrito pero **nunca se ejecutó en dispositivo**: verificarlo en el iPhone es parte del trabajo, y lo que no funcione se registra como coste adicional de los epics de Salud y Live Activity.
- **Prueba de equivalencia en tres categorías:** la suite JS existente (281 aserciones ejecutadas) se reparte de forma que cada aserción cae en exactamente una — vectores de datos que ejecutan **ambos runtimes**, escenarios portados a mano a Swift Testing, y excluidos que quedan **declarados muertos, no olvidados**. Los motores de meta y de logros no tienen ninguna cobertura previa: sus vectores se **escriben**, no se extraen.
- **Divergencias declaradas:** solo dos conductas deben diferir de la referencia —hora local en lugar de UTC, y categoría de clima por código WMO en lugar de regex sobre texto localizado—, ambas decisiones de plataforma. Las otras dos que había eran defectos y ya se corrigieron en la referencia.
- **Sin CI:** el mecanismo de cumplimiento es un script local que corre ambos runtimes contra los mismos vectores. Su paso en verde es Definition of Done de toda historia que toque el dominio.
- **Catálogo en datos, evaluación en Swift:** el catálogo de logros es un fichero de datos con esquema publicado (clave estable, métrica de un enum cerrado, umbral y comparación). El evaluador es un `switch` exhaustivo: una métrica nueva sin rama no compila. La app **valida el catálogo al arrancar y falla ruidosamente** si no cuadra; nunca degrada.
- **Atribución:** la fuente de clima exige atribución visible en Ajustes → Acerca de.

## Cross-Story Dependencies

- **El epic entero bloquea a los demás.** Ningún otro epic puede empezar sin el proyecto, el árbol limpio y el arnés de verificación.
- `8.6` y `8.3` requieren el proyecto y los targets de `8.5`. `8.3` además requiere cuenta Apple Developer de pago activa.
- `8.7` es precondición permanente: su script en verde es DoD de toda historia posterior que toque el dominio (epics de sesión, metas/logros, calibración e historial).
- `8.6` adelanta trabajo de los epics de feedback háptico, Apple Salud y Live Activity; si el código extraído no funciona en dispositivo, esos epics recuperan su coste completo.
- `8.4` es el gate final y **produce dato que otros consumen**: de esa medición salen el timeout de reconciliación y el umbral de sesión huérfana, hoy diferidos a un fichero de constantes y necesarios en el epic de sesión. Si el gate falla algún criterio, se revisa antes de seguir construyendo.
- El wake lock que la historia anulada 8.2 gobernaba **no se pierde**: sobrevive como puerto propio dentro del epic de sesión.
