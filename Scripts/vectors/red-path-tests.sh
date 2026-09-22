#!/bin/bash
#
# Camino rojo del arnés JS de AD-6 (`run-js.js` y `check-inventory.js`). Un gate sin
# prueba de su camino rojo no es un gate: es un script que nadie ha visto fallar.
#
# Cada caso copia los vectores y el inventario a un directorio temporal, aplica UNA
# mutación y afirma el código de salida Y el mensaje. El árbol real solo se lee:
# los scripts reciben la copia por `--vectors`. Cubre las filas de la matriz de la
# 8.7 que son del lado JS: vector roto, divergencia esperada, divergencia obsoleta,
# divergente que falla fuera de su familia, e inventario incompleto o duplicado.
# Y los escenarios portados: una cita borrada o un sitio citado reasignado.
#
# Uso:  bash Scripts/vectors/red-path-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VECTORS="$ROOT/WalkTrackerTests/Vectors"
RUN_JS="$SCRIPT_DIR/run-js.js"
CHECK_INVENTORY="$SCRIPT_DIR/check-inventory.js"

WORK="$(mktemp -d -t red-path-tests)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# Copia fresca de los vectores para un caso. Devuelve su ruta.
fresh_copy() {
    local dir="$WORK/$1"
    rm -rf "$dir"
    cp -R "$VECTORS" "$dir"
    echo "$dir"
}

# Aplica una mutación JS a un fichero JSON: `d` es el documento ya parseado.
mutate() {
    local file="$1" body="$2"
    node -e '
        const fs = require("fs");
        const file = process.argv[1];
        const d = JSON.parse(fs.readFileSync(file, "utf8"));
        (new Function("d", process.argv[2]))(d);
        fs.writeFileSync(file, JSON.stringify(d, null, 2));
    ' "$file" "$body"
}

# assert_run NOMBRE EXIT_ESPERADO TEXTO_ESPERADO -- SCRIPT [ARGS...]
# Con EXIT_ESPERADO "nonzero" basta con que no sea 0: lo que se afirma es el rojo.
assert_run() {
    local name="$1" want="$2" needle="$3"
    shift 4
    local out status
    out="$(node "$@" 2>&1)"
    status=$?

    if { [ "$want" = "nonzero" ] && [ "$status" -eq 0 ]; } || { [ "$want" != "nonzero" ] && [ "$status" -ne "$want" ]; }; then
        report_fail "$name — esperado exit $want, obtenido $status"
        echo "$out" | sed 's/^/      /' | tail -8
        return
    fi
    if ! grep -qF -- "$needle" <<< "$out"; then
        report_fail "$name — exit $status correcto, pero la salida no menciona: $needle"
        echo "$out" | sed 's/^/      /' | tail -8
        return
    fi
    report_pass "$name"
}

# Huella del árbol real antes de empezar: al final tiene que ser idéntica.
fingerprint() { (cd "$VECTORS" && shasum *.json; shasum "$ROOT/WalkTracker/Resources/achievements.json"); }
BEFORE="$(fingerprint)"

echo "Camino rojo del arnés JS de AD-6"

# ── Árbol real, intacto ──────────────────────────────────────────────────────
assert_run "árbol real: run-js en verde" 0 "run-js: " \
    -- "$RUN_JS" --vectors "$VECTORS"
assert_run "árbol real: check-inventory en verde" 0 "Cada sitio, una vez." \
    -- "$CHECK_INVENTORY" --vectors "$VECTORS"

# ── Vector no divergente roto ────────────────────────────────────────────────
dir="$(fresh_copy broken)"
mutate "$dir/pace.json" 'd.vectors.find(v => v.id === "3370m-en-62min-con-2min-de-pausa").expected = 1069;'
assert_run "vector no divergente con valor esperado erróneo rompe y nombra fichero#id" nonzero "pace.json#3370m-en-62min-con-2min-de-pausa: esperado 1069, domain.js da 1068" \
    -- "$RUN_JS" --vectors "$dir"

