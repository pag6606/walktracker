---
title: WalkTracker v2.0 — Migración a Capacitor (iOS nativa)
type: architecture-proposal
status: draft
created: 2026-07-04
updated: 2026-07-04
author: Winston (System Architect)
parent_spine: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md
---

# Plan de Migración — WalkTracker PWA → Capacitor (iOS nativa)

## 1. Problema

La PWA actual (v1.1, GitHub Pages) funciona pero iOS Safari impone 3 limitaciones bloqueantes para el caso de uso de Paul:

| Limitación | Impacto | Causa raíz |
|---|---|---|
| **Acelerómetro no funciona en background** | Modo automático pierde pasos al cambiar de app o bloquear | iOS suspende `DeviceMotionEvent` al background |
| **Sin HealthKit** | Imposible escribir workouts directo a Salud | Safari/PWA no tiene API de HealthKit |
| **Wake Lock se libera al background** | Pantalla se apaga si no se toca | iOS libera `navigator.wakeLock` al background |

Estas son **limitaciones de la plataforma Apple**, no de la app. No tienen solución dentro de una PWA.

## 2. Solución propuesta — Capacitor

**Capacitor** (por Ionic) envuelve la web app existente en un WebView nativo y expone APIs del dispositivo vía plugins. Es la opción de **menor esfuerzo** porque reutiliza el 90% del código actual.

### Por qué Capacitor y no alternativas

| Opción | Esfuerzo | Reutilización | Veredicto |
|---|---|---|---|
| **Capacitor** | 1 fin de semana | 90% (HTML+CSS+JS intacto) | ✅ Recomendada |
| SwiftUI nativa | 3-4 fines de semana | 0% (rewrite total) | Descartada por effort |
| React Native | 3-4 fines de semana | 10% (solo lógica) | Descartada por effort |

Capacitor es **tecnología aburrida** (principio de Winston): respaldada por Ionic, miles de apps en producción, API estable, documentación sólida.

### Qué cambia vs qué se mantiene

```
ACTUAL (PWA pura)                    PROPUESTA (Capacitor)
┌──────────────────┐                ┌──────────────────────────┐
│  index.html      │                │  index.html (igual)      │
│  ├─ UI Layer     │                │  ├─ UI Layer (igual)     │
│  ├─ Domain       │──── MANTIEN ──→│  ├─ Domain (igual)       │
│  └─ Adapters     │                │  └─ Adapters             │
│     ├ AudioPort  │                │     ├ AudioPort (igual)  │
│     ├ StoragePort│                │     ├ StoragePort (igual)│
│     ├ ClockPort  │                │     ├ ClockPort (igual)  │
│     └ Pedometer  │                │     ├ Pedometer ← NATIVO │
│       (DeviceMotion)              │     │  (CMPedometer bg)   │
└──────────────────┘                │     ├ WakeLock ← NATIVO  │
                                    │     │  (isIdleTimerDisabled)│
                                    │     └ HealthKitPort ← NEW │
                                    │        (HKWorkout write) │
                                    └──────────────────────────┘
```

**Mantiene:** Domain puro (Session, Chronometer, MetricsCalculator, CalibrationProfile), UI (Home/Sesión/Historial/Ajustes), localStorage (funciona en Capacitor WebView).

**Cambia:** 3 adapters del borde se reemplazan por plugins nativos. El dominio y la UI **no se tocan**.

## 3. Impacto arquitectónico — nuevos ADs

Los 11 ADs del spine actual se mantienen. Se añaden:

### AD-12 — Capacitor como capa nativa
- **Binds:** all
- **Prevents:** rewrite total de la app; doble mantenimiento web+nativo.
- **Rule:** la web app (`index.html`) se sirve dentro de un Capacitor WebView. Los plugins nativos se acceden vía `@capacitor/*` como adapters en el borde. El dominio no conoce Capacitor.

### AD-13 — CMPedometer reemplaza DeviceMotionEvent
- **Binds:** FR-9 (auto-mode), Pedometer adapter
- **Prevents:** pérdida de conteo de pasos en background.
- **Rule:** el adapter `Pedometer` usa el plugin `@capacitor-community/pedometer` (o un plugin custom que envuelva `CMPedometer`) en lugar de `DeviceMotionEvent`. Cuenta pasos en background incluso con pantalla bloqueada. El dominio `Session.lap()` no cambia — solo cambia quién llama `onLap()`.

### AD-14 — HealthKitPort para escritura directa a Salud
- **Binds:** RF-10 (export), §10 HealthKit
- **Prevents:** flujo manual CSV → Health Importer.
- **Rule:** nuevo puerto `HealthKitPort` con método `writeWorkout(session)`. Adapter usa `capacitor-healthkit` (npm). Solo iOS. En web (PWA), el puerto no se registra y se fallback a CSV (v1.1).

### AD-15 — WakeLock nativo via Capacitor
- **Binds:** RF-12, NFR-4
- **Prevents:** pantalla se apaga durante sesión.
- **Rule:** `WakeLock` adapter usa `@capacitor-community/keep-awake` o nativo `isIdleTimerDisabled`. No se libera al background.

## 4. Estructura del proyecto tras migración

```text
walktracker/
├── index.html              # Web app (sin cambios funcionales)
├── sw.js                   # SW para versión web (se mantiene para GitHub Pages)
├── manifest.webmanifest    # Manifest PWA (se mantiene)
├── domain.js               # Domain standalone (sin cambios)
├── src/
│   └── plugins/            # Plugins Capacitor custom (si se necesitan)
│       └── pedometer-bg/   # Plugin nativo CMPedometer background
│           ├── Podfile
│           └── PedometerPlugin.swift
├── ios/
│   ├── App/
│   │   └── App.xcworkspace # Proyecto Xcode (generado por Capacitor)
│   └── entitlements/       # HealthKit entitlement
├── capacitor.config.json   # Configuración Capacitor
├── package.json            # Dependencias npm (Capacitor + plugins)
└── test/
    └── domain-tests.js     # Tests del dominio (sin cambios)
```

