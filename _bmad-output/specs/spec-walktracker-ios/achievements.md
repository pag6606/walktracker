# Achievements — Catálogo de 14 logros

Companion de `SPEC.md` (CAP-8). Catálogo íntegro reutilizado sin cambios de contenido desde la PWA v3 (A-3), con las reglas de evaluación implementadas y validadas en producción. El AchievementEngine evalúa al cierre de cada sesión; los logros desbloqueados no se re-disparan ni se revocan (incluido si se elimina la sesión que los originó, ver CAP-15).

| # | key | Nombre | Descripción (UI) | Regla de evaluación | Icono |
|---|---|---|---|---|---|
| 1 | `first_km` | Tu primer kilómetro | Completa 1 km en una sesión | `session.distanceM ≥ 1000` | 🏅 |
| 2 | `first_5km` | Cinco kilómetros | Completa 5 km en una sesión | `session.distanceM ≥ 5000` | 🥉 |
| 3 | `first_10km` | Diez kilómetros | Completa 10 km en una sesión | `session.distanceM ≥ 10000` | 🥈 |
| 4 | `first_session` | Primera caminata | Completa tu primera sesión | Siempre al finalizar la primera sesión | 🚶 |
| 5 | `weekly_goal` | Meta semanal cumplida | Cumple tu meta de la semana | Evaluado por GoalEngine al cumplirse la meta semanal (no en el loop de sesión) | 🏆 |
| 6 | `rain_walker` | Caminata bajo la lluvia | Camina con clima lluvioso | `session.weather` con condición de lluvia (ver nota de mapeo abajo) | 🌧️ |
| 7 | `7_days_streak` | 7 días consecutivos | Camina 7 días seguidos | ≥ 1 sesión por día durante 7 días consecutivos (fechas sin duplicar, ordenadas desc) | 🔥 |
| 8 | `marathon_42km` | Maratonista | Acumula 42 km en total | `Σ distanceM de todas las sesiones ≥ 42000` | 🏃 |
| 9 | `speed_walker` | Caminante rápido | Ritmo menor a 8:00 /km | `session.paceSecPerKm > 0 y < 480` | ⚡ |
| 10 | `early_bird` | Madrugador | Camina antes de las 7:00 | `startedAt` entre 05:00 y 07:00 (hora local, ver nota) | 🌅 |
| 11 | `night_walker` | Caminante nocturno | Camina después de las 21:00 | `startedAt` entre 21:00 y 23:00 (hora local, ver nota) | 🌙 |
| 12 | `hot_walker` | Caminante del sol | Camina con temperatura >30 °C | `session.weather.tempC > 30` | ☀️ |
| 13 | `cold_walker` | Caminante del frío | Camina con temperatura <5 °C | `session.weather.tempC < 5` | ❄️ |
| 14 | `consistency_30` | Constancia | Acumula 30 sesiones en total | `total de sesiones ≥ 30` | 💪 |

## Reglas transversales

- **Acumulados:** con arranque limpio (OQ-3) todas las sesiones son `source: "ios"` y cuentan para `marathon_42km`, `consistency_30`, rachas y primeras marcas. Si CAP-16 se reactiva a futuro, las importadas (`"v3" | "migrated"`) también cuentan (su distancia es correcta — decisión D1 heredada).
- **Clima ausente:** si `session.weather` es `null`, los logros climáticos (`rain_walker`, `hot_walker`, `cold_walker`) no se evalúan como cumplidos.
- **Nota de mapeo lluvia:** en la PWA la detección era regex sobre string localizado (`/lluv|llovi|torment/i`). En iOS se mapea la condición del proveedor (enum WeatherKit, o código WMO si se usa fallback Open-Meteo: 51–67, 80–82, 95–99) a una categoría interna `rain`. No depender de strings localizados (ver `domain-model.md` §9).
- **Nota de zona horaria:** la PWA evaluaba `early_bird`/`night_walker` y rachas en UTC por detalle de implementación. En iOS se evalúan en hora local del dispositivo (la intención del logro es local).
- **Almacenamiento:** `achievements` store → `{ key, unlockedAt: ISO8601|null, progress: 0.0..1.0 }`. El grid de UI muestra locked/unlocked con progreso.
- **Celebración:** visual + sonora + háptica (CAP-12); en la PWA era solo visual + sonora (sin háptica, R5).
