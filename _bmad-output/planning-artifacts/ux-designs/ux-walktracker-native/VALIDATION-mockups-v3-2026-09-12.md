---
id: VALIDATION-mockups-v3
fecha: 2026-09-12
objeto: _bmad-output/planning-artifacts/ux-designs/ux-walktracker-native/mockups/ (7 pantallas + index)
contraste: _bmad-output/specs/spec-walktracker-ios/SPEC.md (+ achievements.md), index.html (web app v3)
veredicto: NO APTO PARA BUILD — apto como dirección visual
estado: 3 correcciones aplicadas 2026-09-12 (B-3, B-4, B-5 parcial, etiqueta del index)
decision_paul: pivot nativo APROBADO; reestimación + ADRs a cargo del arquitecto; nueva party al cerrar el estándar nativo
---

# Validación de mockups — WalkTracker Native iOS (v3)

## Veredicto

Los siete mockups **no son aptos para construcción** y **sí son aptos como dirección visual**.
La dirección iOS-stock queda aprobada por decisión de Paul (2026-09-12). Lo que sigue es la lista
de lo que hay que corregir antes de que ninguna de estas pantallas sea contrato de implementación.

Etiqueta actual del set: `mockups/index.html` dice *"Aprobado para build"*. **Es falsa y debe cambiarse
a `EXPLORATORIO` hoy.** Es el único hallazgo de esta validación que no depende de ninguna otra decisión.

- 🔴 Bloqueantes: **11**
- 🟠 Mayores: **14**
- 🟡 Menores: **9**

---

## 🔴 Bloqueantes

### B-1 · Paridad funcional perdida frente a la web app v3
Ocho capacidades del SPEC que **ya funcionan hoy en `index.html`** no tienen representación en ningún mockup.

| CAP | Falta en mockups | Existe en v3 (`index.html`) |
|---|---|---|
| CAP-3 | Marca de pasos estimados `~` | `est-banner`, `est-count`, `est-discard` |
| CAP-5 | Snapshot de clima | `home-weather`, `ses-weather` |
| CAP-6 | Overlay de frase motivacional 3–4 s | `motivational-overlay`, `ov-quote` |
| CAP-10 | Gráfico de tendencia | `trend-chart` (4 semanas, línea 818) |
| CAP-10 | Empty state de historial | `history-empty` |
| CAP-14 | Export CSV/JSON + import | `btn-export`, `last-export` (línea 899) |
| CAP-17 | Recordatorios de meta | — (tampoco en v3; pendiente en ambos) |
| CAP-2 | Estado *Motion & Fitness denegado* | `screen-motion-denied` |
| CAP-4 | Cadencia en métricas en vivo | `ses-cad` |
| CAP-18 | Layout de pantalla de bloqueo | — (solo un toggle en Ajustes) |

Extras de la v3 sin equivalente dibujado: `recovery-banner`, `backup-warning`, `wl-banner`, `btn-delete-all`.

**Regla que sale de aquí:** ninguna pantalla del rediseño puede ofrecer menos capacidades que su
equivalente v3. Esta tabla es el checklist de paridad.

### B-2 · CAP-3 sin UI es una regresión de integridad, no de features
La marca `~` de pasos estimados es un **invariante de dominio** declarado en Constraints
(*"pasos estimados siempre desglosados y marcados"*). Sin ella, la app muestra números que no
puede justificar. Afecta a `mock-02`, `mock-03`, `mock-04` y `mock-05`.

### B-3 · Catálogo de logros inventado: 24 vs 14 — ✅ CORREGIDO 2026-09-12
`mock-06` declara *"8 de 24 logros desbloqueados"*. El catálogo canónico (`achievements.md`) tiene
**14**, y el SPEC lo blinda en A-3: *"se reutilizan íntegros, sin cambios de contenido"*.
De los 14 reales solo aparecían 2. Los 12 restantes del mockup estaban inventados.

**Corregido:** `mock-06` reescrito con los 14 canónicos de `achievements.md`, copia de UI verbatim.
Estado coherente derivado del fixture de `mock-05` (12 sesiones, 48,3 km, mejor sesión 6,15 km,
mejor ritmo 11:42, sin sesiones antes de 07:00 ni después de 21:00): **4 desbloqueados / 10 bloqueados**
— Primera caminata, Tu primer kilómetro, Cinco kilómetros, Maratonista (48,3 ≥ 42 km).
Anillo recalculado a `dashoffset="81"` = 28,6 % = 4/14 (antes marcaba 66 % junto a un texto del 33 %).
Strip *"Siguiente logro"* → **Meta semanal cumplida, 5,2 de 10 km, faltan 4,8 km**, que ahora concuerda
exactamente con el 52 % del anillo de `mock-01`.

### B-4 · Logros de desnivel: técnicamente imposibles — ✅ CORREGIDO 2026-09-12
*"Montañés — 10.000 m de desnivel acumulado"* y *"Cima — 5.000 m"* requerían altimetría/GPS.
`GPS de ruta ni mapas` es **non-goal explícito** del SPEC.

