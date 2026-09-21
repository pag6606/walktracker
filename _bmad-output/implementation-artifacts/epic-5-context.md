# Epic 5 Context: Historial, persistencia y respaldos

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Las caminatas de Paul dejan de vivir solo en la pantalla que las terminó: se guardan de forma garantizada en el sandbox de la app, se consultan como historial con totales y tendencia, se exportan como respaldo voluntario y se borran una a una cuando sobran. **La historia 5.1 se ha adelantado** (decisión de Paul, 2026-09-21) y llega **antes** que los epics 3 y 4, no después: hoy `SessionStore.confirmFinish()` termina limpiando el snapshot y **no guarda nada** —la caminata cerrada solo existe en un `@State` de la vista de sesión mientras se mira el resumen—, así que sin la 5.1 no hay suma semanal para el anillo de la 3.1 ni acumulados ni rachas para la 3.2. El resto del epic (5.2–5.4) sigue en su sitio. Aviso de lectura: varios criterios de `epics.md` citan fuentes de la etapa PWA/Capacitor; donde choquen, mandan `ARCHITECTURE-SPINE.md` y `DEROGACIONES.md` (carpeta `architecture-walktracker-2026-09-12`):

- **Derogados:** **UX-DR7** en su prohibición de swipe-to-delete — en iOS el swipe **es** el gesto y el icono de papelera embebido en la fila es el antipatrón (**AD-20**); **UX-DR1** (tokens Volt) y la parte CSS de **UX-DR2/UX-DR3** (`px`, `clamp()`, tamaños fijos) → colores del sistema por su rol y Dynamic Type (**AD-13**).
- **Parcial:** **UX-DR5** — Historial es una **pestaña** del `TabView` de cuatro (**AD-14**), no un icono ⚙📋🏆 arriba a la derecha; sobreviven el inventario de superficies y de estados (empty history, recuperación). Además, el estado **"backup overdue"** y el aviso de "respaldo > 30 días" **se retiran del producto**: eran mitigación de la evicción de la PWA y el storage garantizado los deja sin razón de ser.
- **Traducido:** **UX-DR6** — la accesibilidad sigue vinculante en su intención (WCAG AA, VoiceOver, Dynamic Type sin recortes, Reduce Motion); `aria-*` y `role=` son mecanismos web y en SwiftUI son `.accessibilityLabel` y equivalentes.

## Stories

- Story 5.1: Persistencia garantizada en sandbox (StoragePort)
- Story 5.2: Historial — lista descendente + totales semana/mes + tendencia
- Story 5.3: Export CSV/JSON + re-import (share sheet)
- Story 5.4: Eliminar sesiones individuales

## Requirements & Constraints

**Persistencia (5.1) — no se parte de cero**
- Lo que falta son **dos ficheros con su dueño**, no el mecanismo: `sessions.json` (historial de sesiones finalizadas, dueño `HistoryStore`) y `achievements.json` (estado `{key, unlockedAt, progress}`, dueño `AchievementsStore`). Los otros dos —`activeSession.json` (dueño `SessionStore`) y `settings.json` (dueño `SettingsStore`)— ya existen, con su adapter, su esquema y sus tests.
- **`achievements.json` es el store de desbloqueos, no el catálogo.** El catálogo de los 14 logros es **contenido congelado** que vive en `Resources/achievements.json` y que un gate compara campo a campo contra la referencia de la v3. Son dos ficheros distintos con nombres parecidos: confundirlos rompe el gate o pisa contenido congelado.
- Una sesión finalizada es un **registro inmutable**: `{id, startedAt, endedAt, stepsMeasured, stepsEstimated, strideM, distanceM, durationS, pausesS, paceSecPerKm|null, cadenceSpm, weather|null, quoteId, source}`. `source` es `"ios"` para todo lo que produce la v1 (la importación del historial de la PWA está retirada, arranque limpio). La zancada queda **congelada** en la fila: recalibrar nunca reescribe historial.
- Criterios de aceptación reales: reinicio del iPhone → historial, logros y config íntegros; force-quit con sesión viva → recuperación silenciosa desde el snapshot, que es lo que ya funciona.

**Historial (5.2)**
- Lista **descendente** (lo más reciente primero) con fecha, distancia, duración y ritmo; las sesiones con pasos estimados se marcan con **"~"**.
- Totales de **semana y mes** que cuadran exactamente con la suma de las sesiones, y un **gráfico de tendencia** simple de la distancia en el tiempo.
- Sin sesiones: empty state "Aún no hay sesiones registradas", y **sin gráfico**. Una magnitud ausente se representa como ausente, nunca como `0` (AD-22).

