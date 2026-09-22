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
#   5. Que la extensión no importe `Domain` (AD-15). Ver la sección.
#   6. Que la UI y la app no escriban el estado de los stores (AD-7, AD-16). Desde el
#      A-1 de la retro del Epic 1 sus propiedades y pasos internos tienen acceso de
#      módulo, porque los comparten sus extensiones: el compilador ya no impide un
#      `store.session = nil` en una vista. El receptor se reconoce por su TIPO declarado
#      (`SessionStore`, `SettingsStore`, y desde la 5.1 `HistoryStore` y
#      `AchievementsStore`), no por cómo se llame la variable.
#   7. Que solo el adapter de movimiento importe CoreMotion (AD-10): en `WalkTracker/`,
#      `import CoreMotion` solo en `WalkTracker/Adapters/Motion/`. Y lo mismo para la
#      ubicación (2.1): `import CoreLocation` solo en `WalkTracker/Adapters/Location/`.
#   8. Que el dominio no lea el reloj ni el calendario del sistema (AD-3, AD-19): en
#      `Domain/` no hay `Date()`, `Date.now` ni `Calendar.current` en código. El tiempo
#      entra por `ClockPort`. Los comentarios que los nombran no cuentan.
#   9. Que cada fichero de `StoragePort` tenga UN dueño (AD-16). El puerto es uno y los
#      ficheros CUATRO, así que el compilador no separa nada: las llamadas a
#      `load`/`save`/`clear`/`setAsideActiveSession` solo en
#      `WalkTracker/Application/SessionStore*.swift`; las de `load`/`saveSettings` (2.2) solo
#      en `WalkTracker/Application/SettingsStore*.swift`; las de `load`/`saveSessions` (5.1)
#      solo en `WalkTracker/Application/HistoryStore*.swift`; y las de
#      `load`/`saveAchievements` (5.1) solo en `WalkTracker/Application/AchievementsStore*.swift`
#      — cada una con su implementación en `WalkTracker/Adapters/Persistence/`. Ningún dueño
#      toca el fichero de otro.
#  10. Que ninguna vista importe un framework de sistema (AD-10): `WalkTracker/UI/` no
#      importa CoreMotion, CoreLocation, HealthKit, ActivityKit, WidgetKit, CoreHaptics,
#      AVFoundation, AudioToolbox, UserNotifications ni UIKit. Esas capacidades entran
#      por un puerto y su adapter.
#  11. Que la red solo salga del adapter del clima (2.1, AD-10): en `WalkTracker/` y
#      `Domain/`, `URLSession`, `URLRequest` e `import Network` solo en
#      `WalkTracker/Adapters/Weather/`. Open-Meteo es la única llamada de red del producto.
#  12. Que ninguna vista cablee el vocabulario visual (AD-13, UX-DR3, AD-20): en
#      `WalkTracker/UI/` —salvo `Style/DesignTokens.swift` y `Diagnostics/`— no se escribe
#      a mano un lado de marco numérico (el 44 pt del objetivo táctil), ni un radio de
#      esquina numérico, ni un color en hexadecimal o por componentes, ni NINGÚN color
#      CROMÁTICO del sistema —`.red`, `.orange`, `.yellow`, `.mint`…—, porque un color sin
#      medir es como entró el incumplimiento WCAG AA dos veces (los roles semánticos
#      `.primary`, `.secondary` y `.tint` sí pasan: su contraste lo garantiza el sistema),
#      ni los peldaños de la escala
#      —4, 8, 12, 16, 24— en `spacing:`, `minLength:` o `.padding(…)`. Viven en
#      `WalkTracker/UI/Style/DesignTokens.swift`. Los valores que la spec decide NO
#      tokenizar (`spacing: 0`, `spacing: 2`, `.padding(.top, 48)`) siguen permitidos.
#      Además: la key `UIDesignRequiresCompatibility` no aparece en ningún `Info.plist`
#      del manifiesto (AD-13) —y un `Info.plist` declarado que no exista es un fallo, no
#      un salto silencioso—, y el target de la app (`type: application`) fija
#      `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` con su colorset en el
#      árbol, sin lo cual el acento de la app vuelve al azul del sistema POR OMISIÓN, no
#      por decisión.
#      Sin target de UI tests, este check es lo único que impide que el vocabulario se
#      erosione en la primera historia que lo use.
#
#   Las secciones 7–12 no miran `WalkTrackerTests/`, `Shared/` ni `WalkTrackerActivity/`.
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

