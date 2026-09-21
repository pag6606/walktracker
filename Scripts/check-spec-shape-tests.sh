#!/bin/bash
#
# Camino rojo (y verde) de `check-spec-shape.sh` (A-7). Un gate sin prueba de su camino
# rojo no es un gate: es un script que nadie ha visto fallar (B-5/B-6).
#
# El defecto que cierra: las dos reglas de la lección de specs se aplicaban a mano desde
# que se decidieron, y llevaban incumpliéndose desde el principio sin que nadie lo notara.
# Un check que solo se hubiera visto en verde sobre el árbol arreglado repetiría el mismo
# error con otra cara: pareceria proteger.
#
# **Cada regla trae caso rojo Y caso verde.** Los verdes importan tanto como los rojos:
# la regla (b) tiene un falso positivo evidente —una spec que menciona `SessionStore`
# fuera de su Code Map, como hace `spec-1-1` nueve veces— y sin un caso verde que lo fije,
# la primera "mejora" del gate lo rompe.
#
# Monta un árbol temporal con `mktemp -d` —NUNCA toca el repositorio—, aplica UNA mutación
# por caso y afirma el código de salida Y el mensaje, para no dar por buena una violación
# detectada por la razón equivocada.
#
# Uso:  bash Scripts/check-spec-shape-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-spec-shape.sh"

pass=0
fail=0

report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# Afirma el código de salida; si se pide, que la salida mencione un texto concreto; y si
# se pide, que NO mencione otro (para probar que el gate señala la spec correcta y no
# arrastra a las vecinas).
assert_gate() {
    local name="$1" root="$2" want="$3" needle="${4:-}" anti="${5:-}"
    local out status

    # Si `mktemp -d` falló, `$root` viene vacío y el gate se lanzaría SIN argumento: es
    # decir, contra el repositorio real, justo lo que este arnés promete no hacer nunca.
    # Se comprueba aquí porque es el único sitio por el que pasan todos los casos.
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        report_fail "$name — no hay árbol temporal (¿falló \`mktemp -d\`?). No se corre el gate: sin raíz apuntaría al repositorio."
        return
    fi

    out="$(bash "$GATE" "$root" 2>&1)"
    status=$?

    if [ "$status" -ne "$want" ]; then
        report_fail "$name — esperado exit $want, obtenido $status"
        echo "$out" | sed 's/^/      /'
        return
    fi
    if [ -n "$needle" ] && ! grep -q -- "$needle" <<< "$out"; then
        report_fail "$name — exit $want correcto, pero la salida no menciona '$needle'"
        echo "$out" | sed 's/^/      /'
        return
    fi
    if [ -n "$anti" ] && grep -q -- "$anti" <<< "$out"; then
        report_fail "$name — exit $want correcto, pero la salida señala además '$anti'"
        echo "$out" | sed 's/^/      /'
        return
    fi
    report_pass "$name"
}

