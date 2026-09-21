#!/bin/bash
#
# Forma de las specs y del registro de trabajo diferido (A-7 de la retro del Epic 1).
#
# El defecto que cierra: las dos reglas de la lección de specs se decidieron
# **verificables, no convención**, y el check nunca se escribió. Vivían como
# `persistent_facts` en `_bmad/custom/bmad-build.toml` y se aplicaban a mano, así que
# llevaban incumpliéndose desde el principio sin que nadie se enterara — medido el
# 2026-09-21 sobre el árbol: 14 de las 18 specs que tocan `SessionStore` en su Code Map
# no listaban los campos compartidos, y 27 de las 54 entradas de `deferred-work.md` no
# declaraban destino de forma reconocible a máquina.
#
# Las dos reglas:
#
#   (a) Toda entrada de `deferred-work.md` declara su destino con la forma canónica
#       `Destino:` (D3 del A-7) — además de tener sus tres campos y de apuntar a un
#       `source_spec` que exista. Una entrada marcada `**CERRADO` al principio del
#       `summary` no necesita destino: ya no hay trabajo que asignar.
#   (b) Una spec cuyo `## Code Map` menciona `SessionStore` lista ahí los campos
#       compartidos del store y sus invariantes, en una línea en negrita que empieza por
#       `**Campos compartidos`.
#
# Lo que este gate SÍ comprueba: **forma**. Lo que NO, y por eso no lo anuncia: la otra
# mitad de la regla (a) —"una spec que difiere trabajo TIENE su entrada"— no es
# mecanizable sin adivinar intención. Se midió: `spec-8-4` dispara todas las señales de
# prosa y no tiene entrada; `spec-r1` no dispara ninguna y sí la tiene. Un gate sobre eso
# daría rojos y verdes falsos, que es justo el defecto que B-5/B-6 cerraron. Esa mitad
# vive donde único puede: en el `persistent_facts` que el agente lee al escribir la spec.
# LÍMITES CONOCIDOS, declarados aquí para no prometer de más (B-5). Los tres están
# registrados en `deferred-work.md` con su `Destino:`, porque este chore también se aplica
# su propia regla (a):
#   1. La regla (b) comprueba que la línea EXISTE, no lo que dice: una spec puede escribir
#      `**Campos compartidos**: los de siempre` y pasar. Caza el olvido, no la desgana.
#   2. La regla (a) comprueba que hay `Destino:` con algo detrás, no que ese algo sea un
#      dueño real: `Destino: por decidir, hoy sin dueño` pasa. Dos de las 52 entradas
#      vivas dicen justamente eso (`hoy sin dueño`, `hoy sin epic asignado`), y es
#      honesto que se vean así en vez de inventarles un epic.
#   3. NADA comprueba que este gate llegue a ejecutarse. Lo invoca `workflow.on_complete`
#      de `_bmad/custom/bmad-build.toml`; si la skill renombra ese escalar, el override
#      del proyecto se vuelve un no-op silencioso y el gate deja de correr sin un solo
#      rojo. El check es mecánico; la EJECUCIÓN sigue siendo un prompt.
#
# **No se engancha a ninguna `preBuildScript`.** Estas reglas son sobre documentos: una
# spec a medio escribir no puede tumbar el build de la app, porque la consecuencia
# previsible es que alguien desactive el gate, y un gate desactivado es peor que ninguno.
# Lo invoca el `on_complete` del workflow de `bmad-build` (`_bmad/custom/bmad-build.toml`).
#
# Uso:  bash Scripts/check-spec-shape.sh [raíz]
# La raíz por argumento existe para que su arnés (`check-spec-shape-tests.sh`) lo apunte a
# un árbol temporal y NUNCA al repositorio.

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ARTIFACTS="$ROOT/_bmad-output/implementation-artifacts"
DEFERRED="$ARTIFACTS/deferred-work.md"

fail_count=0

# Formato `fichero:línea: error:`, el mismo contrato de salida que `check-project-shape.sh`.
err() {
    echo "$1: error: $2" >&2
    fail_count=$((fail_count + 1))
}

section() { printf '\n── %s ─────────────────────────────────────────\n' "$1"; }