# ── Divergencia declarada que JS falla: sale 0 y se informa ──────────────────
dir="$(fresh_copy expected-divergence)"
mutate "$dir/checkTimeOfDay.json" '
    d.vectors.push({
        id: "sonda-divergente", sources: [], divergence: "localTime", timeZone: "America/Guayaquil",
        input: { startedAt: "2026-07-08T05:30:00-05:00", hourStart: 5, hourEnd: 7 }, expected: true, expectedJs: false
    });'
assert_run "divergencia declarada que domain.js falla sale 0 y se informa como esperada" 0 "≈ checkTimeOfDay.json#sonda-divergente [localTime]: domain.js da false; el vector lleva true" \
    -- "$RUN_JS" --vectors "$dir"

# ── Divergencia obsoleta ─────────────────────────────────────────────────────
dir="$(fresh_copy obsolete-divergence)"
mutate "$dir/evaluateAchievements.json" 'd.vectors.find(v => v.id === "lluvia-wmo-51-llovizna").divergence = "wmoCategory";'
assert_run "vector marcado divergente que domain.js pasa rompe: la divergencia ya no existe" nonzero "evaluateAchievements.json#lluvia-wmo-51-llovizna: marcado divergente (wmoCategory) pero domain.js lo pasa: la divergencia ya no existe" \
    -- "$RUN_JS" --vectors "$dir"

# ── Divergente de logros que además difiere fuera de su familia ──────────────
dir="$(fresh_copy foreign-diff)"
mutate "$dir/evaluateAchievements.json" 'd.vectors.find(v => v.id === "madrugador-05-00-local-guayaquil").expected.newlyUnlocked = ["early_bird", "first_km"];'
assert_run "divergente de hora local que también difiere en first_km rompe" nonzero "evaluateAchievements.json#madrugador-05-00-local-guayaquil: divergente (localTime), pero domain.js también difiere en first_km" \
    -- "$RUN_JS" --vectors "$dir"

# ── Inventario incompleto ────────────────────────────────────────────────────
dir="$(fresh_copy inventory-missing)"
mutate "$dir/inventory.json" 'd.sites = d.sites.filter(s => s.site !== "test/gapestimator-tests.js:21");'
assert_run "inventario sin un sitio rompe y nombra fichero:línea" nonzero "test/gapestimator-tests.js:21: sitio de aserción que falta en el inventario" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Inventario duplicado ─────────────────────────────────────────────────────
dir="$(fresh_copy inventory-duplicate)"
mutate "$dir/inventory.json" 'd.sites.push({ ...d.sites.find(s => s.site === "test/motivation-tests.js:55") });'
assert_run "inventario con un sitio duplicado rompe y nombra fichero:línea" nonzero "test/motivation-tests.js:55: aparece 2 veces en el inventario" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Inventario: código de un sitio cambiado ─────────────────────────────────
dir="$(fresh_copy inventory-code)"
mutate "$dir/inventory.json" 'd.sites.find(s => s.site === "test/gapestimator-tests.js:21").code = "assert(steps === 401, \"otro\");";'
assert_run "inventario con el código de un sitio cambiado rompe" nonzero "test/gapestimator-tests.js:21: el código no coincide" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Inventario: excluido sin motivo ──────────────────────────────────────────
dir="$(fresh_copy inventory-reason)"
mutate "$dir/inventory.json" 'delete d.sites.find(s => s.site === "test/motivation-tests.js:45").reason;'
assert_run "excluido sin motivo rompe" nonzero "test/motivation-tests.js:45: excluido sin motivo admitido" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Inventario: ejecuciones mal declaradas en el sitio del bucle ─────────────
dir="$(fresh_copy inventory-executions)"
mutate "$dir/inventory.json" 'd.sites.find(s => s.site === "test/session-v3-tests.js:345").executions = 99;'
assert_run "executions erróneas en session-v3-tests.js:345 rompen contra la suite real" nonzero \
    "test/session-v3-tests.js: la suite ejecuta 184 aserciones y el inventario declara 183" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Escenarios portados: una cita borrada ───────────────────────────────────