**Corregido:** eliminados junto con el resto del catálogo inventado (ver B-3). Con ellos cae también
m-6 (el duplicado de *"Montañés"* con dos iconos y dos descripciones).

### B-5 · Métricas inventadas fuera del dominio
- **218 kcal** (`mock-04`): CAP-4 enumera pasos, distancia, tiempo, ritmo y cadencia. Calorías no
  está en el dominio y su cálculo exigiría peso corporal, que no se pide en ninguna pantalla.
- **Badge `+150`** (`mock-06`): sistema de puntos inexistente en SPEC y dominio.
  **Retirado** en la corrección de B-3 — vivía dentro del bloque reescrito y re-publicar puntos
  inventados mientras se arreglaban logros inventados no tenía defensa. La regla CSS `.next-ach-badge`
  queda huérfana en la hoja de estilos; inocua, se limpia en la v4.

### B-6 · "Restaurar compras" en Ajustes
`mock-07`, pie de página. Producto de usuario único, sin backend, sin cuentas, y con
*"Publicación en App Store como requisito de éxito"* listado como non-goal. Residuo de plantilla.

### B-7 · Coherencia aritmética rota en las 7 pantallas
Ningún fixture sobrevive a una división. Detalle completo en el anexo A.
Consecuencia real: las zancadas implícitas en el historial son 0,52 / 0,58 / 0,60 / 0,62 m —
**ninguna es los 0,75 m que muestra la propia pantalla de Ajustes**. El diseño no se hizo contra
`domain-model.md`.

### B-8 · Contradicción con `PLAN-CAPACITOR-v2.md`
Líneas 62 y 179: *"el dominio y la UI no se modifican"*. Línea 27: *"reutiliza el 90 % del código
actual"* — ese 90 % es la UI. El pivot invalida el argumento con el que se descartó SwiftUI
(*"3-4 fines de semana, rewrite total, descartada por effort"*).
**Requiere ADR + reestimación antes de tocar código de UI.** Asignado al arquitecto.

### B-9 · Base dimensional inconsistente
Lienzo de **291 px** de ancho con safe areas de **59 pt / 34 pt** y tab bar de **49 pt** — valores
reales de iPhone, que corresponden a **393 pt**. O el marco está mal o la tipografía está ~35 %
sobredimensionada. En dispositivo, todo baila.

### B-10 · Sin tema claro en 4 de 7 pantallas
`mock-01`, `02`, `03` y `04` tienen `background: #000000` cableado. La restricción de UX del SPEC
dice *"claro/oscuro"*. La v3 lo cumple con `:root` alternativo; los mockups lo rompen.

### B-11 · Borrado destructivo bajo mínimos (CAP-15)
`mock-05`: botón papelera de **28×28 px** — la restricción del SPEC es **≥ 44 pt** —, sin
confirmación, y sustituyendo el gesto *swipe* que es el patrón nativo. Tres fallos en un elemento.

---

## 🟠 Mayores

| # | Pantalla | Hallazgo |
|---|---|---|
| M-1 | `mock-01` | Cada `.bar-col` contiene **dos** `.bar`: 14 barras para 7 días |
| M-2 | `mock-01` | Cabecera *"Lunes, 11 de septiembre"* pero el gráfico marca **sábado** como hoy |
| M-3 | `mock-01` | *"Buenos días"* junto a un registro de las **14:05** |
| M-4 | `mock-01` | Quick actions (Historial, Logros) **duplican el tab bar**; *"Estadísticas"* es un cuarto destino que no existe en el SPEC ni en la navegación |
| M-5 | `mock-01` | El *"14:05"* del `today-right` no tiene etiqueta: ¿hora o ritmo? |
| M-6 | `mock-02` | **Dos indicadores de directo** simultáneos: pill `EN CURSO` + badge `LIVE`. Además `LIVE` está en inglés en una UI en español |
| M-7 | `mock-02` | Botón `✕` sin semántica definida, `flex: 0.4` pegado al primario, sin confirmación, y conviviendo con *"Finalizar caminata"*. Dos salidas ambiguas |
| M-8 | `mock-02` | El ritmo se muestra siempre; CAP-4 exige mostrarlo **solo con distancia ≥ 100 m**. No hay estado para el caso contrario |
| M-9 | `mock-03` | La pausa **pierde** la barra de meta semanal que sí tiene la activa: inconsistencia entre estados de la misma pantalla |
| M-10 | `mock-04` | *"Guardado en Salud"* incondicional. No hay estado de permiso denegado ni de escritura fallida (CAP-11) |
| M-11 | `mock-04` | Logros mostrados que no existen: *"Primer 5K"* (catálogo: *Cinco kilómetros*), *"Racha 3 días"* (catálogo: *7 días consecutivos*) |
| M-12 | `mock-05` | Segmentado en **"Mes"** pero la lista muestra Septiembre **y** Agosto |
| M-13 | Todas | **Tres tab bars distintos**: SVG inline (`01`), emoji 🏠📋🏆⚙️ (`05`), solo texto (`06`, `07`). No hay sistema de componentes |
| M-14 | Todas | Emoji como iconografía de chrome, revirtiendo la decisión v2 (*"SVG icons en vez de emoji"*). Nota: en las **insignias** de logros el emoji sí es correcto — el catálogo los especifica |

