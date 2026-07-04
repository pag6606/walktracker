# Handoff para Amelia (Dev) — WalkTracker v2.0 Rediseño UI

## Contexto

Paul aprobó el rediseño UI (Volt + Card Sport). El desarrollo se hará en una máquina Windows. Este documento le da a Amelia todo lo que necesita.

## Artefactos de entrada (léelos todos)

| # | Documento | Dónde | Qué contiene |
|---|---|---|---|
| 1 | **DESIGN.md** | `_bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md` | Tokens de color (12), tipografía (8 roles), spacing, componentes (7), Do's & Don'ts |
| 2 | **EXPERIENCE.md** | `_bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md` | IA (5 surfaces), estados (9), interacciones, accesibilidad, 3 Key Flows |
| 3 | **Mockups HTML** | `_bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/mockups/key-screens-all.html` | 5 pantallas × dark+light, ábrelo en navegador para referencia visual |
| 4 | **App actual** | `index.html` (1296 líneas) | El código que vas a rediseñar |
| 5 | **Architecture Spine** | `_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md` | Constraints técnicos (11 ADs) |
| 6 | **Plan Capacitor** | `_bmad-output/planning-artifacts/architecture/capacitor-migration/PLAN-CAPACITOR-v2.md` | El target: migración nativa iOS (después del rediseño) |

## Qué hay que hacer

### Story RED-1: Actualizar CSS tokens en index.html

Reemplazar las CSS custom properties actuales por los tokens Volt:

```css
/* DARK (default) */
:root {
  --canvas: #1A1A1A;
  --surface: #2A2A2A;
  --accent: #CCFF00;
  --secondary: #FF6600;
  --danger: #FF453A;
  --success: #30D158;
  --text: #FFFFFF;
  --muted: #777777;
  --border: #3A3A3A;
}

/* LIGHT */
@media (prefers-color-scheme: light) {
  :root {
    --canvas: #F5F5F7;
    --surface: #FFFFFF;
    --accent: #CC9900;  /* ⚠️ Si se usa en texto pequeño, subir a #B8860B (contraste) */
    --text: #1D1D1F;
    --muted: #86868B;
    --border: #D2D2D7;
  }
}
```

### Story RED-2: Layout Card Sport en Session screen

Reestructurar la pantalla de sesión:
- Header: "Sesión activa" + "● EN CURSO" (accent)
- Card elevada: número de vueltas (hero, 48px, 900, accent) + 3 sub-métricas
- Botón +1: accent background, rounded/xl (20px), ≥40% viewport
- Controles: Pausar (surface) + Finalizar (danger), rounded/md (12px)

### Story RED-3: Actualizar pantallas restantes

- **Home**: botón Iniciar circular, header con ⚙ y 📋 icons
- **Summary**: grid 2×2 de stats + HealthKit badge ("✓ Escrito en Salud")
- **Settings**: campos con labels, toggle switch, validation feedback
- **History**: card de totales + lista de rows

### Story RED-4: Modo claro completo

Asegurar que las 5 pantallas se vean correctas en modo claro con los tokens light.

## Constraints que NO debes romper

- **AD-2**: Single-file (todo CSS en `<style>` dentro de index.html, sin frameworks)
- **AD-5**: Perímetro siempre derivado/readonly en Settings
- **AD-6**: Cronómetro wall-clock (no cambiar la lógica del timer)
- **AD-7**: Validación en frontera (validar antes de guardar)
- **AD-8**: Recovery silencioso (no agregar prompts)
- **AD-9**: Beep como feedback primario (no quitarlo ni hacerlo opcional)
- **FR-02**: Botón +1 ≥40% viewport
- **NFR-4**: Targets ≥44pt, safe areas iOS
- **NFR-5**: Sin CDN, sin imports externos, sin Google Fonts

## Cómo probar

```bash
# En Windows (PowerShell o CMD)
python -m http.server 8000
# Abrir http://localhost:8000 en Chrome/Edge

# Tests del dominio (Node.js)
node test/domain-tests.js
# Debe dar: 51 passed, 0 failed
```

## Flujo de trabajo (GitFlow)

1. Crear branch: `feature/redesign-ui`
2. Implementar Story RED-1 a RED-4
3. Verificar tests: `node test/domain-tests.js` (deben seguir pasando)
4. Commit + push
5. Crear PR a main
6. Merge

## Token reference rápido

| Token | Dark | Light |
|---|---|---|
| canvas | `#1A1A1A` | `#F5F5F7` |
| surface | `#2A2A2A` | `#FFFFFF` |
| accent | `#CCFF00` | `#CC9900` |
| secondary | `#FF6600` | `#FF6600` |
| danger | `#FF453A` | `#FF453A` |
| success | `#30D158` | `#30D158` |
| text | `#FFFFFF` | `#1D1D1F` |
| muted | `#777777` | `#86868B` |
| border | `#3A3A3A` | `#D2D2D7` |