dir="$(fresh_copy scenario-citation-removed)"
cp -R "$ROOT/WalkTrackerTests/Scenarios" "$dir/Scenarios"
sed -i '' 's/@Test("session-v3-tests.js:73 · /@Test("/' "$dir/Scenarios/SessionStartScenarios.swift"
assert_run "escenario de la 1.1 sin @Test que lo cite rompe" nonzero \
    "test/session-v3-tests.js:73: escenario de la 1.1 sin ningún @Test que lo cite" \
    -- "$CHECK_INVENTORY" --vectors "$dir" --scenarios "$dir/Scenarios"

# ── Escenarios portados: un sitio citado reasignado a otra historia ─────────
dir="$(fresh_copy scenario-retagged)"
mutate "$dir/inventory.json" 'd.sites.find(s => s.site === "test/session-v3-tests.js:73").story = "1.3";'
assert_run "cita de la 1.1 a un sitio reasignado a la 1.3 rompe" nonzero \
    "cita test/session-v3-tests.js:73 como escenario de la 1.1, pero escenario de la 1.3" \
    -- "$CHECK_INVENTORY" --vectors "$dir"

# ── Cobertura: un logro sin ningún vector que lo cubra ───────────────────────
dir="$(fresh_copy coverage)"
mutate "$dir/evaluateAchievements.json" 'd.vectors.forEach(v => { if (v.covers) delete v.covers.hot_walker; });'
assert_run "quitar toda la cobertura de hot_walker rompe" nonzero "cobertura: ningún vector desbloquea 'hot_walker'" \
    -- "$RUN_JS" --vectors "$dir"

# ── Catálogo: nombre e icono cambiados en una copia de achievements.json ─────
dir="$(fresh_copy catalog-name)"
cp "$ROOT/WalkTracker/Resources/achievements.json" "$dir/catalog.json"
mutate "$dir/catalog.json" 'd.achievements.find(a => a.key === "first_5km").name = "5 kilómetros";'
assert_run "achievements.json con un name cambiado rompe" nonzero "achievements.json#first_5km: name '5 kilómetros' ≠ referencia 'Cinco kilómetros'" \
    -- "$RUN_JS" --vectors "$VECTORS" --catalog "$dir/catalog.json"
cp "$ROOT/WalkTracker/Resources/achievements.json" "$dir/catalog.json"
mutate "$dir/catalog.json" 'd.achievements.find(a => a.key === "hot_walker").icon = "🔆";'
assert_run "achievements.json con un icon cambiado rompe" nonzero "achievements.json#hot_walker: icon '🔆'" \
    -- "$RUN_JS" --vectors "$VECTORS" --catalog "$dir/catalog.json"

# ── Catálogo: la divergencia de texto declarada (early_bird · description) ───
# Los cinco casos de la matriz del chore de `early_bird`. El primero es el único caso
# VERDE que este arnés tiene para el catálogo: hasta aquí solo había rojos, y una
# excepción que nadie ve pasar en verde no está probada.

# (a) Con la divergencia declarada, el texto decidido pasa Y se imprime.
assert_run "la divergencia declarada de early_bird·description pasa y se imprime" 0 \
    "≠ early_bird · description — declarada el 2026-09-20" \
    -- "$RUN_JS" --vectors "$VECTORS"

# (b) La excepción es por LOGRO: el mismo campo en otro logro sigue rompiendo.
dir="$(fresh_copy catalog-divergence)"
cp "$ROOT/WalkTracker/Resources/achievements.json" "$dir/catalog.json"
mutate "$dir/catalog.json" 'd.achievements.find(a => a.key === "first_5km").description = "Completa 5 km de golpe";'
assert_run "description cambiada en OTRO logro rompe: la excepción es por logro" nonzero \
    "achievements.json#first_5km: description 'Completa 5 km de golpe' ≠ referencia 'Completa 5 km en una sesión'" \
    -- "$RUN_JS" --vectors "$VECTORS" --catalog "$dir/catalog.json"

# (b) Y por CAMPO: `name` de early_bird no está exento.
cp "$ROOT/WalkTracker/Resources/achievements.json" "$dir/catalog.json"
mutate "$dir/catalog.json" 'd.achievements.find(a => a.key === "early_bird").name = "Madrugadora";'
assert_run "name cambiado en early_bird rompe: la excepción es por campo" nonzero \
    "achievements.json#early_bird: name 'Madrugadora' ≠ referencia 'Madrugador'" \
    -- "$RUN_JS" --vectors "$VECTORS" --catalog "$dir/catalog.json"

