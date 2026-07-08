---
baseline_commit: NO_VCS
epic: E1
story_key: e1-s12-climate-adapters
status: ready-for-dev
---

# E1-S1+S2 — Clima: GeoPort + WeatherPort

**Epic:** E1 — Clima
**Prioridad:** Must | **Estimación:** S (2 días) | **Dependencias:** E0-S4

## Story

**Como** Paul, **quiero** que la app obtenga mi ubicación y el clima actual al iniciar una sesión, **para** saber las condiciones de mi caminata.

## Acceptance Criteria

- [ ] `GeoPort.oneShot()` retorna `{lat, lon}` o `null` (timeout 3s, permiso opcional)
- [ ] Coordenadas redondeadas a 2 decimales (privacidad RNF-06)
- [ ] `WeatherPort.fetch({lat, lon})` retorna snapshot de clima o `null`
- [ ] Llama a Open-Meteo API (sin key, CORS abierto, timeout 3s)
- [ ] Snapshot: tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh
- [ ] condition mapea código WMO a español
- [ ] ≥8 tests (mock), 0 fallos

## File List
*To be filled on completion*

## Status
**Current:** ready-for-dev | **Last updated:** 2026-07-07
