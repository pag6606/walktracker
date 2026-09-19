# Epic 2 Context: Clima, motivación y calibración

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Cada caminata de Paul queda asociada al clima en que la hizo y arranca con una frase motivacional, y Paul puede recalibrar su zancada sin tocar el historial ya cerrado. El epic se apoya en el sustrato SwiftUI y en la sesión nativa (Epics 8 y 1, terminados) y trae tres primeras veces del producto: la **primera llamada de red** (Open-Meteo), la **primera degradación no bloqueante** y la **primera persistencia de ajustes**. Aviso de lectura: muchos criterios de aceptación de `epics.md` citan fuentes de la etapa Capacitor/PWA. Donde choquen, mandan `ARCHITECTURE-SPINE.md` y `DEROGACIONES.md` (carpeta `architecture-walktracker-2026-09-12`):

- **Derogados:** **AR-1** — la corrección WMO→`rain` ya no es una excepción de portación sino una divergencia obligatoria del dominio Swift (**AD-6**); **AR-10**, los contratos de puerto de la etapa Capacitor, que ahora gobierna **AD-10**; **UX-DR1**, los design tokens Volt → colores del sistema (**AD-13**), con la excepción declarada de más abajo; y la parte CSS de **UX-DR2** (`px`, `clamp()` → Dynamic Type).
- **Parciales:** **UX-DR5** y **UX-DR7**. La navegación ⚙📋🏆 de los flujos 1 y 5 pasa a ser el `TabView` de cuatro pestañas de **AD-14**; sobrevive el inventario de superficies y estados.
- **Traducido:** **UX-DR6**. La accesibilidad sigue vinculante en su intención (WCAG AA, VoiceOver, Dynamic Type sin recortes, Reduce Motion), pero `role=dialog`, `aria-modal` y `focus ring` son mecanismos web y no aplican.
- **Enmendado:** **NFR-7** — Open-Meteo es CC-BY 4.0, no MIT (**AD-24**); la restricción de licencias admite CC-BY en fuentes de datos, nunca en código.
- **AR-12 sigue vigente,** pero sus "AD-14/AD-17/AD-18" son numeración de la **v3** (timeout 3 s, coordenadas a 2 decimales, `quotes.json`) y no tienen nada que ver con los AD-14/17/18 del spine actual.

## Stories

- Story 2.1: Clima snapshot al inicio de sesión (Open-Meteo)
- Story 2.2: Frase motivacional al iniciar sesión
- Story 2.3: Recalibración de zancada en Ajustes

## Requirements & Constraints

**Clima**
- Snapshot `{tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt}`, **congelado al iniciar** la sesión y no refrescado durante ella.
- Sin red, sin permiso de ubicación o con timeout, la sesión inicia **sin clima** (`weather = nil`): nunca bloquea ni retrasa el arranque. Con el permiso denegado no se vuelve a pedir en cada sesión.
- Timeout de Open-Meteo: **3 s**. La ubicación es una lectura única, de baja precisión, con edad máxima aceptable de unos minutos.
- La lluvia se detecta por **código WMO** (51–67, 80–82, 95–99) → categoría interna `rain`, nunca por regex sobre texto localizado. Es una divergencia declarada: el vector lleva el valor corregido y el runtime JS de referencia falla ese vector a propósito. El snapshot debe **conservar el código WMO**, porque `evaluateAchievements.json` ya modela `weather` como `{wmoCode, tempC}`.

**Privacidad y red**
- El clima es la **única** llamada de red del producto: sin backend, sin terceros, sin telemetría ni crash reporting.
- Las coordenadas salen redondeadas a **2 decimales**.
- Open-Meteo exige **atribución visible** en Ajustes → Acerca de. Ningún criterio de aceptación la pide: hay que asignarla a una historia (2.1) o registrarla en `deferred-work.md` con destino explícito (**NFR-7**, **AD-24**).

**Frase**
- Selección al azar del banco de 100 (`quotes.json`, asset del bundle, contenido sin cambios) excluyendo las **últimas 20** mostradas; si todas quedan excluidas, se ignora el filtro. Con el banco vacío no hay frase.
- Resultado observable: 20 sesiones seguidas sin repetición. La lista de recientes se actualiza en cada selección, con tope de 20, y **persiste** en la configuración.
- El identificador de la frase mostrada se guarda en la sesión.

**Zancada**
- `strideM` es la única medida cruda editable: debe ser **> 0 y finita**, validada en la frontera. Campo vacío, valor ≤ 0, NaN o texto no numérico → mensaje de error y **nada se persiste**.
- Sin valor configurado, el default es **0,655 m**, y vive como constante en `formulas.json`, no en el código.
- La nueva zancada aplica desde la **siguiente** sesión; las sesiones cerradas conservan la suya congelada.

## Technical Decisions