# Bidireccional, como el inventario de suites de B-6: revertido al texto viejo, la
# divergencia declarada ya no se cumple y el gate pide que se borre.
cp "$ROOT/WalkTracker/Resources/achievements.json" "$dir/catalog.json"
mutate "$dir/catalog.json" 'd.achievements.find(a => a.key === "early_bird").description = "Camina antes de las 7:00";'
assert_run "revertir el texto deja la divergencia declarada sobrante y rompe" nonzero \
    "achievements.json#early_bird: description vuelve a coincidir con la referencia" \
    -- "$RUN_JS" --vectors "$VECTORS" --catalog "$dir/catalog.json"

# Una entrada sin fecha o sin razón no es una decisión declarada. Es lo único que no se
# puede mutar por `--catalog`: la lista vive DENTRO del gate. Así que se muta una COPIA
# del script y se le pasa `--root` para que siga encontrando la referencia v3 del árbol
# real. La mutación falla ruidosamente si no encuentra el campo: un caso rojo que se
# vuelve no-op sin avisar no prueba nada.
mutate_run_js() {
    local dest="$1" pattern="$2" replacement="$3"
    mkdir -p "$dest"
    cp "$RUN_JS" "$SCRIPT_DIR/lib.js" "$dest/"
    node -e '
        const fs = require("fs");
        const file = process.argv[1];
        const before = fs.readFileSync(file, "utf8");
        const after = before.replace(new RegExp(process.argv[2]), process.argv[3]);
        if (after === before) {
            console.error(`mutate_run_js: el patrón ${process.argv[2]} no casó con nada en ${file}`);
            process.exit(1);
        }
        fs.writeFileSync(file, after);
    ' "$dest/run-js.js" "$pattern" "$replacement"
}

sdir="$WORK/divergence-no-reason"
if mutate_run_js "$sdir" "reason: 'La v3[\\s\\S]*?'," "reason: '',"; then
    assert_run "divergencia declarada sin razón rompe" nonzero "sin razón escrita" \
        -- "$sdir/run-js.js" --root "$ROOT" --vectors "$VECTORS"
else
    report_fail "divergencia declarada sin razón — no se pudo mutar la lista de run-js.js"
fi

sdir="$WORK/divergence-no-date"
if mutate_run_js "$sdir" "date: '2026-09-20'," "date: ''," ; then
    assert_run "divergencia declarada sin fecha rompe" nonzero "sin fecha (AAAA-MM-DD)" \
        -- "$sdir/run-js.js" --root "$ROOT" --vectors "$VECTORS"
else
    report_fail "divergencia declarada sin fecha — no se pudo mutar la lista de run-js.js"
fi

# ── Divergente fuera de logros con expectedJs que no casa ────────────────────
dir="$(fresh_copy expected-js)"
mutate "$dir/weeklyProgress.json" 'd.vectors.find(v => v.id === "ahora-lunes-00-00-local").expectedJs.goalKm = 12;'
assert_run "divergente de weeklyProgress con expectedJs erróneo rompe" nonzero \
    "weeklyProgress.json#ahora-lunes-00-00-local: divergente (localTime), pero domain.js da" \
    -- "$RUN_JS" --vectors "$dir"

dir="$(fresh_copy expected-js-missing)"
mutate "$dir/checkStreak.json" 'delete d.vectors.find(v => v.id === "racha-local-que-utc-no-ve").expectedJs;'
assert_run "divergente de checkStreak sin expectedJs rompe" nonzero \
    "checkStreak.json#racha-local-que-utc-no-ve: divergente (localTime) sin \"expectedJs\"" \
    -- "$RUN_JS" --vectors "$dir"

# ── El árbol real sigue intacto ──────────────────────────────────────────────
if [ "$(fingerprint)" = "$BEFORE" ]; then
    report_pass "los vectores reales no se tocaron"
else
    report_fail "los vectores reales cambiaron durante la prueba"
fi

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"
[ "$fail" -eq 0 ]
