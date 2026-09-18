#!/bin/bash
#
# Caminos verde y rojo de `walk-report.sh` (gate 8.4). Un informe que nadie ha visto
# fallar no demuestra nada.
#
# Fixtures de texto con la forma de `log show --style compact`. La caminata limpia es la
# fixture compartida con la app (`WalkTrackerTests/Application/MeasurementLogFixture.txt`):
# `MeasurementLogTests` afirma que `MeasurementLog` escribe exactamente esas líneas, así que
# si el formato de la app y el del informe se separan, uno de los dos lados se pone rojo.
# El resto se escriben aquí: degradada (nil, timeout y estimación), consulta menor que lo
# visto (R1, con el registro corregido y el de un build anterior que sí estimó), muestra que
# sube tras degradar (R2, con tramo desplazado, salto pequeño y dos degradadas seguidas),
# estimación omitida por cada defensa del estimador y por una razón que el informe no conoce,
# respuesta tardía tras timeout, criterio de `stepsEstimated`, huérfana,
# stream terminado (R5), varias sesiones, y registros vacío, ajeno, json, `<private>`, de otra
# versión o mal formados.
#
# No toca el dispositivo ni `log collect`.
#
# Uso:  bash Scripts/walk-report-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$SCRIPT_DIR/walk-report.sh"
SHARED_FIXTURE="$ROOT/WalkTrackerTests/Application/MeasurementLogFixture.txt"

WORK="$(mktemp -d -t walk-report-tests)" || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "  ⚠️  no se pudo crear el directorio temporal" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

OUT=""
STATUS=0
run_report() {
    OUT="$(bash "$SCRIPT" "$@" 2>&1)"
    STATUS=$?
}

# expect NOMBRE EXIT TEXTO... — EXIT "nonzero" basta con que no sea 0. Cada TEXTO debe
# aparecer literal en la salida; un TEXTO con prefijo `!` NO debe aparecer.
expect() {
    local name="$1" want="$2"
    shift 2
    if { [ "$want" = "nonzero" ] && [ "$STATUS" -eq 0 ]; } || { [ "$want" != "nonzero" ] && [ "$STATUS" -ne "$want" ]; }; then
        report_fail "$name: salió con $STATUS (esperado $want)"
        echo "$OUT" | sed 's/^/      /'
        return
    fi
    local needle
    for needle in "$@"; do
        if [ "${needle#!}" != "$needle" ]; then
            if grep -qF -- "${needle#!}" <<< "$OUT"; then
                report_fail "$name: la salida contiene '${needle#!}'"
                echo "$OUT" | sed 's/^/      /'
                return
            fi
        elif ! grep -qF -- "$needle" <<< "$OUT"; then
            report_fail "$name: la salida no contiene '$needle'"
            echo "$OUT" | sed 's/^/      /'
            return
        fi
    done
    report_pass "$name"
}

P='2027-01-15 08:00:00.000 Df WalkTracker[412:5f31] [com.walktracker.app:Medicion]'
SID=1800000000000

# ── Caminata limpia (fixture compartida con la app) ──────────────────────────
echo "Caminata limpia"
if [ ! -f "$SHARED_FIXTURE" ]; then
    report_fail "no existe la fixture compartida $SHARED_FIXTURE"
else
    run_report "$SHARED_FIXTURE"
    expect "limpia: informe completo" 0 \
        "Finalizada: sí" \
        "Duración neta: 30 min 00 s (1800 s)" \
        "Pasos: 1800 (medidos 1800 + estimados 0)" \
        "Distancia: 1200.00 m · del sistema: 1200.00 m" \
        "stepsEstimated: 0 · criterio del gate = 0: cumple" \
        "Consultas: 2 · duración máx.: 40 ms · p95: 40 ms" \
        "Desenlaces: data=2 nil=0 timeout=0 belowSeen=0 error=0" \
        "Muestras del stream: 3 · con distancia: 2 · sin distancia: 1 · alternancias: 1" \
        "Estimaciones: 0 (0 pasos) · omitidas: 0" \
        "Build: 4.0.0 (38)" \
        "Avisos: ninguno" \
        "reconciliationTimeoutS propuesto: 1 s" \
        "!R1 ·" "!R2 ·"
fi