- **Puertos (AD-10, conjunto cerrado de 11).** Este epic estrena `LocationPort`, `WeatherPort` y `RandomPort`. `LocationPort` es independiente de `WeatherPort` y es **quien redondea** a 2 decimales antes de entregar las coordenadas: el único punto donde la restricción de privacidad es verificable. `RandomPort` existe para que el motor de motivación no llame a un generador aleatorio dentro del dominio, y `capturedAt` llega por `ClockPort`, nunca con `Date()` en `Domain/` (**AD-3**, **AD-19**).
- **Adapters.** `Adapters/Location` y `Adapters/Weather`, cada uno con su doble `XxxStub`. Ninguna vista importa un framework de sistema: CoreLocation queda fuera de `UI/` y de `Domain/`, y `Scripts/check-project-shape.sh` lo hace cumplir (**AD-10**). Open-Meteo se consume directo por HTTPS del sistema, **sin dependencias de terceros**. WeatherKit está diferido y sería un cambio de adapter.
- **Permisos y degradación (AD-11).** El adapter posee el estado de su permiso y lo expone por el puerto como `status`; toda petición va precedida de pre-pantalla explicativa. La respuesta a "falta esta capacidad" vive en **una única** `DegradationPolicy`: "ubicación denegada" y "red no disponible" significan sesión sin clima, nunca bloqueo. La retro del Epic 1 (**S6**) dejó **dos huecos concretos** que este epic tiene que reconciliar, y que no quedan resueltos porque el texto de arriba los resuma:
  - **`DegradationPolicy` no existe todavía** en el árbol Swift: hoy cada degradación se decide en su sitio.
  - **`PermissionStatus.unavailable` hoy bloquea igual** que el permiso denegado de Motion. La ubicación **no** debe heredar ese bloqueo.

  Y conviene leerlo junto a **AD-5**, la otra política de fallo del producto: un catálogo de logros inválido **mata el arranque**, mientras que un banco de frases ausente o inválido **degrada** (decisión de Paul, 2026-09-19). Las dos conviven a propósito.
- **Escritor único (AD-7/AD-16).** `weather` y el identificador de frase entran en el agregado solo a través de `SessionStore`, único escritor de la sesión y de `activeSession.json` (**AD-7**). Un clima que llegue después del inicio lo escribe el store, no el adapter. El snapshot de la sesión viva debe incluirlos para que la recuperación tras force-quit los conserve; lleva `schemaVersion`, y los milisegundos del modelo heredado se convierten a segundos en el adapter de persistencia (**AD-9**; el dominio trabaja en segundos).
- **Ajustes (AD-9/AD-16).** `strideM` y `recentQuoteIds` viven en `settings.json`, cuyo **único dueño** es `SettingsStore`. Ni el fichero ni el store existían al compilar este contexto: `StoragePort` cubría solo `activeSession.json` ("los ajustes llegan con la 5.1"), y la sección 9 de `Scripts/check-project-shape.sh` lo limitaba a `SessionStore`. Ampliar el puerto implica declarar el nuevo dueño en esa regla, no saltársela. La zancada que hoy consume la sesión es la constante fija; la 2.3 la sustituye por la configurada, leída al iniciar.
- **Verificación (AD-6).** Los vectores `selectQuote.json` y `updateRecentIds.json` ya existen y figuran como pendientes en Swift: la historia que porte el motor de motivación los registra, y `Scripts/verify-domain.sh` en verde es su Definition of Done. Las conductas aleatorias están excluidas de los vectores y se prueban con un `RandomPort` determinista. Los vectores `recalibrate` heredados pertenecen a la agregada v1 eliminada y están declarados muertos: la validación de `strideM` se cubre con tests propios.
- **Errores y textos.** El dominio lanza errores tipados con una única traducción a mensaje de usuario; nunca se muestra un error crudo de red o de CoreLocation. Todos los textos van al String Catalog en su capitalización final. La condición se muestra en español derivada del código WMO; la tabla de `climate.js` sirve de referencia.
- **Primera historia con red.** Conviene cerrar con ella la declaración de privacidad del bundle (hoy declara cero datos recogidos bajo el supuesto de coordenadas enviadas sin guardar ni vincular), la revisión del flag de cifrado no exento —que solo se sostiene usando HTTPS del sistema— y la comprobación del manifiesto dentro del `.app` en `release-testflight.sh`, que es un diferido abierto. `NSLocationWhenInUseUsageDescription` ya está en `Info.plist`.

## UX & Interaction Patterns

