# Epic 2 Context: Clima, motivación y calibración

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Cada caminata de Paul queda asociada al clima en que la hizo y arranca con una frase motivacional. Además, Paul puede recalibrar su zancada sin tocar el historial ya cerrado. Este epic se apoya en el sustrato SwiftUI y en la sesión nativa de los Epics 8 y 1, los dos terminados. Trae tres cosas que la app aún no tiene: la **primera llamada de red** del producto (Open-Meteo), la **primera degradación no bloqueante** y la **primera persistencia de ajustes**. Muchos criterios de `epics.md` citan fuentes de Capacitor/PWA, y en ese caso mandan `ARCHITECTURE-SPINE.md` y `DEROGACIONES.md` (carpeta `architecture-walktracker-2026-09-12`):
- **Derogados:** AR-1 (la corrección WMO→`rain` ya no es una excepción de portación: es una divergencia obligatoria de AD-6), AR-10 (contratos de puerto; ahora gobierna AD-10), UX-DR1 (tokens Volt → colores del sistema, AD-13) y la parte CSS de UX-DR2 (`px`, `clamp()` → Dynamic Type).
- **Parciales:** UX-DR5 y UX-DR7. La navegación ⚙📋🏆 de los flujos 1 y 5 pasa a ser el `TabView` de AD-14.
- **Traducido:** UX-DR6. `role=dialog`, `aria-modal` y `focus ring` no aplican.
- **AR-12 sigue vigente,** pero sus "AD-14/AD-17/AD-18" son numeración de la v3 (timeout 3 s, redondeo de coordenadas a 2 decimales, `quotes.json`). No tienen nada que ver con los AD-14/17/18 del spine actual.
- **NFR-7 enmendado:** Open-Meteo es CC-BY 4.0, no MIT (AD-24).

## Stories

- Story 2.1: Clima snapshot al inicio de sesión (Open-Meteo)
- Story 2.2: Frase motivacional al iniciar sesión
- Story 2.3: Recalibración de zancada en Ajustes

## Requirements & Constraints

- **Clima**
  - **Snapshot:** `{tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt}`. Se congela al iniciar la sesión y no se refresca durante ella.
  - **Degradación:** sin red, sin permiso de ubicación o con timeout, la sesión inicia **sin clima** (`weather = nil`) y nunca bloquea ni se retrasa. En la v3 la sesión arrancaba primero y el clima se adjuntaba al llegar.
  - **Permiso denegado:** no se vuelve a pedir en cada sesión.
  - **Timeout:** 3 s en Open-Meteo. La ubicación de la v3 era de una sola lectura, baja precisión, 3 s y `maximumAge` 5 min.
- **Lluvia:** se detecta por **código WMO** (51–67, 80–82, 95–99) → categoría interna `rain`, nunca por texto localizado. Es una divergencia declarada: el vector lleva el valor corregido y `domain.js` falla a propósito. El snapshot debe conservar el código WMO, porque `evaluateAchievements.json` ya modela `weather` como `{wmoCode, tempC}`.
- **Privacidad y red**
  - El clima es la **única** llamada de red permitida. Sin backend, sin terceros y sin telemetría.
  - Las coordenadas salen redondeadas a **2 decimales**.
- **Frase**
  - Se elige al azar del banco de 100 (`quotes.json`, empaquetado en el bundle y sin cambios de contenido), excluyendo `recentQuoteIds` (las últimas 20). Si todas quedan excluidas, se ignora el filtro. Con el banco vacío no hay frase.
  - Resultado: 20 sesiones seguidas sin repetir.
  - `recentQuoteIds` se actualiza en cada selección, con tope de 20, y persiste en la configuración.
  - El `quoteId` mostrado se guarda en la sesión.
- **Zancada**
  - `strideM` es la única medida cruda editable. Debe ser > 0 y finita, y se valida en la frontera. Con el campo vacío, un valor ≤ 0, NaN o texto no numérico se muestra un mensaje y no se persiste nada.
  - Por defecto vale 0,655 m (`formulas.json`).
  - La nueva zancada aplica desde la **siguiente** sesión. Las sesiones cerradas conservan congelada la suya.
- **Licencia:** Open-Meteo exige atribución visible en Ajustes → Acerca de. Ningún criterio de `epics.md` la pide: hay que asignarla (2.1) o registrarla en `deferred-work.md`.