---

## 🟡 Menores

| # | Pantalla | Hallazgo |
|---|---|---|
| m-1 | `mock-01` | El SVG del CTA no es un glifo de caminar ni de play |
| m-2 | `mock-01` | *"Ver detalles →"* no tiene destino definido |
| m-3 | `mock-02/03` | Emoji `⏸` y `▶` dentro de botones tipográficos |
| m-4 | `mock-04` | *"🏃 Nueva caminata"* como acción primaria justo al terminar de caminar; prioridad discutible frente a *"Volver al inicio"* |
| m-5 | `mock-05` | La clase `session-time` renderiza la unidad *"km"*: el nombre miente |
| m-6 | `mock-06` | *"Montañés"* aparece dos veces (strip + rejilla) con **dos iconos** (🏔️/🗻) y **dos descripciones** distintas |
| m-7 | `mock-06` | Tab bar sin iconos, solo etiquetas |
| m-8 | `mock-07` | Sublabels cruzados: *"Sonido — Vibración y sonidos en metas"* / *"Vibración — Haptic feedback"* |
| m-9 | `mock-07` | *"Live Activity"* agrupada bajo la sección **Salud**; es una capacidad de sistema, no de HealthKit |

---

## Lo que sí funciona (y hay que conservar en la v4)

- El **CTA sobre el fold** en Home: la decisión v2 se sostiene y es la mejor de todo el set.
- El **anillo de meta semanal** de `mock-01` es el único elemento **aritméticamente correcto**:
  `dasharray 251 / dashoffset 120` = 52,2 %, y el texto dice 52 %, 4,8 km restantes de 10.
- La reducción del anillo a *"Restante esta semana + plazo domingo"* (decisión v3) funciona.
- La **distancia en gris** en `mock-03` como señal de estado pausado: buena, silenciosa, correcta.
- La jerarquía de la sesión activa (número enorme + rejilla de tres celdas) es sólida.
- `mock-07` sin info-card, solo controles con disclosure (decisión v3): correcto para iOS.

---

## Anexo A — Aritmética

| Pantalla | Afirma | Real | Δ |
|---|---|---|---|
| `01` | 3,2 km · 24.800 pasos | 24.800 × 0,75 m = **18,6 km** | ×5,8 |
| `01`/`04`/`05` | *"Lunes, 11 de septiembre"* | 11-09-2026 es **viernes** | — |
| `02` | 3,24 km en 24:18 → 13:42 /km | **7:29 /km** | +6:13 |
| `02` | Meta *"5.2 / 10 km"* con `width: 34%` | **52 %** | −18 pp |
| `04` | Misma sesión, ahora 42:18 → 13:42 /km | **13:03 /km** | +0:39 |
| `02` vs `04` | 24:18 → 42:18, distancia sin cambiar | inconsistencia entre pantallas | +18 min |
| `05` | 48,3 km en 5:24 h → 14:12 /km | **6:42 /km** (14:12 exigiría 11,4 h) | ×2,1 |
| `05` | Zancadas implícitas por fila | 0,52 / 0,58 / 0,60 / 0,62 m | Ajustes dice **0,75** |
| `06` | *"8 de 24"* con anillo `113/38` | anillo = **66 %**, texto = **33 %** | ×2 |
| `06` | *"4.500 logrados + 4.500 para desbloquear"* | 9.000 ≠ meta de **10.000** | −1.000 |
| `06` | *"Cima — 5.000 m"* **desbloqueado** | con 4.500 m logrados | imposible |
| `06` | *"Maratoniano — 100 km"* | catálogo: **42 km** | — |
| `06` | *"Noctámbulo — 22h+"* | catálogo: **después de las 21:00** | — |

---

## Salida de esta validación

1. ✅ **Hecho 2026-09-12:** `mockups/index.html` — *"Aprobado para build"* → **"EXPLORATORIO — no apto
   para build"**, con referencia a este documento.
2. ✅ **Hecho 2026-09-12:** logros de desnivel eliminados (B-4) y `mock-06` devuelto a los 14
   canónicos (B-3), con fixture aritméticamente coherente y `+150` retirado (B-5, parcial).
3. **Arquitecto:** definir el **nuevo estándar nativo**, escribir los ADRs (incluido el que corrige
   `PLAN-CAPACITOR-v2.md` líneas 27/62/179) y la reestimación. Debe resolver explícitamente la
   ambigüedad abierta: *"todo nativo"* = UI nativa **dentro** del WebView, o **salida de Capacitor**.
4. **v4 de mockups:** congelada hasta que exista el estándar. Al reabrirse, entra con la tabla de
   paridad de B-1 como checklist y con fixtures derivados de `domain-model.md`.
5. **Nueva party** al cerrar el punto 3.