**Export e import (5.3)**
- Export por el **share sheet** de iOS, en **JSON y CSV**. El **import acepta solo JSON**: el CSV es formato de salida hacia hojas de cálculo, no de entrada.
- El JSON de export **reutiliza la serialización de `sessions.json`** — no hay un segundo serializador que pueda divergir en silencio. El **CSV sí es un segundo serializador**, y por eso su contrato está fijado fuera de la historia: columnas en este orden `fecha;hora;duracion_s;pasos_medidos;pasos_estimados;distancia_m;ritmo_s_km;fuente`, **separador de campo `;` y decimal `,`** (la UI está en español y la coma decimal rompe el CSV separado por comas), cabecera siempre presente, UTF-8 con BOM.
- Prueba de respaldo/restauración: exportar JSON → borrar → importar → historial íntegro. Importar sobre datos existentes **no puede romper** los registros que ya están. Las reglas de importación archivadas de la v3 son la referencia disponible para el merge —idempotencia por `id`, registros con `distanceM ≤ 0` o `strideM ≤ 0` excluidos—, pero la decisión de la política de merge es de la historia.

**Borrado (5.4)**
- El gesto es el **swipe nativo** con acción `.destructive` y **confirmación explícita**; objetivo táctil **≥ 44 pt, verificable**. El icono de papelera dentro de la fila que pedían los mockups está **prohibido** (era su defecto B-11: 28×28 px, sin confirmación y sustituyendo el gesto nativo).
- Borrar quita la sesión de la lista, de los totales de semana/mes, del anillo semanal y de los **acumulados de los logros aún no desbloqueados**. Un logro **ya desbloqueado nunca se revoca**.

## Technical Decisions

- **El mecanismo de disco ya está resuelto y se hereda, no se reinventa.** `JSONFileStore` absorbió la escritura atómica (temporal en el mismo directorio + `rename`), el apartado de ficheros ilegibles (`<base>.corrupt.<marca>.json`, con `RENAME_EXCL` para no destruir un apartado anterior) y la derivación de nombres; `FileStorageAdapter` es un **compositor puro** que solo reparte a los adapters por fichero. Añadir `sessions.json` y `achievements.json` es añadir dos adapters con su esquema y enchufarlos ahí.
- **Dos reglas heredadas que no se pueden aflojar.** Un fichero ilegible **se aparta, no se destruye**; y **`nil` no es un error**: `nil` significa "no hay nada que perder" y deja escribir, mientras que un error de lectura significa "hay algo que no se pudo leer" y **no deja escribir**. Lo fijó el chore B-1 tras un defecto de pérdida de datos confirmado. Además, un `schemaVersion` **mayor** que el conocido no es corrupción: se deja intacto para que quien lo entienda lo recupere entero.
- **Un fichero, un dueño, y el gate lo sabe (AD-16).** `StoragePort` es **un** puerto (AD-10 fija un conjunto cerrado de 11) con hoy **seis métodos sobre dos ficheros**. La **sección 9 de `Scripts/check-project-shape.sh`** comprueba qué fichero de `Application/` puede llamar a qué método: ampliar el puerto obliga a **declarar el nuevo dueño en esa regla**, no a saltársela. Quien no es dueño lee a través del dueño, nunca del disco.
- **Esquemas y unidades.** `activeSession.json` va por la versión **3** y `settings.json` por la **1**; los ficheros nuevos empiezan en la suya. Un campo ausente se lee con su valor por omisión, así que añadir campos no obliga a subir versión. El dominio trabaja en **segundos y metros**; los **milisegundos** del contrato de datos del snapshot se convierten **en el adapter de persistencia, nunca dentro del dominio**. Timestamps ISO-8601, distancia en metros (2 dp), pasos enteros, cadencia con 1 decimal.
- **Un solo calendario (AD-19).** Los totales de semana y mes del historial usan el **mismo `AppCalendar`** expuesto por `ClockPort` (ISO-8601, lunes como primer día, zona del dispositivo) que el anillo de meta. `Calendar.current` está prohibido y el gate lo comprueba: el anillo y el historial no pueden dar dos números distintos para la misma semana.
- **Un solo disparador de logros (AD-17).** Los logros se evalúan **al finalizar la sesión, dentro de la misma transacción que la persiste** — nunca al abrir el historial, ni al pintar una lista, ni al borrar. Borrar recalcula totales y el progreso de los **no** desbloqueados; un `unlockedAt` nunca vuelve a nulo.
- **El gráfico de tendencia es la tercera pieza dibujada a mano** que AD-13 autoriza (con el anillo de meta y la insignia de logro). Un `Canvas` **no trae etiqueta de accesibilidad**: la lleva explícita, diciendo la magnitud completa. La sección 12 del gate falla si una vista de `UI/` escribe a mano un color, un radio, un lado de marco o un peldaño de la escala de espaciado: el vocabulario vive en `UI/Style/DesignTokens.swift`, y `UI/Components/` todavía no existe.
- **Verificación.** `Scripts/verify-domain.sh` en verde es Definition of Done de toda historia que toque `Domain/`, y el gate **deriva del árbol** la lista de suites: un `@Suite` nuevo que no esté registrado rompe el script en vez de no ejecutarse en silencio. No hay target de XCUITest y no lo habrá: la lógica de presentación se extrae a tipos probables sin SwiftUI.
- **Sin migración pendiente.** `schemaVersion` está desde el día uno y el arranque es limpio: no hay datos previos que migrar.