## Technical Decisions

- **Puertos (AD-10, conjunto cerrado de 11):** este epic crea `LocationPort`, `WeatherPort` y `RandomPort`.
  - **`LocationPort`:** independiente de `WeatherPort`. Es **quien redondea** a 2 decimales antes de entregar las coordenadas: es el único punto donde la privacidad es verificable.
  - **`RandomPort`:** la selección de frase no llama a `random()` en el dominio.
  - **`capturedAt`:** llega por `ClockPort`, nunca con `Date()` en `Domain/`.
  - **Adapters:** van en `Adapters/Location` y `Adapters/Weather`, con dobles `XxxStub`. CoreLocation queda fuera de `UI/` y de `Domain/`, y `check-project-shape.sh` lo hace cumplir.
  - **Open-Meteo:** se consume directo con HTTPS del sistema, sin dependencias (Stack: ninguna de terceros). WeatherKit queda diferido; sería un cambio de adapter.
- **Permisos y degradación (AD-11):** el adapter posee el estado del permiso y lo expone como `status`. Toda petición va precedida de una pre-pantalla. "Ubicación denegada" y "Red no disponible" significan sesión sin clima, nunca bloqueo. La retro del Epic 1 (S6) encontró dos huecos que este epic debe reconciliar:
  - `DegradationPolicy` no existe todavía.
  - `PermissionStatus.unavailable` hoy bloquea igual que el permiso denegado de Motion. La ubicación **no** debe heredar ese bloqueo.
- **Escritor único (AD-7/AD-16):** `weather` y `quoteId` entran en el agregado solo a través de `SessionStore`, que es el único escritor de la sesión y de `activeSession.json`. Un clima que llega después del inicio lo escribe el store, no el adapter.
- **Snapshot de sesión:** el snapshot de la sesión viva aún no escribe `weather` ni `quoteId`. Hay que añadirlos para que la recuperación tras un force-quit los conserve. El fichero lleva `schemaVersion`; los milisegundos se convierten a segundos en el adapter de persistencia.
- **Ajustes (AD-9/AD-16):** `strideM` y `recentQuoteIds` viven en `settings.json`, cuyo único escritor es `SettingsStore`. Ni `settings.json` ni `SettingsStore` existen hoy: `StoragePort` solo cubre `activeSession.json` ("los ajustes llegan con la 5.1"), y la sección 9 de `check-project-shape.sh` limita `StoragePort` a `SessionStore`. Ampliar el puerto implica declarar su dueño en esa regla, no saltársela. La zancada que hoy recibe `SessionStore` es la constante fija de `formulas.json`; la 2.3 la sustituye por la configurada, leída al iniciar.
- **Verificación (AD-6):**
  - **Motivación:** `selectQuote.json` y `updateRecentIds.json` ya existen y en Swift figuran como *pending*. La historia que porte `MotivationEngine` los registra, y `Scripts/verify-domain.sh` en verde es su DoD. Las conductas aleatorias de la v3 están excluidas de los vectores, así que se prueban con `RandomPort` determinista.
  - **Zancada:** los vectores `recalibrate` de la v3 son de vueltas v1 y están excluidos, de modo que la validación de `strideM` se cubre con tests propios.
- **Errores y textos:** los errores del dominio son tipados y tienen una única traducción a mensaje de usuario; nunca se muestra un error crudo de red o de CoreLocation. Los textos van al String Catalog. `condition` se muestra en español a partir del código WMO; la tabla de `climate.js` sirve de referencia.
- **Entrega de la primera historia con red (2.1):**
  - **Privacidad:** `PrivacyInfo.xcprivacy` declara hoy cero datos recogidos, bajo el supuesto (anotado en el propio fichero) de que las coordenadas redondeadas se envían sin guardarse ni vincularse. La 2.1 confirma o corrige ese supuesto.
  - **Cifrado:** revisar `ITSAppUsesNonExemptEncryption = NO`, que solo se sostiene con HTTPS del sistema, y la nota del README que lo aplaza a esta historia.
  - **Release:** cerrar el diferido que pide a `release-testflight.sh` comprobar que el manifiesto está dentro del `.app` y el flag de cifrado.
  - `NSLocationWhenInUseUsageDescription` ya está en `Info.plist`.