# ── Exenciones declaradas de la regla (b) ────────────────────────────────────
# Decisión D1 de Paul (2026-09-21): la regla (b) corre sobre TODO el corpus, y las specs
# que ya estaban cerradas cuando se escribió el gate se nombran UNA A UNA aquí, con fecha
# y razón. No hay exenciones implícitas: el gate imprime esta lista cada vez que corre.
#
# Razón, la misma para las 14: la regla (b) solo tiene valor PROSPECTIVO —enumerar los
# campos compartidos evita que la SIGUIENTE historia los pise—. Sobre una spec ya cerrada
# el valor es cero y el riesgo de inventar contenido retroactivo es real. Es el mismo
# patrón que las divergencias declaradas de AD-6 y la excepción de tres colorsets de AD-13.
#
# La exención cubre a estas 14, no a la regla: una spec nueva que toque `SessionStore` sin
# listar los campos entra en rojo. Y si alguien rellena una de las exentas, el gate también
# se pone rojo pidiendo que se borre su línea de aquí — una exención que ya no hace falta
# es tan mentira como una invisible.
#
# Formato: fichero|fecha|razón
EXEMPT_RULE_B=(
    "spec-1-2-conteo-pasos-coprocesador.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-1-3-metricas-en-vivo.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-1-4-pausar-reanudar-finalizar.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-1-5-reconstruccion-background.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-1-6-recuperacion-foreground.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-2-2-frase-motivacional.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-2-3-recalibracion-zancada.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-5-1-persistencia-sesiones.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-8-4-gate-success-signal.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-a5-reconciliar-planificacion.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-b1-ajustes-no-se-pisan.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-b5-b6-gates-honestos.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-b9-degradacion-y-atribucion.md|2026-09-21|cerrada (status: done) antes del A-7"
    "spec-retro-e1-a6-gates-arquitectura.md|2026-09-21|cerrada (status: done) antes del A-7"
)

# Estado de cada exención en ESTE árbol: `ausente` (la spec no está aquí), `vigente` (la
# spec sigue sin listar los campos) o `sobrante` (ya los lista: la línea debe borrarse).
exempt_state=()
i=0
while [ "$i" -lt "${#EXEMPT_RULE_B[@]}" ]; do
    exempt_state[$i]="ausente"
    i=$((i + 1))
done

# Índice de la exención de una spec, o vacío si no está exenta.
exempt_index() {
    local i=0
    while [ "$i" -lt "${#EXEMPT_RULE_B[@]}" ]; do
        if [ "${EXEMPT_RULE_B[$i]%%|*}" = "$1" ]; then
            echo "$i"
            return
        fi
        i=$((i + 1))
    done
}