## UX & Interaction Patterns

- **Historial es una pestaña** del `TabView` (Inicio · Historial · Logros · Ajustes), hoy ocupada por un marcador de posición que no inventa contenido. Export y borrado de datos viven en **Ajustes**.
- **Fila de historial:** fecha arriba, métricas debajo (distancia, duración, ritmo), separador entre filas, sin avatar; el "~" marca los pasos estimados con su color propio. VoiceOver dice la magnitud completa ("3,2 kilómetros") y anuncia los pasos estimados **como estimados**.
- **Ajustes tiene una obligación que ninguna historia puede perder.** La pantalla tiene hoy "Zancada" y "Acerca de", y ese "Acerca de" son **dos filas obligatorias** —crédito a Open-Meteo y enlace al texto de CC BY 4.0— que cumplen una obligación de licencia (AD-24, NFR-7), fijadas por sus tests y mapeadas en `NOTICE`. Añadir exportar y borrar datos es **añadir una sección**; reorganizar la pantalla dejando fuera el "Acerca de" **no es una opción**.
- **Acciones irreversibles (AD-20).** Borrar una sesión, borrar todos los datos y descartar pasos estimados se disparan **solo** desde una superficie declarada, con confirmación explícita y objetivo táctil ≥ 44 pt. Cada pantalla **no** inventa su propio gesto destructivo.
- **"Celebrar, nunca culpar".** El historial vacío dice que aún no hay sesiones, no que Paul falló; y nada de badge counts, pull-to-refresh ni carousels.

## Cross-Story Dependencies

- **La 5.1 desbloquea a casi todo el mundo, y por eso se adelanta.** La consumen la **3.1** (suma semanal de distancia para el anillo), la **3.2** (acumulados de `marathon_42km` y `consistency_30`, y las rachas), la **5.2** (lista, totales y tendencia), la **5.3** (export e import) y la **5.4** (borrado). **La forma del registro los condiciona a todos**: decidirla mirando solo la 5.2 es decidirla mal.
- **Dentro del epic:** la 5.1 crea `sessions.json` y su dueño; la 5.2 lo **lee** y estrena la superficie de historial; la 5.3 reutiliza su serialización para el JSON y añade el CSV; la 5.4 escribe a través del mismo dueño y propaga el borrado a totales, anillo y progreso de logros no desbloqueados.
- **Con el Epic 3:** `achievements.json` es el fichero de la 3.2, pero su **dueño y su esquema** se definen aquí. Y la evaluación de logros ocurre en la misma transacción que persiste la sesión, así que el punto de escritura que abre la 5.1 es también donde la 3.2 se enchufa.
- **Con el Epic 2, una deuda con destino explícito:** probar que **recalibrar la zancada no cambia el historial** quedó registrado *para la 5.1*, porque no era demostrable sin sesiones cerradas. El test que falta es concreto: cerrar una sesión con 0,655 m, recalibrar a 0,670 m y comprobar que la fila guardada sigue en 0,655.
- **Con el Epic 6:** la escritura del workout en Apple Salud (6.1) cuelga del mismo cierre de sesión que ahora empieza a persistir. Y la pantalla de resumen, cuyas piezas están repartidas entre los epics 3, 5.1 y 6, sigue sin dueño único.
- **Límite derivado que hay que rederivar si se acumula:** el tope de zancada representable sale hoy del tope de pasos de **una** sesión. Si alguna vez la distancia se calcula sobre el **historial acumulado** —una suma de varias sesiones—, ese factor deja de ser el correcto y **ningún gate lo comprueba**.