# Una spec con la forma real del corpus: frontmatter, `## Intent`, `## Code Map` y la
# sección siguiente, que es la que delimita el Code Map por abajo.
#
#   store-con-campos   toca `SessionStore` en el Code Map y lista los campos → verde
#   store-sin-campos   toca `SessionStore` en el Code Map y no los lista     → rojo
#   store-fuera        menciona `SessionStore` FUERA del Code Map            → verde
#   sin-store          no lo menciona                                        → verde
#   sin-code-map       no tiene `## Code Map`                                → rojo
write_spec() {
    local file="$1" variant="$2"
    mkdir -p "$(dirname "$file")"
    {
        echo "---"
        echo "title: 'Fixture del arnés de check-spec-shape'"
        echo "status: 'done'"
        echo "---"
        echo
        echo "## Intent"
        echo
        if [ "$variant" = "store-fuera" ]; then
            echo "Esta historia arranca la sesión: \`SessionStore\` publica el estado, \`SessionStore\`"
            echo "reconcilia el hueco y \`SessionStore\` guarda el snapshot. Nueve menciones como las de"
            echo "\`spec-1-1\`, y ninguna en el Code Map."
        else
            echo "Una historia cualquiera del fixture."
        fi
        echo
        if [ "$variant" != "sin-code-map" ]; then
            echo "## Code Map"
            echo
            case "$variant" in
                store-con-campos|store-sin-campos)
                    echo "- \`WalkTracker/Application/SessionStore.swift\` — el store de sesión."
                    ;;
                *)
                    echo "- \`Domain/Formulas.swift\` — fórmulas puras, sin estado compartido."
                    ;;
            esac
            if [ "$variant" = "store-con-campos" ]; then
                echo "- **Campos compartidos del store** (lección L3): \`backgroundedAt\` y"
                echo "  \`stepsMeasuredAtGapStart\` — o están los dos o no está ninguno."
            fi
            echo
        fi
        echo "## Tasks & Acceptance"
        echo
        echo "- [x] Nada que hacer: esto es un fixture."
        # Las menciones que importan van DESPUÉS del Code Map, no antes. Con ellas solo
        # delante, un gate que leyera hasta el final del fichero —en vez de cortar en el
        # siguiente `## `— seguía saliendo verde y el caso no se enteraba. Medido: con el
        # corte eliminado, el arnés daba 19/19 y el gate marcaba en falso a `spec-1-1`,
        # que menciona `SessionStore` en las líneas 91–146 con su Code Map en la 68.
        if [ "$variant" = "store-fuera" ]; then
            echo
            echo "## Implementation Notes"
            echo
            echo "Al implementar se tocó \`SessionStore\` otra vez, y \`SessionStore\` de nuevo"
            echo "en la recuperación. Igual que el corpus real: las menciones caen aquí abajo."
        fi
    } > "$file"
}

# Una entrada de `deferred-work.md` con su forma real: tres líneas exactas.
deferred_entry() {
    printf -- '- source_spec: `%s`\n  summary: %s\n  evidence: %s\n' "$1" "$2" "$3"
}

# Los nombres de la lista de exención salen del propio gate, para que el arnés no
# mantenga una segunda copia a mano — el defecto que B-6 cerró.
exempt_names() {
    sed -nE '/^EXEMPT_RULE_B=\(/,/^\)/p' "$GATE" \
        | sed -E '1d;$d;s/^[[:space:]]*"//;s/\|.*$//' | grep -v '^$'
}

ARTIFACTS_REL="_bmad-output/implementation-artifacts"

# ── Fixture verde: el árbol mínimo que cumple las dos reglas ─────────────────
make_fixture() {
    local root dir
    if ! root="$(mktemp -d)" || [ -z "$root" ]; then
        echo "mktemp -d falló: no se monta ningún fixture." >&2
        return 1
    fi
    dir="$root/$ARTIFACTS_REL"
    mkdir -p "$dir"

    write_spec "$dir/spec-verde-store.md"  store-con-campos
    write_spec "$dir/spec-verde-fuera.md"  store-fuera
    write_spec "$dir/spec-verde-simple.md" sin-store

    {
        echo "# Deferred Work"
        echo
        deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
            "Portar los vectores que faltan. Destino: la historia 3.1." \
            "Quedaron fuera por no tener calendario."
        deferred_entry "$ARTIFACTS_REL/spec-verde-store.md" \
            "**CERRADO el 2026-09-21 — Paul lo zanjó el mismo día.** Estaba registrado así: faltaba el enlace a la licencia." \
            "Ya no hay trabajo que asignar, así que no hay destino que exigir."
    } > "$dir/deferred-work.md"

    echo "$root"
}

echo "══════════════════════════════════════════════════════════"
echo "  Camino rojo y verde de check-spec-shape.sh (A-7)"
echo "══════════════════════════════════════════════════════════"

# ── 0. Verde de referencia ───────────────────────────────────────────────────
ROOT="$(make_fixture)"
assert_gate "el árbol que cumple las dos reglas pasa" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

echo "── Regla (b) · campos compartidos en el Code Map ──"

# ── 1. (b) rojo: `SessionStore` en el Code Map sin los campos ────────────────
ROOT="$(make_fixture)"
write_spec "$ROOT/$ARTIFACTS_REL/spec-nueva-sin-campos.md" store-sin-campos
assert_gate "una spec nueva con \`SessionStore\` y sin campos compartidos falla" "$ROOT" 1 \
    "spec-nueva-sin-campos.md:10: error: regla (b)" \
    "spec-verde-store.md"