## 5. Dependencias y licencias

Todas **MIT o Apache-2.0** (cumple AGENTS.md — sin copyleft):

| Paquete | Licencia | Propósito | Estado |
|---|---|---|---|
| `@capacitor/core` | MIT | Runtime Capacitor | ✅ Estable |
| `@capacitor/ios` | MIT | Plataforma iOS | ✅ Estable |
| `@capacitor/preferences` | MIT | Storage nativo (opcional) | ✅ Estable |
| `@capacitor-community/keep-awake` | MIT | Wake lock nativo | ✅ Verificado: v8.0.1, 58K downloads/semana |
| Plugin CMPedometer (custom) | — | Pasos en background | ⚠️ `@capacitor-community/pedometer` **no existe** en npm → escribir plugin custom |
| Plugin HealthKit (custom o existente) | — | HealthKit write | ⚠️ Verificar `capacitor-healthkit` o escribir custom |

> **Verificación web realizada:** `@capacitor-community/keep-awake` confirmado (MIT, estable). `@capacitor-community/pedometer` **no disponible** — se requiere plugin custom (~80 líneas Swift con `CMPedometer.startPedometerUpdates`).

## 6. Requisitos

| Requisito | Detalle |
|---|---|
| **Mac con Xcode 15+** | Para compilar iOS |
| **Cuenta Apple Developer** | $99/año (para instalar en dispositivo y App Store) |
| **Node.js + npm** | Para Capacitor CLI |
| **iPhone físico** | Simulator no tiene acelerómetro real |

## 7. Breakdown de trabajo (5 stories)

### Story M-1: Inicializar Capacitor en el proyecto
- `npm init`, instalar `@capacitor/core`, `@capacitor/ios`
- `npx cap init "WalkTracker" "com.pag6606.walktracker"`
- `npx cap add ios`
- Configurar `capacitor.config.json` (webDir: ".")
- Verificar que `npx cap open ios` abre Xcode y la app corre en simulator

### Story M-2: Plugin CMPedometer (background step counting)
- Buscar/installar `@capacitor-community/pedometer` o escribir plugin custom
- Si custom: `CMPedometer` con `startPedometerUpdates` → evento `stepcount`
- Reemplazar adapter `Pedometer` en index.html: usar plugin en lugar de `DeviceMotionEvent`
- Verificar: pasos se cuentan con pantalla bloqueada
- Entitlement: `NSMotionUsageDescription` en Info.plist

### Story M-3: Plugin HealthKit (escritura directa)
- Instalar `capacitor-healthkit` o plugin equivalente
- Implementar `HealthKitPort.writeWorkout(session)` → `HKWorkout` type `.walking`
- Entitlement: `HealthKit` capability + `NSHealthShareUsageDescription`
- Llamar `writeWorkout` al finalizar sesión (reemplaza export CSV en iOS)

### Story M-4: WakeLock nativo
- Instalar `@capacitor-community/keep-awake`
- Reemplazar `navigator.wakeLock` por el plugin
- Verificar: pantalla se mantiene activa al cambiar de app

### Story M-5: Build, test en dispositivo y despliegue
- Compilar en iPhone físico (no simulator — sin acelerómetro)
- Verificar los 3 flujos: modo manual, modo automático con música en background, HealthKit write
- Configurar provisioning profile
- Opcional: App Store Connect (si se quiere publicar)

## 8. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Plugin pedometer no existe o no soporta background | Media | Alto | Escribir plugin custom (~80 líneas Swift) |
| HealthKit requiere aprobación de Apple | Baja | Medio | Documentar uso en review; solo escritura, no lectura de datos sensibles |
| localStorage no persiste en Capacitor iOS | Baja | Medio | Migrar a `@capacitor/preferences` si ocurre (detrás de StoragePort) |
| Performance del WebView en dispositivos antiguos | Baja | Bajo | La app es trivial (sin animaciones pesadas); no debería ser problema |

## 9. Lo que NO cambia (estabilidad del dominio)

Este es el punto clave: **el dominio y la UI no se modifican**. Los 11 ADs del spine actual se respetan. Solo se reemplazan 3 adapters en el borde:

| Adapter | Actual (PWA) | Tras Capacitor |
|---|---|---|
| Pedometer | `DeviceMotionEvent` (no background) | `CMPedometer` plugin (background ✅) |
| WakeLock | `navigator.wakeLock` (se libera en bg) | `keep-awake` plugin (persiste ✅) |
| HealthKitPort | No existe | `capacitor-healthkit` (nuevo ✅) |

La arquitectura hexagonal-lite demuestra su valor aquí: cambiar de PWA a nativa solo afecta el borde, no el núcleo.

## 10. Estrategia de doble canal (PWA + Nativa)

El proyecto puede mantener **ambos canales**:

- **GitHub Pages (PWA):** para acceso web, compartir URL, usuarios sin iPhone
- **Capacitor (iOS):** para Paul, con background + HealthKit

El mismo `index.html` sirve para ambos. La diferencia es cómo se carga:
- PWA: navegador → GitHub Pages → `sw.js` cache
- Capacitor: WebView nativo → archivos locales → plugins nativos

Esto es **doble canal sin duplicar código**.