## UX & Interaction Patterns

- **El vocabulario visual está en código, y es la fuente:** `WalkTracker/UI/Style/DesignTokens.swift` (chore de tokens, 2026-09-18). Espaciado (`Spacing`, la escala 4/8/12/16/24 de UX-DR3), margen y objetivo táctil de 44 pt (`LayoutMetrics`), radio de tarjeta (`Radius.card`, 20), relleno de tarjeta (`Surface`, 16/12), los dos roles tipográficos que el sistema no nombra (`Typography`) y los dos colores propios (`Colors.accent`, `Colors.estimated`), como colorset con variante clara y oscura y contraste medido. La pantalla de Ajustes de la 2.3 y el campo de zancada toman de ahí el margen, el radio y las 44 pt sin decidir nada nuevo. **Ninguna vista los reteclea:** la sección 12 de `Scripts/check-project-shape.sh` falla si dentro de `WalkTracker/UI/` aparece un lado de marco numérico (`minHeight: 44`, `.frame(height: 44)`), un radio de esquina numérico (`cornerRadius: 16`, `.cornerRadius(16)`), un color en hexadecimal o por componentes, `.orange`, o un peldaño de la escala —4, 8, 12, 16, 24— escrito a mano en `spacing:`, `minLength:` o `.padding(…)`. Lo que la spec decide no tokenizar (`spacing: 0`, `spacing: 2`, `.padding(.top, 48)`) sigue pasando. La misma sección comprueba que `project.yml` mantenga `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`: sin esa key el acento vuelve al azul del sistema.
- **Tarjeta de clima**
  - Va en la vista de sesión, bajo las métricas, y es estática durante la sesión.
  - Muestra la temperatura grande y la condición, con humedad, UV y viento en una fila secundaria.
  - Sin clima degrada con calma ("Sin clima"): nunca un error ni un cero, siguiendo "celebrar, nunca culpar" (AD-22).
  - El icono de condición es un SF Symbol: el emoji queda reservado a las insignias de logro.
  - Ningún criterio pide la vista previa de clima en Inicio que aparece en el flujo v3.
- **Frase motivacional**
  - Se presenta como modal nativo sobre una sesión que **ya está corriendo**, con la frase en jerarquía dominante y Dynamic Type sin recortes.
  - Se cierra sola a los 3–4 s o con un tap en cualquier punto. No lleva botón de cerrar.
  - VoiceOver la anuncia como contenido modal. Con Reduce Motion aparece sin fundido.
  - Colores del sistema; no el fondo acento a pantalla completa de la v3.
- **Zancada en Ajustes**
  - Está en la pestaña Ajustes (AD-14). Se edita en metros con coma decimal en la UI y se guarda con validación.
  - El error sale en un mensaje en línea, sin culpar. Objetivos táctiles ≥ 44 pt.
  - Flujo 5: editar → guardar → la próxima sesión la usa, y el historial no cambia.

## Cross-Story Dependencies

- **2.1 ↔ 2.2:** las dos amplían el agregado `Session` y el snapshot de `SessionStore` (`weather`, `quoteId`) y tocan el flujo de inicio. Según la lección L3 de la retro del Epic 1, la spec lista en su Code Map los campos compartidos del store y sus invariantes: recuperación, reconciliación, sesión huérfana y bloqueo de comandos mientras `reconciling`.
- **2.2 ↔ 2.3:** las dos necesitan la persistencia de ajustes. La primera que llegue crea `settings.json` y su dueño; la otra lo reutiliza.
- **Epic 3:** `rain_walker`, `hot_walker` y `cold_walker` leen `session.weather` (código WMO y `tempC`); con `weather = nil` no se desbloquean. `WeatherCategory.rain` ya existe en `Domain/Achievements`. La meta semanal (3.1) comparte `settings.json` y la pantalla Ajustes.
- **Epic 5:** `sessions.json` (5.1) y el export (5.3) deben llevar `weather` y `quoteId`, y la 5.1 hereda el `StoragePort` de ajustes que cree este epic.
- **Proceso (lección L2):** todo traspaso "hasta la historia X" se registra en `deferred-work.md` con esa historia como destino. Por ejemplo, la atribución de Open-Meteo si no la cierra la 2.1, o lo que dependa de la 5.1.