# ── Degradada: nil, timeout sin respuesta tardía y estimación ────────────────
echo "Caminata degradada"
cat > "$WORK/degradada.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00 version=4.0.0 build=39
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=800 distance=nil
$P WTM1 event=session sid=$SID transition=background at=1800000600000 status=active elapsedS=600 measured=800 estimated=0 systemDistance=nil distance=524.00
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=nil distance=nil seen=800 ms=120 outcome=nil
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=400 skipped=nil
$P WTM1 event=session sid=$SID transition=active at=1800000900000 status=active elapsedS=900 measured=800 estimated=400 systemDistance=nil distance=786.00
$P WTM1 event=session sid=$SID transition=background at=1800001000000 status=active elapsedS=1000 measured=800 estimated=400 systemDistance=nil distance=786.00
$P WTM1 event=query sid=$SID start=$SID end=1800001200000 result=nil distance=nil seen=800 ms=3001 outcome=timeout
$P WTM1 event=estimate sid=$SID gapStart=1800001000000 gapEnd=1800001200000 steps=0 skipped=nil
$P WTM1 event=session sid=$SID transition=active at=1800001200000 status=active elapsedS=1200 measured=800 estimated=400 systemDistance=nil distance=786.00
EOF
run_report "$WORK/degradada.txt"
expect "degradada: desenlaces, estimación, timeout censurado y sesión sin finalizar" 0 \
    "Build: 4.0.0 (39)" \
    "Finalizada: no" \
    "Pasos: 1200 (medidos 800 + estimados 400)" \
    "stepsEstimated: 400 · criterio del gate = 0: NO CUMPLE" \
    "Consultas: 2 · duración máx.: 120 ms · p95: 120 ms" \
    "Desenlaces: data=0 nil=1 timeout=1 belowSeen=0 error=0" \
    "Estimaciones: 2 (400 pasos) · omitidas: 0" \
    "estimación (línea 5): 400 pasos para un gap de 5.0 min" \
    "1 consulta(s) agotaron el timeout sin respuesta tardía registrada" \
    "la sesión no está finalizada" \
    "reconciliationTimeoutS propuesto: no se propone: hay consultas con timeout sin duración real" \
    "!3001 ms" "!R2 ·"

# Timeout con respuesta tardía: la duración real sustituye a la espera censurada.
{ cat "$WORK/degradada.txt"; echo "$P WTM1 event=queryLate sid=$SID start=$SID end=1800001200000 result=950 distance=nil seen=800 ms=4200 outcome=data"; } > "$WORK/tardia.txt"
run_report "$WORK/tardia.txt"
expect "timeout con queryLate: máximo y propuesta con la duración real" 0 \
    "Consultas: 2 · duración máx.: 4200 ms" \
    "Respuestas tardías: 1 (data=1)" \
    "reconciliationTimeoutS propuesto: 21 s = max(1 s, 5 × 4200 ms)" \
    "!sin respuesta tardía"

# ── Criterio stepsEstimated ──────────────────────────────────────────────────
echo "Criterio stepsEstimated"
cat > "$WORK/descartada.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00 version=4.0.0 build=39
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=800 distance=nil
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=nil distance=nil seen=800 ms=90 outcome=nil
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=400 skipped=nil
$P WTM1 event=session sid=$SID transition=discardEstimated at=1800000910000 status=active elapsedS=910 measured=800 estimated=0 systemDistance=nil distance=524.00
$P WTM1 event=session sid=$SID transition=finish at=1800001000000 status=finished elapsedS=1000 measured=800 estimated=0 systemDistance=nil distance=524.00
EOF
run_report "$WORK/descartada.txt"
expect "estimados descartados no cumplen aunque el final sea 0" 0 \
    "stepsEstimated: 0 · criterio del gate = 0: NO CUMPLE (estimados descartados)"

grep -v "transition=finish" "$SHARED_FIXTURE" > "$WORK/sin-finalizar.txt"
run_report "$WORK/sin-finalizar.txt"
expect "sesión sin finalizar no cumple" 0 "criterio del gate = 0: NO CUMPLE (sesión sin finalizar)"

grep "event=sample" "$SHARED_FIXTURE" > "$WORK/solo-muestras.txt"
run_report "$WORK/solo-muestras.txt"
expect "sin transiciones el criterio queda sin datos" 0 "stepsEstimated: — · criterio del gate = 0: sin datos" "!NO CUMPLE" "Duración neta: — "