rm -rf "$ROOT"

# ── 2. (b) rojo: borrar la línea de campos de una spec que la tenía ──────────
# El criterio de aceptación pide que nombre ESA spec y no otra: el `anti` lo fija.
ROOT="$(make_fixture)"
write_spec "$ROOT/$ARTIFACTS_REL/spec-vecina-store.md" store-con-campos
sed -i.bak '/Campos compartidos/d' "$ROOT/$ARTIFACTS_REL/spec-verde-store.md"
rm -f "$ROOT/$ARTIFACTS_REL/spec-verde-store.md.bak"
assert_gate "borrar la línea \`**Campos compartidos…\` falla nombrando esa spec" "$ROOT" 1 \
    "spec-verde-store.md:10: error: regla (b)" \
    "spec-vecina-store.md:"
rm -rf "$ROOT"

# ── 3. (b) verde: `SessionStore` mencionado FUERA del Code Map ──────────────
# El falso positivo evidente de esta regla, y el que la hace útil: `spec-1-1` menciona
# `SessionStore` nueve veces y ninguna en su Code Map. Sin este caso verde, la primera
# "simplificación" del gate (buscar en el fichero entero) pasa desapercibida.
ROOT="$(make_fixture)"
write_spec "$ROOT/$ARTIFACTS_REL/spec-menciona-fuera.md" store-fuera
assert_gate "mencionar \`SessionStore\` fuera del Code Map NO dispara la regla" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# ── 4. (b) rojo: una spec sin `## Code Map` ─────────────────────────────────
# No se declara verde lo que no se miró: sin Code Map la regla no es comprobable.
ROOT="$(make_fixture)"
write_spec "$ROOT/$ARTIFACTS_REL/spec-sin-code-map.md" sin-code-map
assert_gate "una spec sin \`## Code Map\` falla en vez de saltarse" "$ROOT" 1 \
    "spec-sin-code-map.md:1: error: esta spec no tiene"
rm -rf "$ROOT"

# ── 5. (b) verde: una spec exenta de D1 sin los campos ──────────────────────
EXEMPT_ONE="$(exempt_names | head -n 1)"
if [ -z "$EXEMPT_ONE" ]; then
    report_fail "el gate no declara ninguna exención: la lista de D1 ha desaparecido"
else
    ROOT="$(make_fixture)"
    write_spec "$ROOT/$ARTIFACTS_REL/$EXEMPT_ONE" store-sin-campos
    assert_gate "una spec exenta sin campos pasa Y se imprime como exención" "$ROOT" 0 \
        "$EXEMPT_ONE"

    # Y se imprimen TODAS, no solo la primera. Afirmar únicamente la primera dejaba pasar
    # un `break` en el bucle de impresión: el arnés seguía verde con 1 exención impresa de
    # 14 mientras el rótulo seguía diciendo "Total: 14". Una exención invisible es una
    # mentira, y catorce menos una también.
    declared="$(exempt_names | wc -l | tr -d ' ')"
    printed="$(bash "$GATE" "$ROOT" 2>&1 | grep -cE '^  [·✗?] ')"
    if [ "$printed" = "$declared" ]; then
        report_pass "el gate imprime una línea por exención declarada ($printed de $declared)"
    else
        report_fail "el gate imprime $printed líneas de exención y declara $declared"
    fi
    rm -rf "$ROOT"

    # ── (b) verde: una exención cuya spec NO está en este árbol ────────────────
    # Comportamiento declarado, no descuido: se marca `?` y NO pone el gate en rojo. El
    # criterio de "la exención sobrante es roja" es de una sola dirección a propósito —en
    # los árboles temporales de este arnés casi todas las exenciones están ausentes, y
    # hacerlo rojo convertiría el caso normal del arnés en un fallo. Se ve, no se castiga.
    ROOT="$(make_fixture)"
    assert_gate "una exención ausente del árbol se imprime con \`?\` y NO falla" "$ROOT" 0 \
        "no está en este árbol: no evaluada"
    rm -rf "$ROOT"

    # ── 6. (b) rojo: una exención que ya no hace falta ──────────────────────
    # Si alguien rellena una spec exenta, la exención sobra: una exención innecesaria
    # engorda la lista y esconde a las que sí lo son.
    ROOT="$(make_fixture)"
    write_spec "$ROOT/$ARTIFACTS_REL/$EXEMPT_ONE" store-con-campos
    assert_gate "una exención que ya no hace falta falla pidiendo que se borre" "$ROOT" 1 \
        "la exención sobra"
    rm -rf "$ROOT"