# ── Camino rojo propio, ANTES de gatear nada ─────────────────────────────────
# El molde es `verify-domain.sh`, que ejecuta su arnés antes de mirar el árbol: un gate
# cuyo camino rojo nadie corre acaba siendo otro script que nadie recuerda, y ése es el
# defecto que B-5/B-6 cerraron. Solo cuando se invoca SIN raíz, porque el arnés siempre
# pasa una: así no hay recursión y no hace falta un flag nuevo.
if [ $# -eq 0 ]; then
    section "Camino rojo del propio gate"
    HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-spec-shape-tests.sh"
    if [ ! -f "$HARNESS" ]; then
        err "$HARNESS:1" "no existe el arnés del gate. Sin camino rojo probado esto no es un gate, así que no se declara verde."
    elif ! harness_out="$(bash "$HARNESS" 2>&1)"; then
        echo "$harness_out" | sed 's/^/  /'
        err "$HARNESS:1" "el arnés del gate está en rojo: el gate no comprueba lo que dice comprobar. Se para aquí, sin mirar el corpus."
    else
        echo "$harness_out" | grep -E 'Total:' | sed 's/^/  /'
    fi
    if [ "$fail_count" -gt 0 ]; then
        section "Veredicto"
        echo "check-spec-shape: $fail_count violación(es) de la forma de las specs." >&2
        exit 1
    fi
fi

if [ ! -d "$ARTIFACTS" ]; then
    err "$ARTIFACTS:1" "no existe el directorio de artefactos de implementación: no hay nada que comprobar, y eso no es un verde."
    echo "check-spec-shape: $fail_count violación(es) de la forma de las specs." >&2
    exit 1
fi

# ── Regla (b) · los campos compartidos de `SessionStore` en el Code Map ──────
section "Regla (b) · campos compartidos de \`SessionStore\` en el Code Map"

specs=()
while IFS= read -r spec; do
    [ -n "$spec" ] && specs+=("$spec")
done < <(find "$ARTIFACTS" -maxdepth 1 -type f -name 'spec-*.md' | sort)

# Corpus vacío: un gate que no encuentra nada que comprobar no está en verde, está ciego.
if [ "${#specs[@]}" -eq 0 ]; then
    err "$ARTIFACTS:1" "no hay ninguna \`spec-*.md\` bajo este directorio: el gate no encontró nada que comprobar. Un corpus vacío no es un verde."
else
    rule_b_checked=0
    rule_b_failed=0
    rule_b_exempted=0

    for spec in "${specs[@]}"; do
        base="$(basename "$spec")"

        # El encabezado puede llevar texto detrás (`## Code Map (actualizado)`): lo que no
        # puede es faltar, ni estar dos veces —con dos, la mitad del Code Map queda fuera
        # del bloque que se mira y el verde no significaría nada.
        cm_lines="$(grep -nE '^## Code Map([[:space:]].*)?$' "$spec" | cut -d: -f1)"
        cm_count="$(printf '%s\n' "$cm_lines" | grep -c '[0-9]')"
        cm_line="$(printf '%s\n' "$cm_lines" | head -n 1)"
        if [ "$cm_count" -eq 0 ]; then
            err "$spec:1" "esta spec no tiene \`## Code Map\`: sin él la regla (b) no es comprobable, y lo que no se puede comprobar no se declara en verde."
            continue
        fi
        if [ "$cm_count" -gt 1 ]; then
            err "$spec:$(printf '%s\n' "$cm_lines" | sed -n '2p')" "esta spec tiene $cm_count encabezados \`## Code Map\`. El gate mira el primero y el resto quedaría sin comprobar: un Code Map es uno."
            continue
        fi

        # El Code Map va desde su encabezado hasta el siguiente `## `. Delimitarlo es lo
        # que separa el caso real del falso positivo: `spec-1-1` menciona `SessionStore`
        # nueve veces y NINGUNA dentro de su Code Map.
        block="$(awk -v start="$cm_line" 'NR > start { if ($0 ~ /^## /) exit; print }' "$spec")"

        grep -q 'SessionStore' <<< "$block" || continue
        rule_b_checked=$((rule_b_checked + 1))

        idx="$(exempt_index "$base")"

        # La marca de cumplimiento: una línea en negrita que empieza por
        # `**Campos compartidos`, con o sin viñeta delante.
        if grep -qE '^[[:space:]]*([-*+][[:space:]]+)?\*\*Campos compartidos' <<< "$block"; then
            if [ -n "$idx" ]; then
                exempt_state[$idx]="sobrante"
                err "$spec:$cm_line" "esta spec está en la lista de exención de la regla (b) de \`check-spec-shape.sh\` y YA lista sus campos compartidos: la exención sobra. Borra su línea de \`EXEMPT_RULE_B\` — una exención que ya no hace falta engorda la lista y esconde a las que sí."
            fi
            continue
        fi

        if [ -n "$idx" ]; then
            exempt_state[$idx]="vigente"
            rule_b_exempted=$((rule_b_exempted + 1))
            continue
        fi

        rule_b_failed=$((rule_b_failed + 1))
        err "$spec:$cm_line" "regla (b) de la lección de specs (A-7): este \`## Code Map\` menciona \`SessionStore\` y no lista sus campos compartidos. Añade aquí una línea \`**Campos compartidos…**\` con los campos del store que este cambio toca y sus invariantes, para que la siguiente historia no los pise."
    done

    echo "  specs en el corpus: ${#specs[@]}  ·  con \`SessionStore\` en el Code Map: $rule_b_checked  ·  exentas: $rule_b_exempted  ·  en rojo: $rule_b_failed"
fi

# ── Exenciones vigentes de la regla (b) ──────────────────────────────────────
# Se imprimen SIEMPRE, también en verde: lo que está exento se ve. Un verde que no las
# enumere es una mentira.
section "Exenciones declaradas de la regla (b) (D1 de Paul, A-7)"
i=0
while [ "$i" -lt "${#EXEMPT_RULE_B[@]}" ]; do
    entry="${EXEMPT_RULE_B[$i]}"
    file="${entry%%|*}"
    rest="${entry#*|}"
    date="${rest%%|*}"
    reason="${rest#*|}"
    case "${exempt_state[$i]}" in
        vigente)  mark="·" ;;
        sobrante) mark="✗" ;;
        *)        mark="?" ;;
    esac
    printf '  %s %-42s %s  %s%s\n' "$mark" "$file" "$date" "$reason" \
        "$([ "${exempt_state[$i]}" = "ausente" ] && echo "  [no está en este árbol: no evaluada]" || true)"
    i=$((i + 1))
