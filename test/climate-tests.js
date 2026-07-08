/**
 * climate-tests.js — Climate module tests (E1)
 * Run: node test/climate-tests.js
 */
'use strict';

const { createGeoPort, createWeatherPort, wmoToSpanish } = require('../climate.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }
function assertApprox(a, b, t, m) { const ok = Math.abs(a - b) <= t; if (ok) { passed++; process.stdout.write('  ✅ ' + m + ` (${a} ≈ ${b})\n`); } else { failed++; process.stdout.write('  ❌ ' + m + ` (${a} !≈ ${b})\n`); } }

async function main() {

// ═══════════════════════════════════════════════════════
//  WMO Mapper
// ═══════════════════════════════════════════════════════
console.log('\n📋 WMO Mapper');
{
  assert(wmoToSpanish(0) === 'Despejado', '0 → Despejado');
  assert(wmoToSpanish(2) === 'Parcialmente nublado', '2 → Parcialmente nublado');
  assert(wmoToSpanish(61) === 'Lluvia ligera', '61 → Lluvia ligera');
  assert(wmoToSpanish(95) === 'Tormenta', '95 → Tormenta');
  assert(wmoToSpanish(999) === 'Desconocido', '999 → Desconocido');
}

// ═══════════════════════════════════════════════════════
//  GeoPort — mock
// ═══════════════════════════════════════════════════════
console.log('\n📋 GeoPort');
{
  // AC-1: Success
  const mockGeo = {
    getCurrentPosition(success) {
      success({ coords: { latitude: 19.4326, longitude: -99.1332 } });
    },
  };
  const port = createGeoPort({ geolocation: mockGeo });
  const pos = await port.oneShot();
  assert(pos !== null, 'position returned');
  assert(pos.lat === 19.43, `lat rounded to 2dp (got ${pos.lat})`);
  assert(pos.lon === -99.13, `lon rounded to 2dp (got ${pos.lon})`);

  // AC-2: Error → null
  const errGeo = {
    getCurrentPosition(_success, error) { error(new Error('denied')); },
  };
  const errPort = createGeoPort({ geolocation: errGeo });
  const errPos = await errPort.oneShot();
  assert(errPos === null, 'null on error');

  // AC-3: No geolocation → null
  const noPort = createGeoPort({ geolocation: null });
  const noPos = await noPort.oneShot();
  assert(noPos === null, 'null when geolocation unavailable');
}

// ═══════════════════════════════════════════════════════
//  WeatherPort — mock
// ═══════════════════════════════════════════════════════
console.log('\n📋 WeatherPort');
{
  // AC-4: Success
  const mockFetch = async (url) => {
    assert(url.includes('api.open-meteo.com'), 'calls Open-Meteo');
    assert(url.includes('latitude=19.43'), 'includes lat');
    assert(url.includes('longitude=-99.13'), 'includes lon');
    return {
      ok: true,
      json: async () => ({
        current: {
          temperature_2m: 22.5,
          apparent_temperature: 20.1,
          relative_humidity_2m: 65,
          weather_code: 2,
          wind_speed_10m: 12.3,
          uv_index: 6,
        },
      }),
    };
  };
  const port = createWeatherPort({ fetch: mockFetch });
  const weather = await port.fetch({ lat: 19.43, lon: -99.13 });
  assert(weather !== null, 'weather returned');
  assert(weather.tempC === 22.5, `tempC = 22.5 (got ${weather.tempC})`);
  assert(weather.feelsLikeC === 20.1, `feelsLikeC = 20.1`);
  assert(weather.condition === 'Parcialmente nublado', `condition = Parcialmente nublado`);
  assert(weather.humidityPct === 65, `humidityPct = 65`);
  assert(weather.uvIndex === 6, `uvIndex = 6`);
  assert(weather.windKmh === 12.3, `windKmh = 12.3`);
  assert(weather.capturedAt !== undefined, 'capturedAt set');

  // AC-5: HTTP error → null
  const errFetch = async () => ({ ok: false });
  const errPort = createWeatherPort({ fetch: errFetch });
  const errWeather = await errPort.fetch({ lat: 19.43, lon: -99.13 });
  assert(errWeather === null, 'null on HTTP error');

  // AC-6: Null coords → null
  const nullWeather = await port.fetch(null);
  assert(nullWeather === null, 'null with null coords');

  // AC-7: Missing lat → null
  const noLat = await port.fetch({ lon: -99.13 });
  assert(noLat === null, 'null with missing lat');

  // AC-8: Fetch throws → null
  const throwFetch = async () => { throw new Error('network error'); };
  const throwPort = createWeatherPort({ fetch: throwFetch });
  const throwWeather = await throwPort.fetch({ lat: 19.43, lon: -99.13 });
  assert(throwWeather === null, 'null on fetch error');

  // AC-9: No fetch → null
  const noFetchPort = createWeatherPort({ fetch: null });
  const noFetchWeather = await noFetchPort.fetch({ lat: 0, lon: 0 });
  assert(noFetchWeather === null, 'null when fetch unavailable');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  Climate: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');

}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