fi

# ── 6b. (b) verde: el marcador SIN viñeta delante ───────────────────────────
# El patrón admite viñeta opcional (`([-*+][[:space:]]+)?`) y las 5 líneas reales del
# corpus usan todas `- `, así que la rama sin viñeta no la ejercitaba nada: se podía
# borrar del patrón y el arnés seguía en verde.
ROOT="$(make_fixture)"
sed -i.bak 's/^- \*\*Campos compartidos/**Campos compartidos/' \
    "$ROOT/$ARTIFACTS_REL/spec-verde-store.md"
rm -f "$ROOT/$ARTIFACTS_REL/spec-verde-store.md.bak"
assert_gate "el marcador sin viñeta delante también cumple la regla (b)" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# ── 6c. (b) verde: encabezado con texto detrás; rojo: encabezado repetido ───
# `## Code Map (actualizado)` es un Code Map, y anclar el encabezado con `$` lo daba por
# ausente: rojo falso sobre una spec correcta.
ROOT="$(make_fixture)"
sed -i.bak 's/^## Code Map$/## Code Map (actualizado 2026-09-21)/' \
    "$ROOT/$ARTIFACTS_REL/spec-verde-store.md"
rm -f "$ROOT/$ARTIFACTS_REL/spec-verde-store.md.bak"
assert_gate "un \`## Code Map\` con texto detrás sigue siendo un Code Map" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# Con dos encabezados, el gate mira el primero y la otra mitad se queda sin comprobar:
# eso es un verde por no haber mirado, así que se dice.
ROOT="$(make_fixture)"
{
    echo
    echo "## Code Map"
    echo
    echo "- \`WalkTracker/Application/SessionStore.swift\` — el segundo, sin campos."
} >> "$ROOT/$ARTIFACTS_REL/spec-verde-store.md"
assert_gate "un \`## Code Map\` repetido falla en vez de comprobar solo el primero" "$ROOT" 1 \
    "encabezados \`## Code Map\`"
rm -rf "$ROOT"

# ── 7. Corpus vacío: no hay verde silencioso ────────────────────────────────
ROOT="$(make_fixture)"
rm -f "$ROOT/$ARTIFACTS_REL"/spec-*.md
assert_gate "una raíz sin ninguna \`spec-*.md\` no da el verde" "$ROOT" 1 \
    "no encontró nada que comprobar"
rm -rf "$ROOT"

ROOT="$(mktemp -d)"
assert_gate "una raíz sin directorio de artefactos no da el verde" "$ROOT" 1 \
    "no existe el directorio de artefactos"
rm -rf "$ROOT"

echo "── Regla (a) · destino explícito en deferred-work.md ──"

