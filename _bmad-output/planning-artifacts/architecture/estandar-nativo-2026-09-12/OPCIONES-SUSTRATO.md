---
id: OPCIONES-SUSTRATO-nativo
autor: Winston (System Architect)
fecha: 2026-09-12
estado: decisión pendiente de Paul
entrada: VALIDATION-mockups-v3-2026-09-12.md (B-8), PLAN-CAPACITOR-v2.md, SPEC-walktracker-ios
proposito: costear las opciones de sustrato antes de escribir el estándar nativo y los ADRs
---

# Opciones de sustrato — WalkTracker iOS

## 0. El hallazgo que reencuadra la pregunta

Se me pidió costear **dos** opciones: UI nativa dentro del WebView de Capacitor, o salida a SwiftUI.
El repositorio contiene **tres** sustratos vivos, y el que más lejos está no es ninguno de los dos.

| Sustrato | Código | Estado en git | CAP-11 HealthKit | CAP-18 Live Activity |
|---|---|---|---|---|
| **Capacitor** (`www/`, `adapters/`, `walktracker-kit/`) | 3.185 líneas | commiteado (rama actual) | ✗ | ✗ |
| **Flutter — Dart** (`lib/`) | 2.366 líneas | **sin trackear** | — | — |
| **Flutter — Swift** (`ios/Runner/AppDelegate.swift`) | 446 líneas | **sin trackear** | ✅ `HKWorkoutBuilder` | ✅ `Activity.request` |
| **SwiftUI** | 0 líneas | no existe | — | — |

Existe además un spine de arquitectura Flutter en `draft` fechado **2026-09-11**
(`architecture-walktracker-flutter-2026-09-11/ARCHITECTURE-FLUTTER.md`), que declara explícitamente
*"reemplaza el stack Capacitor/Web"* y *"big-bang, todo en una sola iteración"*.

**Las dos capacidades más caras y más nativas del proyecto —escritura en Apple Salud y Live Activity—
ya están implementadas, y solo en el camino Flutter.** El plugin de Capacitor no las tiene ni empezadas.

## 1. Riesgo inmediato, independiente de la decisión

`lib/`, `pubspec.yaml`, `ios/Runner/`, `ios/Runner.xcodeproj/` y `walktracker-kit/` están **sin trackear**.
Son ~2.800 líneas de app funcional, incluida la única implementación de HealthKit y ActivityKit del
proyecto, a un `git clean -fd` de desaparecer. Se commitea hoy, se decida lo que se decida.

## 2. Las tres opciones, costeadas

Unidad: **fin de semana de trabajo**, la misma que usa `PLAN-CAPACITOR-v2.md` para poder comparar.

### Opción A — Capacitor + rediseño de la UI web a estética iOS

Se mantiene el WebView; se reescribe la UI HTML/CSS con la dirección iOS-stock de los mockups.

| Partida | Coste |
|---|---|
| Rediseño de 7 pantallas en `index.html` (1.049 líneas, UI+CSS acopladas) | 2,0 |
| Plugin HealthKit en `walktracker-kit` (no existe) | 1,0 |
| Live Activity + ActivityKit en el plugin (no existe) | 1,5 |
| Export/import, recordatorios, estados de permiso | 1,0 |
| **Total** | **≈ 5,5** |

- ✅ Reutiliza `domain.js` (626 líneas) **validado en producción**. Una sola implementación del dominio.
- ✅ Conserva la PWA como canal secundario.
- ❌ El gate de rendimiento de 60 min **sigue sin validar**: se paga el rediseño antes de saber si el
  sustrato aguanta. Es la peor secuencia de riesgo de las tres.
- ❌ Sigue siendo un WebView. Si el criterio es *"se siente como una app"*, es la opción que menos lo cumple.
- ❌ Tira las 2.800 líneas de Flutter, HealthKit y Live Activity incluidos.

### Opción B — SwiftUI puro

| Partida | Coste |
|---|---|
| Portar el dominio a Swift (626 líneas JS, invariantes + 14 logros + 100 frases) | 1,5 |
| 7 pantallas SwiftUI | 2,5 |
| Adapters: storage, clima, motivación, reloj | 1,0 |
| Capa nativa: se **reaprovecha** casi entera de `AppDelegate.swift` (446 líneas ya escritas) | 0,5 |
| **Total** | **≈ 5,5** |