# ── R1: consulta menor que lo visto ──────────────────────────────────────────
echo "Consulta menor que lo visto"
# El registro del build corregido: la consulta se aplica como dato, no hay estimación, y la
# muestra siguiente del mismo tramo sube por encima de lo visto sin que eso sea un aviso R2
# (`belowSeen` está fuera de DEGRADED justo por esto).
cat > "$WORK/below-seen.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00 version=4.0.0 build=39
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=300 distance=200.00
$P WTM1 event=session sid=$SID transition=background at=1800000600000 status=active elapsedS=600 measured=300 estimated=0 systemDistance=200.00 distance=200.00
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=120 distance=50.00 seen=300 ms=55 outcome=belowSeen
$P WTM1 event=sample sid=$SID start=$SID end=1800000905000 steps=500 distance=330.00
$P WTM1 event=session sid=$SID transition=active at=1800000900000 status=active elapsedS=900 measured=500 estimated=0 systemDistance=330.00 distance=330.00
$P WTM1 event=session sid=$SID transition=finish at=1800000900000 status=finished elapsedS=900 measured=500 estimated=0 systemDistance=330.00 distance=330.00
EOF
run_report "$WORK/below-seen.txt"
expect "belowSeen: aviso R1 con la diferencia, se aplica como dato y sin aviso R2" 0 \
    "R1 · consulta menor que lo visto (línea 4): result=120 < seen=300 (−180 pasos); se aplica como dato y no se estima" \
    "Desenlaces: data=0 nil=0 timeout=0 belowSeen=1 error=0" \
    "!R2 ·" \
    "!registro anterior a la corrección"

# Registro de un build anterior a la corrección (≤ 86): tras el `belowSeen` sí estimó.
cat > "$WORK/below-seen-antiguo.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00 version=4.0.0 build=39
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=300 distance=200.00
$P WTM1 event=session sid=$SID transition=background at=1800000600000 status=active elapsedS=600 measured=300 estimated=0 systemDistance=200.00 distance=200.00
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=120 distance=50.00 seen=300 ms=55 outcome=belowSeen
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=150 skipped=nil
$P WTM1 event=session sid=$SID transition=active at=1800000900000 status=active elapsedS=900 measured=300 estimated=150 systemDistance=200.00 distance=298.25
$P WTM1 event=session sid=$SID transition=finish at=1800000900000 status=finished elapsedS=900 measured=300 estimated=150 systemDistance=200.00 distance=298.25
EOF
run_report "$WORK/below-seen-antiguo.txt"
expect "belowSeen que estimó: el aviso R1 dice que el registro es anterior a la corrección" 0 \
    "R1 · consulta menor que lo visto (línea 4): result=120 < seen=300 (−180 pasos); degradó al estimador y estimó pasos: registro anterior a la corrección" \
    "estimación (línea 5): 150 pasos" \
    "!se aplica como dato y no se estima"

# Una estimación de 0 pasos tras el `belowSeen` no es el registro antiguo: no degradó.
sed "s/steps=150 skipped=nil/steps=0 skipped=nil/" "$WORK/below-seen-antiguo.txt" > "$WORK/below-seen-cero.txt"
run_report "$WORK/below-seen-cero.txt"
expect "belowSeen con una estimación de 0 pasos sigue siendo el registro corregido" 0 \
    "se aplica como dato y no se estima" \
    "!registro anterior a la corrección"

# ── R2: el stream sube tras una consulta degradada ───────────────────────────
echo "Doble cuenta tras degradar (R2)"
cat > "$WORK/r2.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=800 distance=nil
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=nil distance=nil seen=800 ms=80 outcome=nil
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=400 skipped=nil
$P WTM1 event=sample sid=$SID start=1800000950000 end=1800000990000 steps=5000 distance=nil
$P WTM1 event=sample sid=$SID start=$SID end=1800000905000 steps=1210 distance=nil
$P WTM1 event=session sid=$SID transition=finish at=1800001000000 status=finished elapsedS=1000 measured=1210 estimated=400 systemDistance=nil distance=1054.55
EOF
run_report "$WORK/r2.txt"
expect "R2: la primera muestra del mismo tramo que sube, con los estimados entre medias" 0 \
    "R2 · tras la consulta nil (línea 3, seen=800) el stream sube a 1210 (+410, línea 6) con 400 pasos estimados entre medias: posible doble cuenta" \
    "!+4200"

# El startDate de CoreMotion puede no coincidir al milisegundo con el inicio del tramo.
sed "s/start=$SID end=1800000905000/start=1800000000300 end=1800000905000/" "$WORK/r2.txt" > "$WORK/r2-desplazada.txt"
run_report "$WORK/r2-desplazada.txt"
expect "R2 con el inicio de la muestra desplazado 300 ms" 0 "el stream sube a 1210 (+410, línea 6)"

# Un salto menor que la mitad de lo estimado es caminar: se informa sin etiqueta.
sed "s/steps=1210 distance=nil/steps=900 distance=nil/" "$WORK/r2.txt" > "$WORK/r2-pequeno.txt"
run_report "$WORK/r2-pequeno.txt"
expect "R2 con salto pequeño: sin 'posible doble cuenta'" 0 "el stream sube a 900 (+100, línea 6) con 400 pasos estimados entre medias" "!posible doble cuenta"

