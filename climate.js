/**
 * climate.js — WalkTracker Climate Module (AD-14, AD-17)
 *
 * GeoPort: one-shot geolocation
 * WeatherPort: Open-Meteo API (sin key, sin cuenta)
 * WMO condition mapper: códigos → español
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.Climate = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ═══════════════════════════════════════════════════════
  //  WMO Condition Mapper
  //  ═══════════════════════════════════════════════════════

  const WMO_CONDITIONS = {
    0: 'Despejado', 1: 'Mayormente despejado', 2: 'Parcialmente nublado',
    3: 'Nublado', 45: 'Niebla', 48: 'Niebla con escarcha',
    51: 'Llovizna ligera', 53: 'Llovizna moderada', 55: 'Llovizna densa',
    56: 'Llovizna helada ligera', 57: 'Llovizna helada densa',
    61: 'Lluvia ligera', 63: 'Lluvia moderada', 65: 'Lluvia intensa',
    66: 'Lluvia helada ligera', 67: 'Lluvia helada intensa',
    71: 'Nevada ligera', 73: 'Nevada moderada', 75: 'Nevada intensa',
    77: 'Granizada',
    80: 'Chubascos ligeros', 81: 'Chubascos moderados', 82: 'Chubascos intensos',
    85: 'Chubascos de nieve ligeros', 86: 'Chubascos de nieve intensos',
    95: 'Tormenta', 96: 'Tormenta con granizo ligero', 99: 'Tormenta con granizo intenso',
  };

  function wmoToSpanish(wmoCode) {
    return WMO_CONDITIONS[wmoCode] || 'Desconocido';
  }

  // ═══════════════════════════════════════════════════════
  //  GeoPort — one-shot geolocation
  //  ═══════════════════════════════════════════════════════

  /**
   * Crea un GeoPort que envuelve navigator.geolocation.
   * @param {object} [deps] - dependencias inyectables (para test)
   * @param {function} [deps.geolocation] - implementación de geolocation (default: navigator.geolocation)
   * @returns {{ oneShot: function }}
   */
  function createGeoPort(deps) {
    const geo = deps && deps.geolocation ? deps.geolocation :
      (typeof navigator !== 'undefined' && navigator.geolocation ? navigator.geolocation : null);

    /**
     * Obtiene ubicación una sola vez.
     * @returns {Promise<{lat: number, lon: number}|null>}
     */
    function oneShot() {
      return new Promise((resolve) => {
        if (!geo) {
          resolve(null);
          return;
        }
        geo.getCurrentPosition(
          (pos) => {
            const lat = Math.round(pos.coords.latitude * 100) / 100;
            const lon = Math.round(pos.coords.longitude * 100) / 100;
            resolve({ lat, lon });
          },
          () => resolve(null),
          { enableHighAccuracy: false, timeout: 3000, maximumAge: 300000 }
        );
      });
    }

    return Object.freeze({ oneShot });
  }

  // ═══════════════════════════════════════════════════════
  //  WeatherPort — Open-Meteo API
  //  ═══════════════════════════════════════════════════════

  const OPEN_METEO_URL = 'https://api.open-meteo.com/v1/forecast';

  /**
   * Crea un WeatherPort que consulta Open-Meteo.
   * @param {object} [deps] - dependencias inyectables (para test)
   * @param {function} [deps.fetch] - implementación de fetch (default: global fetch)
   * @returns {{ fetch: function }}
   */
  function createWeatherPort(deps) {
    const doFetch = deps && deps.fetch ? deps.fetch :
      (typeof fetch !== 'undefined' ? fetch : null);

    /**
     * Consulta el clima actual en las coordenadas dadas.
     * @param {{ lat: number, lon: number }} coords
     * @returns {Promise<{tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt}|null>}
     */
    async function fetch(coords) {
      if (!coords || coords.lat == null || coords.lon == null) return null;
      if (!doFetch) return null;

      const url = `${OPEN_METEO_URL}?latitude=${coords.lat}&longitude=${coords.lon}` +
        `&current=temperature_2m,apparent_temperature,relative_humidity_2m,` +
        `weather_code,wind_speed_10m,uv_index` +
        `&timezone=auto`;

      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 3000);
        const res = await doFetch(url, { signal: controller.signal });
        clearTimeout(timeout);

        if (!res.ok) return null;
        const data = await res.json();
        if (!data || !data.current) return null;

        const cur = data.current;
        return {
          tempC: cur.temperature_2m,
          feelsLikeC: cur.apparent_temperature,
          condition: wmoToSpanish(cur.weather_code),
          humidityPct: cur.relative_humidity_2m,
          uvIndex: cur.uv_index,
          windKmh: cur.wind_speed_10m,
          capturedAt: new Date().toISOString(),
        };
      } catch {
        return null;
      }
    }

    return Object.freeze({ fetch });
  }

  return {
    createGeoPort,
    createWeatherPort,
    wmoToSpanish,
    WMO_CONDITIONS,
  };
}));
