---
title: UX Design Brief — WalkTracker v2.0 Redesign
type: ux-handoff
status: ready-for-ux
created: 2026-07-04
author: Winston (Architect)
for: Sally (UX Designer)
---

# UX Design Brief — WalkTracker v2.0 Redesign

## Contexto para Sally

Paul quiere un **rediseño de UI** antes de migrar la app de PWA a Capacitor (iOS nativa). La app funciona hoy pero la interfaz es funcional-básica (botones azules sólidos, fuentes del sistema, sin identidad visual). Hay que darle un diseño pulido que:

1. Se vea como una **app nativa de iOS** (no una página web)
2. Mantenga la **operabilidad a ciegas** (botón +1 gigante, beep, FR-02)
3. Incorpore las **pantallas nuevas** del modo automático y HealthKit
4. Funcione en **iPhone 14 (390×844 pt)** como referencia

## Artefactos de entrada (léelos todos)

| # | Documento | Dónde | Qué le da |
|---|---|---|---|
| 1 | **PRD** | `_bmad-output/planning-artifacts/prds/prd-walktracker-2026-07-03/prd.md` | FRs, NFRs, User Journeys (UJ-1, UJ-2), Glosario |
| 2 | **SPEC §9 UI** | `input/SPEC_WalkTracker_v1.md` | Descripción original de las 3 pantallas |
| 3 | **Architecture Spine** | `_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md` | Constraints técnicos (NFR-4 UX móvil, AD-1 hexagonal) |
| 4 | **Plan Capacitor** | `_bmad-output/planning-artifacts/architecture/capacitor-migration/PLAN-CAPACITOR-v2.md` | El target: qué cambia con la migración nativa |
| 5 | **App actual** | `index.html` (1296 líneas) | El código que se va a rediseñar |

## Pantallas actuales (5)

```
1. HOME        → botón Iniciar + acceso a Ajustes (⚙) e Historial (📋)
2. SESSION     → botón +1 gigante (≥40% viewport), métricas en vivo, step counter (auto-mode)
                 controles: Pausar/Reanudar, Finalizar, Deshacer (↩ −1)
3. SUMMARY     → stats finales (vueltas, distancia, duración, ritmo) + Nueva sesión
4. SETTINGS    → zancada, pasos/vuelta, perímetro derivado, toggle modo automático
5. HISTORY     → lista de sesiones + totales acumulados
```

## Pantallas/conceptos nuevos a diseñar

| Nuevo | Descripción | Constraint |
|---|---|---|
| **HealthKit status** | Indicador visual de que la sesión se escribió en Salud | Aparece en Summary tras finalizar |
| **Modo automático mejorado** | Step counter "Paso X/62" con barra de progreso | Ya existe funcionalmente; pulir visual |
| **Onboarding de permisos** | iOS pedirá permiso de movimiento + HealthKit al primer uso | Pantalla o modal explicativo antes del permiso |
| **Icono de app** | Icono nativo para pantalla de inicio del iPhone | 1024×1024 fuente → adaptive |

## Constraints técnicos (no romper)

| Constraint | Origen | Por qué |
|---|---|---|
| **Botón +1 ≥ 40% viewport** | FR-02, NFR-4 | Operable a ciegas mientras camina |
| **Targets táctiles ≥ 44 pt** | NFR-4 | HIG de Apple |
| **Modo claro/oscuro** | NFR-4 | `prefers-color-scheme` |
| **Safe areas iOS** | NFR-4 | `env(safe-area-inset-bottom)` |
| **Sin framework CSS** | AD-2, NFR-5 | CSS vanilla inline, sin Tailwind/bootstrap |
| **Single-file** | AD-2 | Todo el CSS va en `<style>` dentro de index.html |
| **Sin imágenes externas** | NFR-1 offline | Solo SVG inline o CSS |

## User Journeys clave (del PRD)

**UJ-1:** Paul camina su circuito sin mirar la pantalla → inicia sesión, marca vueltas con pulgar a ciegas, escucha beep, cambia a música, vuelve, finaliza.

**UJ-2:** Paul recalibra → entra a Ajustes, edita zancada/pasos, ve perímetro recalcularse, guarda.

## Lo que NO debe cambiar (invariantes de UX)

- El **botón +1** sigue siendo el elemento dominante de la pantalla de sesión
- El **beep** sigue como feedback primario (no reemplazar por solo visual)
- **Deshacer** (↩ −1) debe seguir accesible durante la sesión activa
- **3 pantallas principales** (Home, Sesión, Historial/Ajustes) — no añadir complejidad innecesaria

## Output esperado de Sally

Sally debe producir (vía `bmad-ux` skill):
1. **DESIGN.md** — identidad visual, tokens (colores, tipografía, espaciado), componentes
2. **EXPERIENCE.md** — arquitectura de información, flujos, estados, interacciones, accesibilidad
3. Opcional: mockups/wireframes (excalidraw o descripción)

El output va en `_bmad-output/planning-artifacts/ux-designs/ux-walktracker-v2/`

## Próximo paso

Invocar a **Sally** con la skill `bmad-agent-ux-designer` o `bmad-ux`.