- **El vocabulario visual está en código y es la fuente:** `WalkTracker/UI/Style/DesignTokens.swift` (chore de tokens, 2026-09-18). De ahí salen el espaciado (`Spacing`, la escala 4/8/12/16/24 de **UX-DR3**), el margen y el objetivo táctil de 44 pt (`LayoutMetrics`), el radio (`Radius.card`, 20) y el relleno de tarjeta (`Surface`, 16/12), los dos roles tipográficos que el sistema no nombra (`Typography`) y los **dos colores propios del producto** (`Colors.accent`, `Colors.estimated`). Ninguna vista los reteclea: la sección 12 de `Scripts/check-project-shape.sh` falla si dentro de `WalkTracker/UI/` aparece un lado de marco numérico, un radio de esquina numérico, un color en hexadecimal o por componentes, `.orange`, o un peldaño de la escala —4, 8, 12, 16, 24— escrito a mano en `spacing:`, `minLength:` o `.padding(…)`. Lo que la spec del chore decidió no tokenizar (`spacing: 0`, `spacing: 2`, `.padding(.top, 48)`) sigue pasando, y la misma sección comprueba que `project.yml` mantenga `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`. La pantalla de Ajustes de la 2.3 y el campo de zancada toman de ahí margen, radio y 44 pt sin decidir nada nuevo.
- **Excepción declarada a los tokens (vigente desde 2026-09-18).** La paleta Volt sigue derogada y ninguna vista cablea un hexadecimal; la excepción son exactamente **dos colorsets** del catálogo de assets, cada uno **con variante clara y oscura y contraste medido** contra el fondo real sobre el que se pinta: `AccentColor` (oliva en claro 5,62:1, lima en oscuro 17,87:1 — el acento de la app, que sin él salía azul del sistema por omisión) y `EstimatedSteps` (5,71:1 en claro, naranja del sistema en oscuro — corrige un incumplimiento WCAG AA vivo, porque el `.orange` del sistema daba 2,20:1 sobre blanco). Las vistas los referencian por nombre; la suite recalcula el contraste en cada ejecución y falla si cae de 4,5:1; y el script comprueba además que el proyecto conserve la key del acento global, sin la cual el acento vuelve al azul. El resto de la paleta sigue siendo del sistema, referenciada por nombre.
- **Tarjeta de clima.** Va en la vista de sesión, bajo las métricas, y es estática durante toda la sesión: temperatura grande y condición, con humedad, UV y viento en una fila secundaria. Sin clima degrada con calma ("Sin clima"), nunca con un error ni un cero — "celebrar, nunca culpar" (**AD-22**) — la regla es que una magnitud ausente se representa como tal, jamás como `0`. El icono de condición es un **SF Symbol**: el emoji queda reservado a las insignias de logro. Ningún criterio pide la vista previa de clima en Inicio que aparecía en el flujo v3.
- **Frase motivacional.** Modal nativo sobre una sesión **que ya está corriendo**, con la frase en jerarquía dominante y Dynamic Type sin recortes. Se cierra sola a los 3–4 s o con un tap en cualquier punto; sin botón de cerrar. VoiceOver la anuncia como contenido modal y con Reduce Motion aparece sin fundido. Colores del sistema: no el fondo acento a pantalla completa de la v3.
- **Zancada en Ajustes.** En la pestaña Ajustes (**AD-14**). Se edita en metros con coma decimal en la UI y se guarda con validación; el error sale en un mensaje en línea, sin culpar. Objetivos táctiles ≥ 44 pt. El flujo 5 es editar → guardar → la próxima sesión la usa → el historial no cambia.

## Cross-Story Dependencies

- **2.1 ↔ 2.2:** ambas amplían el agregado `Session` y el snapshot de `SessionStore` (`weather`, identificador de frase) y tocan el flujo de inicio. Según la **lección L3** de la retro del Epic 1, la spec de cada una lista en su Code Map los campos compartidos del store y sus invariantes: recuperación, reconciliación, sesión huérfana y bloqueo de comandos mientras se reconcilia.
- **2.2 ↔ 2.3:** ambas necesitan la persistencia de ajustes. La primera que llegue crea `settings.json` y su dueño; la otra lo reutiliza. De ahí cuelga también recordar entre lanzamientos el "Ahora no" de la pre-pantalla de ubicación y ofrecer el permiso de clima desde Ajustes.
- **Epic 3:** `rain_walker`, `hot_walker` y `cold_walker` leen el clima de la sesión (código WMO y `tempC`); con `weather = nil` no se desbloquean. Queda pendiente unificar el enum de lluvia del dominio de clima con el del catálogo de logros. La meta semanal comparte `settings.json` y la pantalla de Ajustes.
- **Epic 5:** `sessions.json` (5.1) y el export (5.3) deben llevar `weather` y el identificador de frase, y heredan el puerto de almacenamiento de ajustes que cree este epic.
- **Proceso (lección L2):** todo traspaso "hasta la historia X" se registra en `deferred-work.md` con esa historia como destino — por ejemplo la atribución de Open-Meteo si no la cierra la 2.1, o lo que dependa de la 5.1.