done
echo "  Total: ${#EXEMPT_RULE_B[@]} exenciones declaradas. La exención cubre a las nombradas, no a la regla."
# Honestidad de alcance: el criterio NO es bidireccional del todo. Una exenta que ya lista
# sus campos deja el gate en rojo (`✗`), pero una exenta que no está en el árbol solo se
# marca `?` y no falla — en los árboles temporales del arnés casi todas están ausentes, y
# hacerlo rojo convertiría el caso normal del arnés en un fallo. Se ve, no se castiga.
echo "  Las marcadas \`?\` no están en este árbol y NO se evalúan: una exención de una spec borrada o renombrada se ve aquí, pero no pone el gate en rojo."

# ── Regla (a) · forma de las entradas de `deferred-work.md` ──────────────────
section "Regla (a) · destino explícito en \`deferred-work.md\`"

if [ ! -f "$DEFERRED" ]; then
    err "$DEFERRED:1" "no existe el registro de trabajo diferido. Es donde vive todo traspaso a otra historia (regla (a) del A-7): sin él no se puede declarar que no hay trabajo huérfano."
else
    # `awk` y no `wc -l`: un fichero sin salto de línea final tiene una línea más de las
    # que `wc` cuenta, y la última entrada se quedaría sin su `evidence` — rojo falso.
    total_lines="$(awk 'END{print NR}' "$DEFERRED")"
    starts=()
    while IFS= read -r n; do
        [ -n "$n" ] && starts+=("$n")
    done < <(grep -n '^- source_spec:' "$DEFERRED" | cut -d: -f1)

    entries="${#starts[@]}"
    a_failed=0
    a_closed=0

    # Corpus vacío, igual que en la regla (b): un registro sin una sola entrada no es un
    # verde, es un gate que no ha encontrado nada que mirar.
    if [ "$entries" -eq 0 ]; then
        err "$DEFERRED:1" "este registro no tiene ninguna entrada (\`- source_spec:\`): el gate no encontró nada que comprobar. Un registro vacío no es un verde; si de verdad no hay trabajo diferido, dilo por escrito aquí."
    fi

    # Lo que haya ANTES de la primera entrada también se lee: solo el encabezado y líneas
    # en blanco. Sin esto, un campo suelto o prosa a la cabeza del fichero es invisible
    # para el parser, que es la forma exacta de "verde por no haber mirado".
    preamble_end=0
    [ "$entries" -gt 0 ] && preamble_end=$(( ${starts[0]} - 1 ))
    [ "$entries" -eq 0 ] && preamble_end="$total_lines"
    if [ "$preamble_end" -gt 0 ]; then
        while IFS= read -r bad; do
            [ -z "$bad" ] && continue
            err "$DEFERRED:${bad%%:*}" "línea fuera de toda entrada, antes de la primera \`- source_spec:\`. Aquí solo caben el encabezado y líneas en blanco: lo que se escriba fuera de una entrada no lo lee ni el parser ni la historia siguiente."
        done < <(sed -n "1,${preamble_end}p" "$DEFERRED" | grep -nvE '^(#.*|[[:space:]]*)$' || true)
    fi

    i=0
    while [ "$i" -lt "$entries" ]; do
        start="${starts[$i]}"
        if [ "$((i + 1))" -lt "$entries" ]; then
            end=$(( ${starts[$((i + 1))]} - 1 ))
        else
            end="$total_lines"
        fi
        block="$(sed -n "${start},${end}p" "$DEFERRED")"
        entry_bad=0

        # Cada entrada son exactamente tres campos. Una línea que no sea ninguno de los
        # tres significa que el parser está leyendo otra cosa: se dice, no se ignora.
        bad_lines="$(grep -nvE '^(- source_spec:|  summary:|  evidence:|[[:space:]]*$)' <<< "$block" || true)"
        if [ -n "$bad_lines" ]; then
            while IFS= read -r bad; do
                off="${bad%%:*}"
                err "$DEFERRED:$((start + off - 1))" "línea que no es ninguno de los tres campos de una entrada (\`- source_spec:\`, \`  summary:\`, \`  evidence:\`). Una entrada diferida son tres líneas y ninguna más: lo demás no lo lee nadie."
            done <<< "$bad_lines"
            entry_bad=1
        fi

        summary_count="$(grep -c '^  summary:' <<< "$block")"
        evidence_count="$(grep -c '^  evidence:' <<< "$block")"
        summary_line="$(grep -n '^  summary:' <<< "$block" | head -n 1 | cut -d: -f1)"
        evidence_line="$(grep -n '^  evidence:' <<< "$block" | head -n 1 | cut -d: -f1)"

        if [ "$summary_count" -eq 0 ]; then
            err "$DEFERRED:$start" "a esta entrada le falta el campo \`summary\`: sin él nadie sabe qué trabajo se difirió."
            entry_bad=1
        elif [ "$summary_count" -gt 1 ]; then
            # Dos entradas fundidas: a una se le cayó su `- source_spec:` y el parser la
            # absorbe en la anterior, con lo que su falta de destino se vuelve invisible.
            err "$DEFERRED:$start" "este bloque tiene $summary_count campos \`summary\`: son dos entradas fundidas, y a la segunda le falta su \`- source_spec:\`. Fundidas, el gate solo comprueba el destino de una."
            entry_bad=1
        fi
        if [ "$evidence_count" -eq 0 ]; then
            err "$DEFERRED:$start" "a esta entrada le falta el campo \`evidence\`: sin él nadie sabe por qué esto es real y no una sospecha."
            entry_bad=1
        elif [ "$evidence_count" -gt 1 ]; then
            err "$DEFERRED:$start" "este bloque tiene $evidence_count campos \`evidence\`: son dos entradas fundidas, y a la segunda le falta su \`- source_spec:\`."
            entry_bad=1
        fi

        # Integridad referencial: una entrada que apunta a una spec que no existe es
        # huérfana — nadie puede volver al contexto que la generó.
        src="$(sed -n "${start}p" "$DEFERRED" | sed -E 's/^- source_spec:[[:space:]]*//; s/^`//; s/`[[:space:]]*$//; s/[[:space:]]*$//')"
        if [ -z "$src" ]; then
            err "$DEFERRED:$start" "esta entrada no nombra ninguna spec en \`source_spec\`: es huérfana desde el minuto uno."
            entry_bad=1
        elif [ ! -f "$ROOT/$src" ]; then
            err "$DEFERRED:$start" "entrada huérfana: su \`source_spec\` apunta a \`$src\`, que no existe en este árbol. O la spec se movió y hay que actualizar la referencia, o la entrada perdió el contexto que la justificaba."
            entry_bad=1
        fi

        if [ -n "$summary_line" ]; then
            summary_text="$(sed -n "$((start + summary_line - 1))p" "$DEFERRED" | sed -E 's/^  summary:[[:space:]]*//')"

            # El cierre no tiene campo propio: se marca con `**CERRADO el <fecha>` al
            # principio del `summary`, que es la convención real del fichero (D2). Una
            # entrada cerrada no tiene trabajo que asignar, así que no se le exige destino
            # — pero la FECHA no es adorno: sin ella, `**CERRADO` sería una forma de
            # eximirse del destino sin decir cuándo ni contra qué se cerró.
            if [[ "$summary_text" == '**CERRADO'* ]]; then
                if grep -qE '^\*\*CERRADO el [0-9]{4}-[0-9]{2}-[0-9]{2}' <<< "$summary_text"; then
                    a_closed=$((a_closed + 1))
                else
                    err "$DEFERRED:$((start + summary_line - 1))" "marca de cierre sin fecha: la convención es \`**CERRADO el <AAAA-MM-DD>\`. Un cierre sin fecha exime del destino sin decir cuándo se cerró, que es la exención invisible de siempre."
                    entry_bad=1
                fi
            # `Destino:` con algo detrás. `Destino:` a secas es la forma canónica vacía:
            # cumple la letra y no nombra a nadie.
            elif ! grep -qE 'Destino:[[:space:]]*[^[:space:]]' <<< "$block"; then
                err "$DEFERRED:$((start + summary_line - 1))" "regla (a) de la lección de specs (A-7): esta entrada no declara destino en la forma canónica \`Destino:\` seguida de a quién va (D3). Entrada: \"$(printf '%.70s' "$summary_text")…\". Trabajo diferido sin dueño es trabajo que nadie recoge."
                entry_bad=1
            fi
        fi

        a_failed=$((a_failed + entry_bad))
        i=$((i + 1))
    done

    echo "  entradas: $entries  ·  cerradas (exentas por \`**CERRADO el <fecha>\`): $a_closed  ·  entradas con fallo: $a_failed"
fi

# ── Veredicto ────────────────────────────────────────────────────────────────
section "Veredicto"
if [ "$fail_count" -gt 0 ]; then
    echo "check-spec-shape: $fail_count violación(es) de la forma de las specs." >&2
    exit 1
fi

echo "check-spec-shape: forma de las specs correcta."
exit 0
