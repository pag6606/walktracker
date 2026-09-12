#!/bin/bash
#
# Comprueba lo que el grafo de módulos NO puede comprobar por sí solo.
#
# El grafo de targets ya hace estructural la dirección de dependencias (AD-3) y ya
# impide que `WalkTrackerActivity` importe `Domain` (AD-15): esos símbolos no existen
# en su módulo y el enlazador lo dice. Lo que el grafo no ve es esto:
#
#   1. Que `Domain/` exista. Sin él no hay frontera que verificar y el proyecto se
#      generaría igual, en verde, sin dominio.
#   2. Que las `sources:` de `WalkTrackerActivity` no ALCANCEN `Domain/`. El grafo
#      protege contra `import Domain`; no protege contra meter los ficheros del
#      dominio dentro del target de la extensión, que los compilaría como propios
#      y dejaría AD-15 sin efecto sin un solo import.
#   3. Que todo `.swift` del árbol esté en algún target. `WalkTracker.xcodeproj` no
#      se versiona y XcodeGen fija la lista de ficheros: un fichero añadido sin
#      regenerar NO rompe el build, se ignora EN SILENCIO. Se comprobó de la peor
#      manera durante la verificación de esta historia.
#   4. Que ningún fichero de `Domain/` importe un framework de plataforma.
#      Esto SÍ es parseo de imports, y es deliberado: `import SwiftUI` dentro de un
#      framework compila perfectamente —SwiftUI está en el SDK— así que el compilador
#      NO puede hacer cumplir AD-3 en su mitad de "imports". La restricción congelada
#      del spec lo exige explícitamente: "un `import SwiftUI` o `import CoreMotion`
#      ahí tiene que romper el build". Sin esta comprobación, no se rompe.
#
# Uso:  check-project-shape.sh [raíz-del-repo]
# En el build lo invoca la preBuildScript de `WalkTracker` y la de
# `WalkTrackerActivity` — en las dos, porque la extensión compila ANTES que la app.

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$ROOT/project.yml"

fail_count=0

# Formato `fichero:línea: error:` para que Xcode lo enseñe en su sitio.
err() {
    echo "$1: error: $2" >&2
    fail_count=$((fail_count + 1))
}

if [ ! -f "$MANIFEST" ]; then
    err "$MANIFEST" "no existe project.yml. Es la fuente de verdad del proyecto: sin él no hay nada que comprobar."
    exit 1
fi