# Dos consultas degradadas seguidas: cada una solo mira sus muestras.
cat > "$WORK/r2-dos.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00
$P WTM1 event=sample sid=$SID start=$SID end=1800000600000 steps=800 distance=nil
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=nil distance=nil seen=800 ms=80 outcome=nil
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=400 skipped=nil
$P WTM1 event=query sid=$SID start=$SID end=1800001200000 result=nil distance=nil seen=800 ms=70 outcome=nil
$P WTM1 event=estimate sid=$SID gapStart=1800000900000 gapEnd=1800001200000 steps=0 skipped=nil
$P WTM1 event=sample sid=$SID start=$SID end=1800001205000 steps=1500 distance=nil
$P WTM1 event=session sid=$SID transition=finish at=1800001300000 status=finished elapsedS=1300 measured=1500 estimated=400 systemDistance=nil distance=1244.50
EOF
run_report "$WORK/r2-dos.txt"
expect "dos degradadas seguidas: la muestra se atribuye solo a la segunda" 0 \
    "R2 · tras la consulta nil (línea 5, seen=800) el stream sube a 1500" \
    "!(línea 3, seen=800) el stream sube"

# Sin degradación, una muestra que sube es caminar: no hay aviso R2.
run_report "$SHARED_FIXTURE"
expect "sin consulta degradada no hay aviso R2" 0 "!R2 ·"

# Estimación omitida porque el stream avanzó durante la consulta.
cat > "$WORK/omitida.txt" <<EOF
$P WTM1 event=session sid=$SID transition=start at=$SID status=active elapsedS=0 measured=0 estimated=0 systemDistance=nil distance=0.00
$P WTM1 event=sample sid=$SID start=$SID end=1800000905000 steps=1210 distance=nil
$P WTM1 event=query sid=$SID start=$SID end=1800000900000 result=nil distance=nil seen=800 ms=500 outcome=timeout
$P WTM1 event=estimate sid=$SID gapStart=1800000600000 gapEnd=1800000900000 steps=0 skipped=streamAdvanced
$P WTM1 event=session sid=$SID transition=finish at=1800001000000 status=finished elapsedS=1000 measured=1210 estimated=0 systemDistance=nil distance=792.55
EOF
run_report "$WORK/omitida.txt"
expect "estimación omitida por streamAdvanced se muestra y no cuenta como estimación" 0 \
    "Estimaciones: 0 (0 pasos) · omitidas: 1" \
    "estimación omitida (línea 4): streamAdvanced; los pasos medidos crecieron desde el inicio del gap"

# Cada defensa del estimador imprime su propia explicación: un 0 en el registro tiene que
# decir qué lo cortó, no solo que salió 0.
skip_case() {
    sed "s/skipped=streamAdvanced/skipped=$1/" "$WORK/omitida.txt" > "$WORK/omitida-$1.txt"
    run_report "$WORK/omitida-$1.txt"
    expect "estimación omitida por $1 imprime su explicación" 0 \
        "estimación omitida (línea 4): $1; $2" \
        "!los pasos medidos crecieron desde el inicio del gap"
}
skip_case gapAboveCap "el gap supera el tope estimable"
skip_case noPriorSample "menos de 120 s de sesión al abrir el gap: la cadencia aún no es representativa"
skip_case notActive "la sesión dejó de estar activa durante la reconciliación"
skip_case noCadence "no salió cadencia con la que estimar (sin pasos medidos o gap no positivo)"

# Una razón que este informe no conozca se imprime tal cual, sin frase inventada.
sed "s/skipped=streamAdvanced/skipped=razonFutura/" "$WORK/omitida.txt" > "$WORK/omitida-desconocida.txt"
run_report "$WORK/omitida-desconocida.txt"
expect "una razón desconocida se imprime tal cual y sin frase" 0 \
    "estimación omitida (línea 4): razonFutura" \
    "!razonFutura;"

# ── Huérfana y stream terminado ──────────────────────────────────────────────
echo "Huérfana y stream terminado"
cat > "$WORK/huerfana.txt" <<EOF
$P WTM1 event=session sid=$SID transition=orphan at=1800002400000 status=finished elapsedS=2400 measured=4000 estimated=0 systemDistance=nil distance=2620.00
EOF
run_report "$WORK/huerfana.txt"
expect "huérfana cerrada al relanzar cuenta como finalizada" 0 "Finalizada: sí" "transiciones: orphan"