# ── 8. (a) rojo: entrada sin destino ────────────────────────────────────────
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "Extraer la presentación de la pantalla de Inicio a un tipo probable." \
    "Hueco de verificación de la revisión: hoy lo cubre un check manual." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una entrada sin \`Destino:\` falla nombrando línea y entrada" "$ROOT" 1 \
    "deferred-work.md:10: error: regla (a)"
rm -rf "$ROOT"

# El mensaje trae el arranque del `summary`, no solo el número de línea: sin eso hay que
# abrir el fichero para saber de qué entrada habla.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "Extraer la presentación de la pantalla de Inicio a un tipo probable." \
    "Hueco de verificación de la revisión: hoy lo cubre un check manual." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "el fallo de destino cita el arranque del \`summary\`" "$ROOT" 1 \
    "Extraer la presentación de la pantalla de Inicio"
rm -rf "$ROOT"

# ── 9. (a) verde: una entrada cerrada no necesita destino ───────────────────
# El fixture ya trae una `**CERRADO`; este caso comprueba que es ESA marca la que la
# exime, y no que el gate no esté mirando.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "**CERRADO el 2026-09-21 — se hizo en la misma historia.** Quedaba pendiente pintar la degradación." \
    "No hay trabajo que asignar." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una entrada \`**CERRADO\` sin destino pasa" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# Y la misma entrada SIN la marca de cierre falla: lo que la exime es la marca.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "Se hizo en la misma historia. Quedaba pendiente pintar la degradación." \
    "No hay trabajo que asignar." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "la misma entrada sin \`**CERRADO\` sí falla" "$ROOT" 1 \
    "no declara destino en la forma canónica"
rm -rf "$ROOT"

# ── 10. (a) rojo: faltan campos ─────────────────────────────────────────────
ROOT="$(make_fixture)"
{
    echo "- source_spec: \`$ARTIFACTS_REL/spec-verde-simple.md\`"
    echo "  evidence: Le falta el summary. Destino: la 3.1."
} >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una entrada sin \`summary\` falla nombrando el campo" "$ROOT" 1 \
    "le falta el campo \`summary\`"
rm -rf "$ROOT"

ROOT="$(make_fixture)"
{
    echo "- source_spec: \`$ARTIFACTS_REL/spec-verde-simple.md\`"
    echo "  summary: Le falta la evidencia. Destino: la 3.1."
} >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una entrada sin \`evidence\` falla nombrando el campo" "$ROOT" 1 \
    "le falta el campo \`evidence\`"
rm -rf "$ROOT"

# ── 11. (a) rojo: una línea que no es ninguno de los tres campos ────────────
# Si el parser se encuentra algo que no sabe leer, lo dice: callárselo sería volver a
# "verde por no haber mirado".
ROOT="$(make_fixture)"
{
    deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
        "Una entrada con un campo inventado. Destino: la 3.1." \
        "Evidencia cualquiera."
    echo "  owner: nadie"
} >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una línea que no es ninguno de los tres campos falla" "$ROOT" 1 \
    "no es ninguno de los tres campos"
rm -rf "$ROOT"

# ── 12. (a) rojo: integridad referencial ────────────────────────────────────
# Esta regla nace en verde sobre el árbol real (los 21 `source_spec` distintos existen);
# su camino rojo solo se puede demostrar aquí.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-que-nunca-existio.md" \
    "Una entrada huérfana. Destino: la 3.1." \
    "Su spec no está en el árbol." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un \`source_spec\` que no existe falla como entrada huérfana" "$ROOT" 1 \
    "entrada huérfana"
rm -rf "$ROOT"

# Renombrar la spec sin tocar la entrada es el mismo caso, y es el que pasa de verdad.
ROOT="$(make_fixture)"
mv "$ROOT/$ARTIFACTS_REL/spec-verde-simple.md" "$ROOT/$ARTIFACTS_REL/spec-renombrada.md"
assert_gate "renombrar una spec deja huérfanas sus entradas, y el gate lo dice" "$ROOT" 1 \
    "entrada huérfana"
rm -rf "$ROOT"

# ── 13. (a) rojo: sin registro de trabajo diferido ──────────────────────────
ROOT="$(make_fixture)"
rm -f "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "sin \`deferred-work.md\` el gate no da el verde" "$ROOT" 1 \
    "no existe el registro de trabajo diferido"
rm -rf "$ROOT"

# ── 14. (a) verde: el `Destino:` vive solo en el `evidence` ─────────────────
# 11 de las 54 entradas reales son así. La búsqueda va sobre la ENTRADA entera, no sobre
# el `summary`: estrechándola a `summary_text` el arnés seguía en 19/19 y once entradas
# legítimas del corpus se ponían en rojo. Medido.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "Portar el resto de los vectores de equivalencia." \
    "Les falta el calendario, que no existe todavía. Destino: la historia 3.1, que lo crea." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un \`Destino:\` que vive solo en el \`evidence\` cuenta" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# ── 15. (a) rojo: un registro sin una sola entrada ──────────────────────────
# La simetría con la regla (b): allí el corpus vacío ya fallaba, aquí no. Un fichero con
# solo el encabezado salía verde, que es el verde silencioso de siempre.
ROOT="$(make_fixture)"
printf '# Deferred Work\n\n' > "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un \`deferred-work.md\` sin entradas no da el verde" "$ROOT" 1 \
    "no tiene ninguna entrada"
rm -rf "$ROOT"

# ── 16. (a) rojo: `Destino:` sin nada detrás ────────────────────────────────
# La forma canónica vacía: cumple la letra y no nombra a nadie.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "Una entrada que cumple la letra y a nadie nombra. Destino:" \
    "Evidencia cualquiera." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un \`Destino:\` sin nada detrás no cuenta como destino" "$ROOT" 1 \
    "seguida de a quién va"
rm -rf "$ROOT"

# ── 17. (a) rojo: `**CERRADO` sin fecha ─────────────────────────────────────
# La convención es `**CERRADO el <fecha>`. Sin fecha, la marca es una forma de eximirse
# del destino sin decir cuándo ni contra qué se cerró.
ROOT="$(make_fixture)"
deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
    "**CERRADO — ya se hizo.** Sin fecha, sin destino y sin rastro." \
    "Evidencia cualquiera." \
    >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un \`**CERRADO\` sin fecha no exime del destino" "$ROOT" 1 \
    "marca de cierre sin fecha"
rm -rf "$ROOT"

# ── 18. (a) rojo: lo que hay antes de la primera entrada ────────────────────
# El parser empieza en el primer `- source_spec:`; todo lo anterior era invisible, así que
# un campo suelto o prosa a la cabeza del fichero pasaba sin que nadie lo mirara.
ROOT="$(make_fixture)"
printf '# Deferred Work\n\nowner: nadie\n\n%s' \
    "$(cat "$ROOT/$ARTIFACTS_REL/deferred-work.md" | tail -n +3)" \
    > "$ROOT/$ARTIFACTS_REL/deferred-work.tmp"
mv "$ROOT/$ARTIFACTS_REL/deferred-work.tmp" "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "una línea suelta antes de la primera entrada falla" "$ROOT" 1 \
    "línea fuera de toda entrada"
rm -rf "$ROOT"

# ── 19. (a) rojo: dos entradas fundidas ─────────────────────────────────────
# A la segunda se le cae su `- source_spec:` y el parser la absorbe en la anterior: su
# falta de destino se vuelve invisible, que es peor que un rojo.
ROOT="$(make_fixture)"
{
    printf -- '  summary: La entrada fundida, sin destino y sin dueño.\n'
    printf -- '  evidence: A esta le falta su `- source_spec:`.\n'
} >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "dos entradas fundidas fallan en vez de absorberse" "$ROOT" 1 \
    "entradas fundidas"
rm -rf "$ROOT"

# ── 20. (a) verde: fichero sin salto de línea final ─────────────────────────
# `wc -l` cuenta una línea de menos y la última entrada se quedaba sin su `evidence`:
# rojo falso sobre un fichero correcto.
ROOT="$(make_fixture)"
printf '%s' "$(cat "$ROOT/$ARTIFACTS_REL/deferred-work.md")" \
    > "$ROOT/$ARTIFACTS_REL/deferred-work.tmp"
mv "$ROOT/$ARTIFACTS_REL/deferred-work.tmp" "$ROOT/$ARTIFACTS_REL/deferred-work.md"
assert_gate "un fichero sin salto de línea final NO da rojo falso" "$ROOT" 0 \
    "forma de las specs correcta"
rm -rf "$ROOT"

# ── 21. (a) rojo: las grafías que D3 proscribió ─────────────────────────────
# Fijan que `Destino:` es LITERAL. Sin estos casos, ensanchar el patrón a `Destino` o
# hacerlo insensible a mayúsculas restaura en silencio la ambigüedad que D3 vino a quitar
# —y que costaba cinco entradas declaradas en prosa que nadie encontraba.
for redaccion in "Destino explícito: la historia 3.1." "Encaja al cerrar la 8.4." "destino: la historia 3.1."; do
    ROOT="$(make_fixture)"
    deferred_entry "$ARTIFACTS_REL/spec-verde-simple.md" \
        "Una entrada que dice su destino con otra grafía. $redaccion" \
        "Evidencia cualquiera." \
        >> "$ROOT/$ARTIFACTS_REL/deferred-work.md"
    assert_gate "\"$redaccion\" NO cuenta como la forma canónica" "$ROOT" 1 \
        "no declara destino en la forma canónica"
    rm -rf "$ROOT"
done

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"

[ "$fail" -eq 0 ]