- ✅ Nativo sin discusión: UIKit/SwiftUI, HIG por construcción, mejor rendimiento y batería.
- ✅ Un solo lenguaje en todo el stack. Sin puente, sin canal, sin serialización.
- ❌ **Tercera implementación del mismo dominio** (JS → Dart → Swift). Tres oportunidades de divergir;
  la divergencia ya ocurrió una vez (ver Opción C, catálogo de logros).
- ❌ Tira las 2.366 líneas de Dart.
- ❌ Ninguna línea escrita hoy. Es la opción con más folio en blanco.

### Opción C — Flutter (consolidar lo que ya existe)

| Partida | Coste |
|---|---|
| Commitear y estabilizar lo existente | 0,25 |
| Extraer los puertos al dominio (`feedback/storage/motion/health/clock`) — hoy no existen | 0,5 |
| Mover engines al dominio (Goal, Motivation, Achievement, GapEstimator) | 0,75 |
| Restaurar el catálogo canónico de 14 logros (hoy hay 7, con semántica cambiada) | 0,25 |
| `summary_screen.dart` (falta) + cablear HealthKit y Live Activity desde los blocs | 0,75 |
| Aplicar la dirección visual de los mockups sobre el tema existente | 1,0 |
| Tests de dominio en Dart (portar los `*-tests.js` existentes) | 0,5 |
| **Total** | **≈ 4,0** |

- ✅ La opción más avanzada con diferencia: ~2.800 líneas, incluidas **las dos capacidades más caras
  del proyecto ya funcionando**.
- ✅ Sin WebView: el gate de rendimiento de 60 min deja de ser un riesgo abierto, desaparece.
- ✅ Adaptativo por construcción; claro/oscuro y safe areas resueltos por el framework.
- ⚠️ Flutter **no es UIKit**: renderiza con su propio motor. Con widgets Cupertino se acerca mucho a
  una app de Apple, pero no *es* una app de Apple. Si tu listón es la indistinguibilidad, es B.
- ❌ **Segunda implementación del dominio, y ya divergió.** El catálogo Dart tiene 7 logros con reglas
  distintas a las canónicas: `5km` mide 5 km *acumulados* donde el catálogo dice 5 km *en una sesión*;
  `100_workouts` (100 caminatas) sustituye a `consistency_30` (30 sesiones). No es un recorte: es otra
  semántica. Sin puertos ni tests, esa deriva seguirá.
- ❌ El catálogo vive en `application/blocs/achievements_bloc.dart` — lógica de dominio en la capa de
  aplicación, violando el propio spine Flutter y la restricción de arquitectura hexagonal del SPEC.

## 3. Recomendación

**Opción C, con tres condiciones no negociables.** El argumento no es que Flutter sea mejor que SwiftUI
—no lo es, para este caso—; es que **el 60 % del trabajo ya está hecho y contiene precisamente las dos
piezas que en las otras dos opciones cuestan 2,5 fines de semana**. Pagar 5,5 para llegar donde ya
estás a 4,0 sólo se justifica si la indistinguibilidad respecto a una app de Apple es un requisito, y
el SPEC no la pide: pide *"que Paul se sienta reconocido"*.

Condiciones:

1. **Un solo sustrato.** Se elimina el camino Capacitor del repo (`ios/App/`, `www/`, `adapters/`,
   `walktracker-kit/`, `capacitor.config.json`). Dos proyectos Xcode conviviendo en `ios/` es deuda
   que se cobra en cada build.
2. **El dominio Dart es la única fuente de verdad**, con puertos explícitos y los tests portados desde
   `test/*-tests.js`. El catálogo vuelve a los 14 canónicos, en `domain/`, no en un bloc.
3. **`domain.js` se congela** como referencia de contraste, no como código vivo.

Si la respuesta a *"¿qué significa nativo?"* es **"literalmente Apple: SwiftUI, UIKit, HIG"**, entonces
la respuesta es B y hay que decirlo hoy, porque cada fin de semana que pase con Flutter avanzando
encarece el cambio.

## 4. Consecuencias documentales de cualquier opción ≠ A

- El SPEC (`Constraints`) dice *"Capacitor como capa nativa (decisión Paul, OQ-1)"* y
  *"Descarta la reescritura SwiftUI total"*. **Ambas frases dejan de ser ciertas.** OQ-1 se reabre.
- `PLAN-CAPACITOR-v2.md` líneas 27/62/179 quedan derogadas, no corregidas.
- Los 8 epics y 28 historias se reestiman: E8 (Fundaciones) cambia de contenido por completo y
  E6/E7 pasan de "por hacer" a "cablear lo que ya existe".