# ── Parseo de las `sources:` del manifiesto ──────────────────────────────────
# project.yml es nuestro y su forma es conocida y estrecha. No se instala un
# parser de YAML para leer un fichero que controlamos.
parse_sources() {
    awk '
        /^[A-Za-z_]/          { section = $1; target = ""; insrc = 0; next }
        section != "targets:" { next }
        /^  [A-Za-z_][A-Za-z0-9_]*:/ { target = $1; sub(/:$/, "", target); insrc = 0; next }
        /^    sources:/       { insrc = 1; next }
        /^    [A-Za-z_]/      { insrc = 0 }
        insrc && /^      - path:/ { p = $3; gsub(/"/, "", p); print target, p }
    ' "$MANIFEST"
}

SOURCES="$(parse_sources)"

if [ -z "$SOURCES" ]; then
    err "$MANIFEST" "no se pudo leer ninguna \`sources:\` del manifiesto. El gate no puede validar nada y no se declara en verde por no saber."
    exit 1
fi

# ── 1. `Domain/` existe ──────────────────────────────────────────────────────
if [ ! -d "$ROOT/Domain" ]; then
    err "$ROOT/Domain" "AD-3: no existe \`Domain/\`. El dominio es su propio módulo y es lo que hace estructural la dirección de dependencias; sin él el proyecto compila sin frontera que verificar."
fi

# ── 2. Las `sources:` de la extensión no alcanzan `Domain/` ──────────────────
# "Alcanzar" en los dos sentidos: la ruta ES el dominio o está dentro de él, o el
# dominio está dentro de la ruta (un `path: .` se los llevaría todos).
while read -r target path; do
    [ "$target" = "WalkTrackerActivity" ] || continue
    clean="${path%/}"
    case "$clean" in
        Domain | Domain/*)
            err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen '$path', que está dentro de \`Domain/\`. La extensión SOLO renderiza: compilar los ficheros del dominio dentro de su target deja AD-15 sin efecto sin un solo import."
            ;;
        . | ./ | "")
            err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen la raíz ('$path'), que arrastra \`Domain/\` al target de la extensión."
            ;;
        *)
            if [ -d "$ROOT/$clean/Domain" ]; then
                err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen '$path', que contiene \`Domain/\` y lo arrastra al target de la extensión."
            fi
            ;;
    esac
done <<< "$SOURCES"

# ── 3. Todo `.swift` del árbol está en algún target ──────────────────────────
TARGET_PATHS="$(echo "$SOURCES" | awk '{ print $2 }' | sed 's:/*$::' | sort -u)"

swift_files="$(
    find "$ROOT" -name '*.swift' -type f \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/DerivedData/*' \
        -not -path '*/.build/*' \
        -not -path '*/build/*' \
        -not -path '*/Pods/*' \
        -not -path '*/_bmad-output/*' \
        -not -path '*.xcodeproj/*' \
        2>/dev/null | sort
)"

# Lo que git ignora no está en el árbol: son restos de build ajenos al producto
# —el `ios/Flutter/ephemeral/` que deja Flutter, el primero—. Preguntarle a git es
# más honesto que mantener una segunda lista de exclusiones que se desincroniza.
# Si no hay repositorio (el arnés del camino rojo monta un árbol pelado), se queda
# con las exclusiones estáticas de arriba.
if [ -n "$swift_files" ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ignored="$(git -C "$ROOT" check-ignore --stdin 2>/dev/null <<< "$swift_files" | sort)"
    if [ -n "$ignored" ]; then
        swift_files="$(comm -23 <(echo "$swift_files") <(echo "$ignored"))"
    fi
fi

while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$ROOT"/}"
    covered=0
    while IFS= read -r tp; do
        [ -n "$tp" ] || continue
        if [ "$rel" = "$tp" ] || [ "${rel#"$tp"/}" != "$rel" ]; then
            covered=1
            break
        fi
    done <<< "$TARGET_PATHS"
    if [ "$covered" -eq 0 ]; then
        err "$file" "no pertenece a ningún target de project.yml. XcodeGen fija la lista de ficheros: este fichero NO se compila y el build pasa en verde sin él. Añádelo a un target y ejecuta \`xcodegen generate\`."
    fi
done <<< "$swift_files"

# ── 4. `Domain/` no importa ningún framework de plataforma ───────────────────
# El compilador no puede hacer cumplir esto: `import SwiftUI` dentro de un framework
# compila. La restricción congelada del spec exige que rompa el build.
if [ -d "$ROOT/Domain" ]; then
    banned='SwiftUI|UIKit|AppKit|CoreMotion|CoreLocation|HealthKit|ActivityKit|WidgetKit|CoreHaptics|UserNotifications|Combine|WatchKit|Observation'
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        module="$(echo "${rest#*:}" | sed -E 's/^[[:space:]]*import[[:space:]]+//; s/[[:space:]].*$//')"
        err "$hit_file:$hit_line" "AD-3: \`Domain/\` solo puede importar Foundation, y este fichero importa \`$module\`. El dominio no conoce SwiftUI, CoreMotion, HealthKit, ActivityKit, CoreLocation ni UIKit: esas capacidades entran por un puerto de \`Domain/Ports/\`."
    done < <(grep -rnE "^[[:space:]]*import[[:space:]]+($banned)\b" "$ROOT/Domain" --include='*.swift' 2>/dev/null)
fi

# ── 5. La extensión no importa `Domain` (AD-15) ──────────────────────────────
# Verificado a mano, y NO es redundante con el grafo de targets: `Domain` no es
# dependencia declarada de `WalkTrackerActivity`, pero la app SÍ lo embebe, así que
# el módulo queda resoluble desde `BUILT_PRODUCTS_DIR` y `import Domain` en la
# extensión COMPILA EN VERDE. Se comprobó: el build pasaba.
#
# Por eso este gate está enganchado también al target de la extensión. La extensión
# es dependencia de la app y compila ANTES: con el script solo en la app, el fallo
# llegaba tarde o no llegaba.
if [ -d "$ROOT/WalkTrackerActivity" ]; then
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-15: \`WalkTrackerActivity\` no puede importar \`Domain\`. La extensión SOLO renderiza: no calcula, no lee ficheros y no tiene dominio. Su contrato de datos es \`ActivitySnapshot\`, en \`Shared/\`, con los valores ya formateados."
    done < <(grep -rnE "^[[:space:]]*import[[:space:]]+Domain\b" "$ROOT/WalkTrackerActivity" --include='*.swift' 2>/dev/null)
fi

# ── Veredicto ────────────────────────────────────────────────────────────────
if [ "$fail_count" -gt 0 ]; then
    echo "check-project-shape: $fail_count violación(es) de la forma del proyecto." >&2
    exit 1
fi

echo "check-project-shape: forma del proyecto correcta."
exit 0