# ── Ajustes del manifiesto, por target ───────────────────────────────────────
# `target<TAB>clave<TAB>valor` de todo `clave: valor` que cuelgue de un target, a
# cualquier profundidad (`type:`, `settings.base.*`, `settings.configs.*`). Es lo que
# permite anclar una comprobación AL TARGET en vez de a `project.yml` entero: la
# sección 12c salía verde con la key del acento movida al target de la extensión.
parse_target_settings() {
    awk '
        /^[A-Za-z_]/          { section = $1; target = ""; next }
        section != "targets:" { next }
        /^  [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ { target = $1; sub(/:$/, "", target); next }
        target == ""          { next }
        /^ +[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*[^[:space:]]/ {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            key = line; sub(/:.*$/, "", key)
            val = line; sub(/^[^:]*:[[:space:]]*/, "", val)
            sub(/[[:space:]]*$/, "", val)
            gsub(/"/, "", val)
            print target "\t" key "\t" val
        }
    ' "$MANIFEST"
}

TARGET_SETTINGS="$(parse_target_settings)"

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

# ── 6. La UI y la app no escriben el estado de los stores (AD-7, AD-16) ─────
# `SessionStore` es el único escritor de la sesión y del snapshot, y `SettingsStore` el
# único de `settings.json`. Sus propiedades y sus pasos internos tienen acceso de módulo
# para que los compartan sus extensiones, así que el compilador no lo hace cumplir fuera de
# ahí. En `WalkTracker/UI` y `WalkTracker/App` se permite leer el estado y llamar a las
# intenciones (y a `restoreOnLaunch()`); no se permite asignar una propiedad del store,
# llamar a sus pasos internos ni tocar sus puertos.
#
# QUÉ ES "del store" (corregido por B-5, 2026-09-20). Antes era *cualquier receptor que
# acabe en `store`/`Store`*, que es una regla sobre el NOMBRE DE LA VARIABLE y no sobre el
# invariante: `settings.save()` en una vista salía en verde, y lo único que lo impedía era
# un comentario en producción pidiendo no renombrar la variable — un *rename* en Xcode lo
# desarmaba (retro del Epic 2, D9). Ahora el criterio principal es el TIPO: se derivan de
# cada fichero los identificadores declarados como `SessionStore` o `SettingsStore`
# (`let settingsStore: SettingsStore`, `init(store: SessionStore, …)`,
# `func f(_ settings: SettingsStore)`, `let s = SessionStore(…)`), y esos son los
# receptores de ese fichero. Un tipo ANIDADO no cuenta (`SessionStore.ScenePhase`,
# `SettingsStore.StrideOutcome` son valores, no stores).
#
# LO QUE ESTA REGLA NO ALCANZA, y por eso se conserva el criterio por nombre COMO RESPALDO:
# un receptor al que se llega a través de otro objeto (`root.sessionStore.isReconciling`)
# no se declara en el fichero que lo usa, así que su tipo no es derivable línea a línea.
# Para esos sigue valiendo el sufijo `store`/`Store`. Es decir: un receptor tipado se caza
# SIEMPRE, y uno encadenado solo si además se llama como se llama. El límite está
# registrado en `deferred-work.md`; no se anuncia como cubierto.
#
# Vale para los DOS stores. `SettingsStore.save()` dejó de ser `private` en la 2.3 —una
# extensión en otro fichero no ve lo privado—, así que `settingsStore.save()` compila desde
# una vista: escribe el fichero saltándose la intención, que es quien decide qué contarle a
# Paul. Por eso `save` está en la lista. La sección 9 NO lo cubría: allí se miran las
# llamadas al PUERTO (`loadSettings`/`saveSettings`), no los métodos del store.
# `saveStride(...)` sigue permitido: es una intención, y `save\b` no casa con ella.
store_types='(SessionStore|SettingsStore|HistoryStore|AchievementsStore)'
# Un identificador declarado con el tipo de un store. `[?!]?` admite el opcional; el
# `[^A-Za-z0-9_.]` final deja fuera los tipos anidados (`…Store.ScenePhase`).
store_decl="[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*(any[[:space:]]+)?$store_types[?!]?([^A-Za-z0-9_.]|\$)"
store_init="[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*$store_types\("
store_props='(persist|save|record|noteKilometerCrossing|reconcile|countSteps|stopCountingSteps|clearSnapshot|capLastSampleAt|beginWeatherForNewSession|cancelWeatherCapture|attachQuoteForNewSession|recordShownQuote|saveFinishedWalk|retrySavingFinishedWalk|finishedRecord|unsavedFinishedRecord|weatherCapture|stepCounting|storage|motion|clock|location|weather|random|quotes|settings|history|achievements|achievementCatalog|feedback)'

# Los identificadores de ESTE fichero declarados con el tipo de un store, uno por línea.
store_receivers_in() {
    {
        grep -oE "$store_decl" "$1" 2>/dev/null | sed -E 's/[[:space:]]*:.*$//'
        grep -oE "$store_init" "$1" 2>/dev/null | sed -E 's/[[:space:]]*=.*$//'
    } | sed -E 's/^[[:space:]]+//' | sort -u
}

for dir in "$ROOT/WalkTracker/UI" "$ROOT/WalkTracker/App"; do
    if [ ! -d "$dir" ]; then
        err "$dir" "no existe: el gate no puede comprobar que la UI y la app no escriben el estado de los stores (AD-7, AD-16) y no se declara en verde por no haber mirado."
        continue
    fi
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        # Respaldo por nombre (sin anclar a la izquierda, para que alcance a
        # `root.sessionStore.…`), más los receptores tipados de este fichero.
        recv='[sS]tore'
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            recv="$recv|(^|[^A-Za-z0-9_.])$name"
        done < <(store_receivers_in "$file")
        store_write="($recv)\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[^=]"
        store_internal="($recv)\.$store_props\b"
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            hit_line="${hit%%:*}"
            err "$file:$hit_line" "AD-7/AD-16: la UI y la app no escriben el estado de \`SessionStore\` ni de \`SettingsStore\`: solo leen y llaman a sus intenciones. Asignar una propiedad del store, llamar a \`persist\`, \`save\`, \`record\`, \`noteKilometerCrossing\`, \`reconcile\`, \`countSteps\`, \`stopCountingSteps\`, \`clearSnapshot\`, \`capLastSampleAt\`, \`beginWeatherForNewSession\`, \`cancelWeatherCapture\`, \`attachQuoteForNewSession\`, \`recordShownQuote\`, \`saveFinishedWalk\` o \`retrySavingFinishedWalk\`, tocar sus tareas \`stepCounting\`/\`weatherCapture\`, o usar \`storage\`/\`motion\`/\`clock\`/\`location\`/\`weather\`/\`random\`/\`quotes\`/\`settings\`/\`history\`/\`achievements\`/\`achievementCatalog\`/\`feedback\` del store es cosa de \`SessionStore*.swift\`, \`SettingsStore*.swift\`, \`HistoryStore*.swift\` y \`AchievementsStore*.swift\`."
        done < <(grep -nE "$store_write|$store_internal" "$file" 2>/dev/null)
    done < <(find "$dir" -name '*.swift' -type f 2>/dev/null | sort)
done

# ── Ayudantes de las secciones 7–10 ──────────────────────────────────────────
# Lo que puede ir delante de `import`: atributos, con o sin argumentos (`@testable`,
# `@preconcurrency`, `@_spi(X)`), y el nivel de acceso de Swift 6 (`internal import`).
import_prefix='^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'

# Un `import` de Swift en todas sus formas: con prefijo (ver arriba), de un símbolo
# (`import struct UIKit.UIApplication`) o de un submódulo
# (`import UIKit.UIGestureRecognizerSubclass`). Uso: `import_re 'A|B'`.
import_re() {
    echo "$import_prefix($1)\b"
}

# El módulo que importa una línea de `import`.
imported_module() {
    echo "$1" | sed -E "s/$import_prefix//; s/[.[:space:]].*\$//"
}

# Imprime `fichero:línea:código` de cada `.swift` bajo los directorios dados, sin los
# comentarios: quita `// …` hasta el final de la línea y los `/* … */`, anidados como
# en Swift y aunque ocupen varias líneas. Dentro de un literal de cadena (`"…"`, con
# escapes, y `"""…"""`, aunque ocupe varias líneas) `//` y `/*` no abren comentario; el
# contenido del literal se conserva, así que un nombre dentro de una cadena cuenta como
# código. No distingue las cadenas crudas (`#"…"#`): en ellas `\` no escapa.
# Si `find` o `awk` fallan, sale con estado ≠ 0: quien llama no puede dar el verde.
code_lines() {
    local dirs=()
    local d
    for d in "$@"; do
        [ -d "$d" ] && dirs+=("$d")
    done
    [ "${#dirs[@]}" -gt 0 ] || return 0
    find "${dirs[@]}" -name '*.swift' -type f -exec awk '
        FNR == 1 { depth = 0; instr = 0 }
        {
            line = $0; out = ""; i = 1; n = length(line)
            if (instr == 1) instr = 0
            while (i <= n) {
                c = substr(line, i, 1); two = substr(line, i, 2); three = substr(line, i, 3)
                if (depth > 0) {
                    if (two == "/*") { depth++; i += 2; continue }
                    if (two == "*/") { depth--; i += 2; if (depth == 0) out = out " "; continue }
                    i++; continue
                }
                if (instr > 0) {
                    if (c == "\\") { out = out two; i += 2; continue }
                    if (instr == 3 && three == "\"\"\"") { out = out three; i += 3; instr = 0; continue }
                    if (instr == 1 && c == "\"") { out = out c; i++; instr = 0; continue }
                    out = out c; i++; continue
                }
                if (three == "\"\"\"") { out = out three; i += 3; instr = 3; continue }
                if (c == "\"") { out = out c; i++; instr = 1; continue }
                if (two == "//") break
                if (two == "/*") { depth++; i += 2; continue }
                out = out c; i++
            }
            print FILENAME ":" FNR ":" out
        }
    ' {} +
}

# `code_lines` en la variable que se nombre; si el escaneo falla, lo dice y deja el gate
# en rojo. Uso: `scan_code_into VARIABLE "$dir"…`. Cada sección escanea en su propia
# variable: una sección que pisara `SCANNED` dejaría a la siguiente escaneando otro árbol.
scan_code_into() {
    local __var="$1"
    shift
    local __out
    if ! __out="$(code_lines "$@")"; then
        err "$1" "no se pudo escanear el código Swift de $*. El gate no se declara en verde sin haber comprobado."
        __out=""
    fi
    printf -v "$__var" '%s' "$__out"
}

# El caso común: el resultado queda en `SCANNED`. Uso: `scan_code "$dir"…`.
scan_code() {
    scan_code_into SCANNED "$@"
}

# Prefijo de `grep -E` sobre la salida de `code_lines`: el código empieza tras
# `fichero:línea:`, y lo buscado va al principio o tras un carácter que no es de nombre.
code_at='^[^:]+:[0-9]+:(.*[^A-Za-z0-9_])?'

# ── 7. CoreMotion y CoreLocation solo en su adapter (AD-10) ─────────────────
# `MotionAdapter` es el único que conoce CoreMotion, y `LocationAdapter` el único que conoce
# CoreLocation (2.1); el resto de la app habla con `MotionPort` y `LocationPort`. `Domain/`
# ya lo cubre la sección 4, y los tests de adapters quedan fuera.
# Uso: `framework_only_in MÓDULO SUBDIRECTORIO-DE-ADAPTERS EXPLICACIÓN`.
framework_only_in() {
    local module="$1" adapter_dir="$2" why="$3"
    [ -d "$ROOT/WalkTracker" ] || return 0
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        case "$hit_file" in
            "$ROOT/WalkTracker/Adapters/$adapter_dir/"*) continue ;;
        esac
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-10: $module solo en \`WalkTracker/Adapters/$adapter_dir/\`. Este fichero importa $module: $why"
    done < <(grep -rnE "$(import_re "$module")" "$ROOT/WalkTracker" --include='*.swift' 2>/dev/null)
}
framework_only_in CoreMotion Motion "el resto de la app cuenta pasos a través de \`MotionPort\`, que implementa \`MotionAdapter\`."
framework_only_in CoreLocation Location "el resto de la app pide la ubicación aproximada a través de \`LocationPort\`, que implementa \`LocationAdapter\` y redondea las coordenadas antes de entregarlas."

# ── 8. El dominio no lee el reloj ni el calendario del sistema (AD-3, AD-19) ─
# Todo instante entra por `ClockPort` (o como argumento), para que el dominio sea
# determinista y probable con vectores. Solo cuenta el código: los comentarios que
# nombran `Date()` —como el de `ClockPort`— no son una llamada.
if [ -d "$ROOT/Domain" ]; then
    time_call='(Date[[:space:]]*(\.[[:space:]]*init[[:space:]]*)?\([[:space:]]*(\)|timeIntervalSinceNow[[:space:]]*:)|Date[[:space:]]*\.[[:space:]]*now\b|Calendar[[:space:]]*\.[[:space:]]*(current|autoupdatingCurrent)\b)'
    scan_code "$ROOT/Domain"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        code="${rest#*:}"
        [[ "$code" =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && code="${BASH_REMATCH[1]}"
        err "$hit_file:$hit_line" "AD-3/AD-19: \`Domain/\` no lee el reloj ni el calendario del sistema (\`Date()\`, \`Date.init()\`, \`Date(timeIntervalSinceNow:)\`, \`Date.now\`, \`Calendar.current\`, \`Calendar.autoupdatingCurrent\`). El instante entra por \`ClockPort\` o como argumento (\`at now: Date\`). Código: \`$code\`"
    done < <(grep -E "$code_at$time_call" <<< "$SCANNED")
fi

# ── 9. Cada fichero de `StoragePort` tiene un dueño (AD-16) ─────────────────
# `StoragePort` es UN puerto con CUATRO ficheros y cuatro dueños distintos: `SessionStore`
# posee `activeSession.json`, `SettingsStore` posee `settings.json` (2.2), `HistoryStore`
# posee `sessions.json` (5.1) y `AchievementsStore` posee el `achievements.json` DEL SANDBOX
# (5.1) — que no es el catálogo congelado de `WalkTracker/Resources/`, que se llama igual y
# no pasa por este puerto. El compilador no los separa —todos ven el mismo protocolo—, así
# que se comprueba aquí.
#
# Se admiten las llamadas en el fichero dueño y en el adapter de persistencia, que las
# implementa. Las declaraciones (`func loadActiveSession`) no son llamadas, y los
# comentarios que las nombran tampoco; una línea que declara Y llama sí cuenta.
#
# Uso: `storage_owner_rule NOMBRES DUEÑO EXPLICACIÓN`.
# - NOMBRES: ERE de los métodos del puerto, sin `\b`.
# - DUEÑO: el nombre del tipo dueño. Quedan exentos **exactamente** dos formas de fichero
#   dentro de `WalkTracker/Application/`: `DUEÑO.swift` y sus extensiones `DUEÑO+Algo.swift`
#   (`SessionStore+Weather.swift`, y el `SettingsStore+Stride.swift` que traerá la 2.3). No es
#   un prefijo suelto: `SettingsStoreKit.swift`, `SessionStore.swift.bak` o un subdirectorio
#   que empiece igual (`SessionStoreKit/…`) NO quedan exentos.
storage_owner_rule() {
    local names="$1" owner="$2" why="$3"
    # Sin `\b`: se evalúa con `[[ =~ ]]`, y el ERE del sistema no lo garantiza.
    local call_bash="(^|[^A-Za-z0-9_])$names([^A-Za-z0-9_]|\$)"
    local hit hit_file rest hit_line code calls rel
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        case "$hit_file" in
            "$ROOT/WalkTracker/Adapters/Persistence/"*) continue ;;
            "$ROOT/WalkTracker/Application/"*)
                rel="${hit_file#"$ROOT/WalkTracker/Application/"}"
                # Un `/` en `$rel` no casa con ninguno de los dos patrones: los
                # subdirectorios quedan fuera sin comprobarlo aparte.
                case "$rel" in
                    "$owner.swift" | "$owner+"*".swift") continue ;;
                esac
                ;;
        esac
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        code="${rest#*:}"
        # Se quitan las declaraciones y se vuelve a buscar: lo que queda es una llamada.
        calls="$(sed -E "s/(^|[^A-Za-z0-9_])func[[:space:]]+$names/\1/g" <<< "$code")"
        [[ "$calls" =~ $call_bash ]] || continue
        err "$hit_file:$hit_line" "AD-16: $why"
    done < <(grep -E "$code_at$names\b" <<< "$SCANNED")
}

scan_code "$ROOT/WalkTracker" "$ROOT/Domain"
storage_owner_rule '(load|save|clear|setAside)ActiveSession' 'SessionStore' \
    "solo \`SessionStore\` usa el snapshot de \`StoragePort\`. \`loadActiveSession\`, \`saveActiveSession\`, \`clearActiveSession\` y \`setAsideActiveSession\` se llaman desde \`WalkTracker/Application/SessionStore*.swift\`; fuera de ahí se pide al store una intención."
storage_owner_rule '(load|save)Settings' 'SettingsStore' \
    "solo \`SettingsStore\` usa los ajustes de \`StoragePort\` (2.2). \`loadSettings\` y \`saveSettings\` se llaman desde \`WalkTracker/Application/SettingsStore.swift\`; fuera de ahí —incluido \`SessionStore\`, que le pide la ventana de frases recientes— se pide al store de ajustes una intención."
storage_owner_rule '(load|save)Sessions' 'HistoryStore' \
    "solo \`HistoryStore\` usa el historial de \`StoragePort\` (5.1). \`loadSessions\` y \`saveSessions\` se llaman desde \`WalkTracker/Application/HistoryStore*.swift\`; fuera de ahí —incluido \`SessionStore\`, que le entrega la caminata cerrada— se pide al store del historial una intención (\`append\`, \`contains\`). Lo que hay en \`sessions.json\` no se puede reconstruir: dos escritores serían dos formas de perderlo."
storage_owner_rule '(load|save)Achievements' 'AchievementsStore' \
    "solo \`AchievementsStore\` usa el estado de los logros de \`StoragePort\` (5.1). \`loadAchievements\` y \`saveAchievements\` se llaman desde \`WalkTracker/Application/AchievementsStore*.swift\`. Ojo: es el \`achievements.json\` del SANDBOX, no el catálogo congelado de \`WalkTracker/Resources/\`, que se llama igual, se lee del bundle y no pasa por este puerto (AD-5)."

# ── 9b. Dentro de `Application/`, el fichero de otro dueño se escribe por su intención ──
# El hueco equivalente al de la sección 6, un piso más adentro: el estado de un store y su
# `save()` tienen acceso de MÓDULO —una extensión en otro fichero no ve lo privado— y la
# sección 6 solo mira `UI/` y `App/`. `SessionStore` guarda el store de ajustes en una
# propiedad llamada `settings` y, desde la 5.1, el del historial en una llamada `history`, así
# que dentro de `Application/` compila `settings.settings = …`, `settings.save()` o
# `history.save { … }`: escribir el fichero de otro dueño saltándose su intención (AD-16).
# Esto existe porque YA PASÓ con los ajustes en la 2.2/2.3, no por si acaso.
#
# Exentos el fichero del dueño y sus extensiones `DUEÑO+Algo.swift`, con la misma regla de
# forma de la sección 9. Las llamadas a las intenciones (`settings.recordShownQuote(id:)`,
# `history.append(record)`, `history.contains(startedAt:)`) siguen permitidas: lo que se
# prohíbe es asignar su estado y escribir su fichero.
#
# Uso: `injected_owner_rule PROPIEDAD DUEÑO INTENCIONES`.
injected_owner_rule() {
    local property="$1" owner="$2" intentions="$3"
    local pattern="$property[[:space:]]*\.[[:space:]]*([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[^=]|save[[:space:]]*(\(|\{))"
    local hit hit_file rest hit_line rel
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        case "$hit_file" in
            "$ROOT/WalkTracker/Application/"*) ;;
            *) continue ;;
        esac
        rel="${hit_file#"$ROOT/WalkTracker/Application/"}"
        case "$rel" in
            "$owner.swift" | "$owner+"*".swift") continue ;;
        esac
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-16: \`$property\` es el store de otro dueño: desde \`Application/\` se le piden intenciones ($intentions), no se le asigna estado ni se le llama \`save()\`. Su estado y su escritura son de \`WalkTracker/Application/$owner*.swift\`, que es su único dueño."
    done < <(grep -E "$code_at$pattern" <<< "$SCANNED")
}

if [ -d "$ROOT/WalkTracker/Application" ]; then
    injected_owner_rule 'settings' 'SettingsStore' \
        "\`recordShownQuote\`, \`saveStride\`, \`clearStride\`, \`resolvedStrideM\`"
    injected_owner_rule 'history' 'HistoryStore' \
        "\`append\`, \`contains\`"
    injected_owner_rule 'achievements' 'AchievementsStore' \
        "\`unlockWeeklyGoal\` (3.1) y \`unlock(_:at:)\` (3.2)"
fi

# ── 10. Ninguna vista importa un framework de sistema (AD-10) ───────────────
# La UI solo pinta el estado del store y llama a sus intenciones. Sensores, salud,
# Live Activities, háptica, sonido y notificaciones entran por un puerto y su adapter.
# `UIKit` también, sin excepciones: para abrir Ajustes basta el `openURL` de SwiftUI.
# Como SwiftUI reexporta UIKit, prohibir el import no basta: también se buscan en el
# código los tipos de UIKit que una vista podría usar sin importarlo.
if [ -d "$ROOT/WalkTracker/UI" ]; then
    ui_banned='CoreMotion|CoreLocation|HealthKit|ActivityKit|WidgetKit|CoreHaptics|AVFoundation|AudioToolbox|UserNotifications|UIKit'
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        module="$(imported_module "${rest#*:}")"
        err "$hit_file:$hit_line" "AD-10: la UI no importa frameworks de sistema, y esta vista importa \`$module\`. CoreMotion, CoreLocation, HealthKit, ActivityKit, WidgetKit, CoreHaptics, AVFoundation, AudioToolbox, UserNotifications y UIKit entran por un puerto y su adapter; la vista lee el store."
    done < <(grep -rnE "$(import_re "$ui_banned")" "$ROOT/WalkTracker/UI" --include='*.swift' 2>/dev/null)

    uikit_symbol='UI(Application|Device|Screen|ViewController|View)\b'
    scan_code "$ROOT/WalkTracker/UI"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-10: la UI no usa UIKit, tampoco sin importarlo: \`UIApplication\`, \`UIDevice\`, \`UIScreen\`, \`UIViewController\` y \`UIView\` son cosa de un adapter. Ajustes se abre con el \`openURL\` de SwiftUI."
    done < <(grep -E "$code_at$uikit_symbol" <<< "$SCANNED")
fi

# ── 11. La red solo sale del adapter del clima (2.1, AD-10) ─────────────────
# Open-Meteo es la única llamada de red del producto, y la hace `OpenMeteoAdapter` por
# `WeatherPort`. Fuera de `WalkTracker/Adapters/Weather/` no se construye ni una petición
# (`URLRequest`) ni una sesión de red (`URLSession` y sus tipos) ni se importa `Network`. Solo
# cuenta el código: los comentarios que las nombran no son una llamada. Los tests quedan fuera.
network_symbol='(URLSession|URLRequest)'
scan_code "$ROOT/WalkTracker" "$ROOT/Domain"
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit_file="${hit%%:*}"
    case "$hit_file" in
        "$ROOT/WalkTracker/Adapters/Weather/"*) continue ;;
    esac
    rest="${hit#*:}"
    hit_line="${rest%%:*}"
    err "$hit_file:$hit_line" "AD-10: la red solo sale de \`WalkTracker/Adapters/Weather/\`. \`URLSession\`, \`URLRequest\` e \`import Network\` son del adapter del clima: la única llamada de red del producto es Open-Meteo, a través de \`WeatherPort\`."
done < <(grep -E "$code_at$network_symbol|^[^:]+:[0-9]+:$(import_re 'Network' | sed 's/^\^//')" <<< "$SCANNED")

# ── 12. La UI no cablea el vocabulario visual (AD-13, UX-DR3, AD-20) ────────
# El espaciado, el margen, el objetivo táctil de 44 pt, el radio de tarjeta, el relleno de
# una superficie y los tres colores propios viven en `WalkTracker/UI/Style/DesignTokens.swift`.
# Una vista que los reteclea rompe el vocabulario en silencio: no hay target de UI tests, y
# las cuatro superficies que faltan (anillo 3.1, logros 3.3, historial 5.2, ajustes 2.3)
# heredarían la erosión.
#
# La exención es de UN fichero, no de una carpeta: `Style/DesignTokens.swift` es la única
# definición del vocabulario, así que un `Style/AchievementBadge.swift` con un hexadecimal
# o un `minHeight: 44` es exactamente la erosión que esto impide. `Diagnostics/` queda fuera
# porque es `#if DEBUG` y está marcada para borrado en `deferred-work.md`.
#
# Lo que NO se prohíbe, y es deliberado: los valores que la spec decide no tokenizar
# —`spacing: 0`, `spacing: 2`, `.padding(.top, 48)`, `.frame(maxWidth: .infinity)`—. Se
# prohíben los peldaños de la escala de UX-DR3 (4, 8, 12, 16, 24) escritos a mano, que es
# reteclear el token; no todo número, que criminalizaría lo que a propósito no es token.
#
# Solo cuenta el código: `code_lines` quita los comentarios, así que un doc comment que
# cite `#CCFF00` o el 44 pt para explicarse no es una violación. Los literales de cadena SÍ
# cuentan, a propósito: un color escrito dentro de una cadena sigue siendo un color cableado.
if [ ! -d "$ROOT/WalkTracker/UI" ]; then
    err "$ROOT/WalkTracker/UI" "no existe \`WalkTracker/UI/\`: el gate no puede comprobar el vocabulario visual y no se declara en verde por no haber mirado."
else
    # Variable propia: `SCANNED` es de las secciones 7–11 y pisarla dejaría a una sección
    # futura heredando un escaneo reducido a `UI/`.
    scan_code_into UI_CODE "$ROOT/WalkTracker/UI"

    # Uso: `ui_token_rule PATRÓN EXPLICACIÓN`.
    ui_token_rule() {
        local pattern="$1" why="$2"
        local hit hit_file rest hit_line
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            hit_file="${hit%%:*}"
            case "$hit_file" in
                "$ROOT/WalkTracker/UI/Style/DesignTokens.swift" | "$ROOT/WalkTracker/UI/Diagnostics/"*) continue ;;
            esac
            rest="${hit#*:}"
            hit_line="${rest%%:*}"
            err "$hit_file:$hit_line" "AD-13/UX-DR3: $why Los tokens viven en \`WalkTracker/UI/Style/DesignTokens.swift\`."
        done < <(grep -E "$code_at$pattern" <<< "$UI_CODE")
    }

    # Un lado de marco numérico, en cualquiera de sus formas: `minHeight: 44` es la del
    # objetivo táctil, pero `.frame(height: 44)` y `.frame(width: 44, height: 44)` —la
    # forma habitual de un target cuadrado— son la misma decisión escrita de otra manera.
    # `.frame(maxWidth: .infinity)` no lleva número y sigue permitido.
    ui_token_rule '(min|max|ideal)?([Hh]eight|[Ww]idth)[[:space:]]*:[[:space:]]*[0-9]' \
        "el objetivo táctil mínimo de 44 pt es normativo (UX-DR3, AD-20) y no se reteclea: usa \`LayoutMetrics.touchTargetMin\`."
    # `[:(]` para que el modificador antiguo, `.cornerRadius(16)`, no esquive la regla.
    ui_token_rule 'cornerRadius[[:space:]]*[:(][[:space:]]*[0-9]' \
        "el radio de una superficie propia no se elige por pantalla: usa \`Radius.card\`."
    # `_` admitido: `0xCC_FF_00` es el mismo hexadecimal con separadores de Swift.
    ui_token_rule '(0[xX]|#)[0-9A-Fa-f][0-9A-Fa-f_]{2,}' \
        "AD-13: los colores se referencian, no se cablean en hexadecimal; los del producto son colorsets de \`Assets.xcassets\` con variante clara y oscura y contraste medido."
    # `Color.init(red:…)` es el mismo constructor escrito entero.
    ui_token_rule 'Color[[:space:]]*(\.[[:space:]]*init[[:space:]]*)?\([[:space:]]*((red|hue|white)[[:space:]]*:|\.(sRGB|sRGBLinear|displayP3))' \
        "AD-13: un color por componentes numéricas es un color cableado, y no tiene variante oscura ni contraste medido; usa \`Colors\` o un color del sistema."
    # Cualquier color CROMÁTICO del sistema, no un nombre concreto. La versión anterior de
    # esta regla vetaba `.orange` —el color que el chore de tokens sustituyó por incumplir
    # AA— y la primera pantalla posterior eligió `Color.red`, que en claro da 3,55:1 sobre
    # blanco y 3,18:1 sobre el gris agrupado: pasó el gate porque no se llamaba `.orange`.
    # Vetar la FAMILIA y exigir medición ataca la causa; vetar un nombre solo mueve la
    # puerta de sitio. Son los doce colores cromáticos con nombre de SwiftUI.
    #
    # Lo que NO veta, y es deliberado: los ROLES semánticos del sistema —`.primary`,
    # `.secondary`, `.tint`— y los acromáticos —`.black`, `.white`, `.gray`, `.clear`—.
    # El sistema garantiza el contraste de los roles y los adapta al tema y a los ajustes
    # de accesibilidad del usuario; aliasarlos añadiría indirección sin ganancia, que es la
    # regla de admisión que el propio fichero de tokens fija.
    #
    # La regla no distingue primer plano de fondo: un gate que trabaja línea a línea no
    # puede saber si un color pinta texto o una superficie, y el lado conservador es
    # prohibir la familia entera. Un color del producto vive en `Colors` y está medido.
    ui_token_rule '(Color[[:space:]]*)?\.[[:space:]]*(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown)\b' \
        "(UX-DR6) un color cromático del sistema no tiene contraste medido, y ya entró dos veces por esta puerta: \`.orange\` daba 2,20:1 sobre blanco y \`Color.red\` da 3,55:1, los dos por debajo del 4,5:1 que WCAG AA exige para texto normal. Los colores del producto viven en \`Colors\` (\`accent\`, \`estimated\`, \`error\`), con variante clara y oscura y ratios que la suite recalcula en cada ejecución. Los ROLES del sistema —\`.primary\`, \`.secondary\`, \`.tint\`— sí se usan: su contraste lo garantiza el sistema."
    # La escala de UX-DR3 reteclada. Solo sus cinco peldaños: `spacing: 0` y `spacing: 2`
    # no son tokens por decisión de la spec y siguen pasando.
    ui_token_rule '(spacing|minLength)[[:space:]]*:[[:space:]]*(4|8|12|16|24)\b' \
        "el espaciado es la escala de UX-DR3 y no se reteclea: usa \`Spacing.xs/s/m/l/xl\`."
    ui_token_rule '\.padding\(([^)]*[^A-Za-z0-9_.])?(4|8|12|16|24)\b' \
        "el margen y el relleno no se reteclean: usa \`LayoutMetrics.margin\`, \`Spacing\` o \`Surface\`."
fi

# ── 12b. `UIDesignRequiresCompatibility` prohibida en el Info.plist (AD-13) ──
# Liquid Glass se hereda del SDK de iOS 26 y no se desactiva. Se busca la KEY, no el
# nombre: el `Info.plist` la cita en un comentario para decir precisamente que está
# prohibida, y ese comentario no es una violación.
#
# La lista sale del manifiesto (`INFOPLIST_FILE`), no escrita a mano: un target nuevo con
# plist propio se comprueba solo. Si el manifiesto no declara ninguno —el arnés del camino
# rojo monta un árbol mínimo— se cae a los dos del producto, para no dejar de mirar.
#
# Un plist de la lista que NO exista es un fallo (B-5, 2026-09-20). Antes había un
# `[ -f "$plist" ] || continue` que se lo saltaba en silencio: borrados los dos
# `Info.plist`, el gate salía verde por no haber mirado (retro del Epic 2, D9). Vale para
# los dos orígenes de la lista: si el manifiesto declara un plist, tiene que estar; y si no
# declara ninguno, los dos del respaldo tienen que estar, porque si no tampoco se miró nada.
PLISTS="$(sed -nE 's/^[[:space:]]*INFOPLIST_FILE:[[:space:]]*"?([^"#]*[^"#[:space:]])"?[[:space:]]*$/\1/p' "$MANIFEST" | sort -u)"
PLISTS_SOURCE="declarado en \`project.yml\` (\`INFOPLIST_FILE\`)"
if [ -z "$PLISTS" ]; then
    PLISTS="WalkTracker/App/Info.plist
WalkTrackerActivity/Info.plist"
    PLISTS_SOURCE="el respaldo de esta sección, porque el manifiesto no declara ningún \`INFOPLIST_FILE\`"
fi
while IFS= read -r plist_rel; do
    [ -n "$plist_rel" ] || continue
    plist="$ROOT/$plist_rel"
    if [ ! -f "$plist" ]; then
        err "$plist" "AD-13: este \`Info.plist\` es $PLISTS_SOURCE y no existe. El gate no puede comprobar que no lleva \`UIDesignRequiresCompatibility\` y no se declara en verde por no haber mirado."
        continue
    fi
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        err "$plist:${hit%%:*}" "AD-13: \`UIDesignRequiresCompatibility\` está PROHIBIDA. Liquid Glass se hereda al compilar contra el SDK de iOS 26; además el sistema ignora la key al compilar para iOS 27+, así que desactivarlo solo aplaza la adopción."
    done < <(grep -nE '<key>[[:space:]]*UIDesignRequiresCompatibility[[:space:]]*</key>' "$plist")
done <<< "$PLISTS"

# ── 12c. El acento de la app es una decisión, no el azul por omisión (AD-13) ─
# `AccentColor.colorset` existe, pero sin esta key el sistema no lo toma como acento de la
# app: el chrome que tiñe solo —controles, barra de pestañas, `.tint` heredado— vuelve al
# azul del sistema POR OMISIÓN, no por decisión, y no falla nada. Verificado borrándola.
#
# Dos arreglos de B-5 (2026-09-20), los dos por el mismo defecto: la regla buscaba la key
# sobre `project.yml` ENTERO y no comprobaba a qué apunta.
#   · ANCLADA AL TARGET DE LA APP. Moverla al target de la extensión salía en verde con la
#     app sin acento. El target de la app se deriva de `type: application`; no se escribe a
#     mano, para que un target de app nuevo o renombrado no deje la comprobación colgando.
#   · EL COLORSET AL QUE APUNTA EXISTE. La key nombra un colorset del catálogo; borrarlo
#     dejaba la key apuntando a nada y el gate en verde.
ACCENT_KEY='ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'
ACCENT_NAME='AccentColor'
app_targets="$(awk -F'\t' '$2 == "type" && $3 == "application" { print $1 }' <<< "$TARGET_SETTINGS")"
if [ -z "$app_targets" ]; then
    err "$MANIFEST" "AD-13: el manifiesto no declara ningún target \`type: application\`, así que el gate no sabe a qué target pedirle \`$ACCENT_KEY\` y no se declara en verde por no haber mirado."
else
    while IFS= read -r app_target; do
        [ -n "$app_target" ] || continue
        accent="$(awk -F'\t' -v t="$app_target" -v k="$ACCENT_KEY" '$1 == t && $2 == k { v = $3 } END { print v }' <<< "$TARGET_SETTINGS")"
        if [ -z "$accent" ]; then
            err "$MANIFEST" "AD-13: el target de la app (\`$app_target\`) no fija \`$ACCENT_KEY: $ACCENT_NAME\`. Sin esa key EN SU TARGET el colorset \`$ACCENT_NAME\` existe y nadie lo mira: el acento de la app vuelve al azul del sistema por omisión, no por decisión, y \`.tint\` deja de resolver al acento elegido. Fijarla en otro target (la extensión, por ejemplo) no tiñe la app."
        elif [ "$accent" != "$ACCENT_NAME" ]; then
            err "$MANIFEST" "AD-13: el target de la app (\`$app_target\`) fija \`$ACCENT_KEY: $accent\`, y el acento del producto es el colorset \`$ACCENT_NAME\` (verde lima, decidido el 2026-09-18). Apuntar a otro colorset cambia el acento de toda la app sin tocar una sola vista."
        else
            # `-prune` y no `-not -path`: aquí cuelgan `node_modules/` (324 MB) y la referencia
            # v3, y descender en ellos costaba segundos en cada build.
            colorset="$(find "$ROOT" \
                \( -name '.git' -o -name 'node_modules' -o -name 'DerivedData' \
                   -o -name 'build' -o -name '.build' -o -name 'Pods' -o -name '*.xcodeproj' \) -prune \
                -o -type d -name "$accent.colorset" -print \
                2>/dev/null | sort | head -n 1)"
            if [ -z "$colorset" ]; then
                err "$MANIFEST" "AD-13: el target de la app (\`$app_target\`) fija \`$ACCENT_KEY: $accent\` y NO existe ningún \`$accent.colorset\` en el árbol: la key apunta a nada y el acento vuelve al azul del sistema. El colorset vive en un catálogo de \`Assets.xcassets\`, con variante clara y oscura y contraste medido."
            elif [ ! -f "$colorset/Contents.json" ]; then
                err "$colorset" "AD-13: \`$accent.colorset\` no tiene \`Contents.json\`, así que no define ningún color: la key \`$ACCENT_KEY\` del target de la app apunta a un colorset vacío."
            fi
        fi
    done <<< "$app_targets"
fi

# ── Veredicto ────────────────────────────────────────────────────────────────
if [ "$fail_count" -gt 0 ]; then
    echo "check-project-shape: $fail_count violación(es) de la forma del proyecto." >&2
    exit 1
fi

echo "check-project-shape: forma del proyecto correcta."
exit 0