sed "s/transition=background at=1800000600000/transition=streamEnded at=1800000600000/" "$SHARED_FIXTURE" > "$WORK/stream-terminado.txt"
run_report "$WORK/stream-terminado.txt"
expect "stream terminado por el sistema da el aviso R5" 0 "R5 · el sistema terminó el stream"

# ── Varias sesiones ──────────────────────────────────────────────────────────
# La segunda sesión, desplazada +9000 s entera (sid, start, end y at), para que sus
# duraciones sean coherentes.
{ cat "$SHARED_FIXTURE"; perl -pe 's/\b(18\d{11})\b/$1 + 9000000/ge' "$WORK/below-seen.txt"; } > "$WORK/dos.txt"
run_report "$WORK/dos.txt"
expect "varias sesiones: cada una con su propuesta de timeout" 0 \
    "el registro contiene 2 sesiones" \
    "sid=1800009000000" \
    "reconciliationTimeoutS propuesto: 1 s = max(1 s, 5 × 40 ms)" \
    "reconciliationTimeoutS propuesto: 1 s = max(1 s, 5 × 55 ms)" \
    "de reloj: 15 min 00 s" \
    "!min -"

# Una duración negativa (reloj hacia atrás) no se imprime.
sed "s/transition=finish at=1800001800000/transition=finish at=1799999000000/" "$SHARED_FIXTURE" > "$WORK/negativa.txt"
run_report "$WORK/negativa.txt"
expect "duración de reloj negativa se muestra como —" 0 "de reloj: —" "!: -"

# ── Registros que no sirven ──────────────────────────────────────────────────
echo "Registros vacíos o ajenos"
: > "$WORK/vacio.txt"
run_report "$WORK/vacio.txt"
expect "registro vacío falla con un mensaje claro" nonzero "no tiene ninguna línea de medición" "!Informe de la caminata"

cat > "$WORK/ajeno.txt" <<'EOF'
Timestamp               Ty Process[PID:TID]
2027-01-15 08:00:00.000 Df SpringBoard[55:9a] [com.apple.springboard:Icon] Reloading icons
2027-01-15 08:00:01.000 Df WalkTracker[412:5f31] [com.walktracker.app:SessionStore] Sesión recuperada: active
EOF
run_report "$WORK/ajeno.txt"
expect "registro ajeno falla con un mensaje claro" nonzero "no tiene ninguna línea de medición"

printf '%s WTM1 event=sample sid=%s start=%s end=<private> steps=<private> distance=<private>\n' "$P" "$SID" "$SID" > "$WORK/privado.txt"
run_report "$WORK/privado.txt"
expect "valores <private> fallan y dicen por qué" nonzero "<private>"

printf '%s WTM2 event=sample sid=%s\n' "$P" "$SID" > "$WORK/v2.txt"
run_report "$WORK/v2.txt"
expect "formato de otra versión se rechaza" nonzero "formato WTM2 desconocido"

printf '%s WTM1 event=query sid=%s start=%s end=1 result=9 seen=1 ms=4 outcome=data\n' "$P" "$SID" "$SID" > "$WORK/incompleta.txt"
run_report "$WORK/incompleta.txt"
expect "línea sin una clave falla nombrándola" nonzero "le faltan distance"

printf '%s WTM1 event=sample sid=%s start=%s end=1 steps=muchos distance=nil\n' "$P" "$SID" "$SID" > "$WORK/tipo.txt"
run_report "$WORK/tipo.txt"
expect "valor no numérico falla" nonzero "'steps' no es un entero"

printf '[{\n  "eventMessage" : "WTM1 event=sample sid=%s start=%s end=1 steps=1 distance=nil"\n}]\n' "$SID" "$SID" > "$WORK/json.txt"
run_report "$WORK/json.txt"
expect "estilo json se rechaza con un mensaje claro" nonzero "estilo json/ndjson"

printf '%s WTM1 event=toString sid=%s\n' "$P" "$SID" > "$WORK/prototipo.txt"
run_report "$WORK/prototipo.txt"
expect "evento con nombre de propiedad de Object falla con mensaje claro" nonzero "evento desconocido 'toString'" "!TypeError"

run_report "$WORK/no-existe.txt"
expect "fichero inexistente falla" nonzero "no existe"

mkdir -p "$WORK/falso.logarchive"
if command -v log >/dev/null 2>&1; then
    run_report "$WORK/falso.logarchive"
    expect "un .logarchive ilegible falla sin informe" nonzero "!Informe de la caminata"
fi

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
[ "$fail" -eq 0 ]
