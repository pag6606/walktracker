#!/bin/bash
#
# Release a TestFlight (historia 8.3).
#
# Con el árbol en un estado verificable, archiva en Release con el toolchain
# congelado, sube el build a App Store Connect y etiqueta el commit con una versión
# SemVer que coincide con la del binario subido.
#
#   1. Precondiciones — Xcode 26.x, rama `main`, árbol limpio, HEAD == origin/main
#      (tras `git fetch --tags origin`), versión SemVer única en `project.yml`, etiqueta
#      libre y número de build mayor que cualquier build ya etiquetado. Se comprueban
#      TODAS y se dice qué falta de una vez. El ensayo no va a la red.
#   2. Gates — `check-project-shape.sh` y `verify-domain.sh` en verde.
#   3. Archivo — `xcodegen generate` y `xcodebuild archive` en Release, con
#      `CURRENT_PROJECT_VERSION` = número de build. El Info.plist del archivo tiene que
#      decir la versión y el build esperados, en la app y en la extensión.
#   4. Subida — `xcodebuild -exportArchive` con `Scripts/ExportOptions-testflight.plist`
#      (`destination: upload`, cuenta de Apple configurada en Xcode). Pide confirmación
#      explícita justo antes: un número de build subido no se puede reutilizar. HEAD y
#      el árbol se vuelven a comprobar tras los gates, tras el archivo y antes de subir.
#   5. Etiqueta — `v<MARKETING_VERSION>-build.<N>`, anotada, sobre el commit archivado.
#      Solo si la subida terminó bien. No se empuja: eso lo decide quien publica.
#
# Número de build: `git rev-list --count HEAD`. En `main` solo crece; aun así el script
# se niega si no supera el mayor build ya etiquetado (un rebase o un historial
# reescrito podría encogerlo).
#
# Uso:
#   bash Scripts/release-testflight.sh                 # pide escribir la etiqueta antes de subir
#   bash Scripts/release-testflight.sh --confirm v4.0.0-build.42
#                                                      # confirmación no interactiva; tiene que
#                                                      # coincidir con la etiqueta calculada
#   bash Scripts/release-testflight.sh --dry-run       # cualquier rama con árbol limpio: archiva y
#                                                      # exporta un .ipa local, sin subir ni etiquetar
#
# Salida en `build/release/<etiqueta>[-ensayo]/` (ignorado por git): archivo, logs e .ipa.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_OPTIONS="$ROOT/Scripts/ExportOptions-testflight.plist"
REQUIRED_XCODE_MAJOR=26
RELEASE_BRANCH=main
SCHEME=WalkTracker
APP_NAME=WalkTracker
EXTENSION_NAME=WalkTrackerActivity

say() { echo "release-testflight: $1"; }
die() { echo "release-testflight: $1" >&2; exit 1; }
section() { printf '\n── %s ─────────────────────────────────────────\n' "$1"; }

usage() {
    sed -n '/^# Uso:/,/^# Salida/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── Argumentos ───────────────────────────────────────────────────────────────
DRY_RUN=0
CONFIRM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --confirm)
            shift
            [ $# -gt 0 ] || die "--confirm necesita la etiqueta que se va a subir (p. ej. v4.0.0-build.42)."
            CONFIRM="$1"
            ;;
        --confirm=*) CONFIRM="${1#--confirm=}" ;;
        -h | --help) usage; exit 0 ;;
        *) die "argumento desconocido: '$1'. Usa --help." ;;
    esac
    shift
done

if [ "$DRY_RUN" -eq 1 ] && [ -n "$CONFIRM" ]; then
    die "--confirm no tiene sentido con --dry-run: el ensayo no sube nada."
fi

MODE="release"
[ "$DRY_RUN" -eq 1 ] && MODE="ensayo (--dry-run)"

# ── 1. Precondiciones ────────────────────────────────────────────────────────
section "1/5 · Precondiciones ($MODE)"

problems=()

# Toolchain (AD-2, SPEC OQ-5): otra versión mayor de Xcode no archiva.
if ! command -v xcodebuild >/dev/null 2>&1; then
    problems+=("no hay xcodebuild en el PATH. El ciclo exige Xcode $REQUIRED_XCODE_MAJOR.x (26.3 verificado).")
else
    xcode_line="$(xcodebuild -version 2>/dev/null | head -n 1)"
    xcode_major="$(sed -nE 's/^Xcode ([0-9]+)(\.[0-9]+)*.*$/\1/p' <<< "$xcode_line")"
    if [ -z "$xcode_major" ]; then
        problems+=("no se pudo leer la versión de Xcode (xcodebuild -version dijo: '${xcode_line:-nada}').")
    elif [ "$xcode_major" != "$REQUIRED_XCODE_MAJOR" ]; then
        problems+=("toolchain equivocado: encontrado '$xcode_line'; el ciclo exige Xcode $REQUIRED_XCODE_MAJOR.x (26.3 verificado). No se archiva con otra versión mayor.")
    else
        say "toolchain: $xcode_line."
    fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    problems+=("xcodegen no está instalado (brew install xcodegen): el proyecto no se versiona y hay que regenerarlo.")
fi

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "$ROOT no es un repositorio git: no hay commit que etiquetar ni número de build."
fi

HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
branch="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(HEAD separado)")"
if [ "$DRY_RUN" -eq 0 ] && [ "$branch" != "$RELEASE_BRANCH" ]; then
    problems+=("rama equivocada: estás en '$branch'. Solo se sube desde '$RELEASE_BRANCH' (el ensayo --dry-run vale en cualquier rama).")
fi

dirty="$(git -C "$ROOT" status --porcelain --untracked-files=all)"
if [ -n "$dirty" ]; then
    count="$(wc -l <<< "$dirty" | tr -d ' ')"
    listing="$(head -n 10 <<< "$dirty" | sed 's/^/      /')"
    problems+=("árbol sucio: $count cambio(s) sin commit. El binario tiene que salir de un commit exacto:
$listing")
fi

# Versión: `project.yml` es la única fuente, y tiene que haber UNA definición.
version_lines="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$ROOT/project.yml" 2>/dev/null)"
version_count="$(grep -c . <<< "$version_lines")"
VERSION="$(head -n 1 <<< "$version_lines" | sed -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
if [ -z "$version_lines" ]; then
    problems+=("project.yml no define MARKETING_VERSION: es la única fuente de la versión.")
    VERSION="?"
elif [ "$version_count" -ne 1 ]; then
    problems+=("project.yml define MARKETING_VERSION $version_count veces: tiene que ser una sola, en settings.base.")
elif ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    problems+=("MARKETING_VERSION '$VERSION' no es SemVer MAJOR.MINOR.PATCH.")
fi

BUILD="$(git -C "$ROOT" rev-list --count HEAD)"
TAG="v${VERSION}-build.${BUILD}"
say "rama: $branch · commit: ${HEAD_SHA:0:12} · versión: $VERSION · build: $BUILD · etiqueta: $TAG."

if [ "$DRY_RUN" -eq 0 ]; then
    # Los PR se fusionan en GitHub: un `main` sin pull subiría un commit que no es el
    # fusionado, y las etiquetas creadas en otro clon no se verían. El ensayo no va a
    # la red.
    if ! git -C "$ROOT" fetch --quiet --tags origin "+refs/heads/$RELEASE_BRANCH:refs/remotes/origin/$RELEASE_BRANCH"; then
        problems+=("no se pudo hacer git fetch --tags de origin: sin él no se sabe si este commit es el de GitHub ni qué builds están ya etiquetados.")
    else
        origin_sha="$(git -C "$ROOT" rev-parse --quiet --verify "refs/remotes/origin/$RELEASE_BRANCH" 2>/dev/null)"
        if [ "$origin_sha" != "$HEAD_SHA" ]; then
            problems+=("HEAD (${HEAD_SHA:0:12}) no es origin/$RELEASE_BRANCH (${origin_sha:0:12}): se subiría un commit que no es el fusionado en GitHub. git pull o git push, y otra vez.")
        fi
    fi

    if git -C "$ROOT" rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
        problems+=("la etiqueta $TAG ya existe: ese build ya se subió. Un número de build no se reutiliza: hace falta un commit nuevo en $RELEASE_BRANCH.")
    fi

    # Monotonía: ningún build ya etiquetado puede igualar o superar este.
    highest=0
    highest_tag=""
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        n="${t##*-build.}"
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        if [ "$n" -gt "$highest" ]; then
            highest="$n"
            highest_tag="$t"
        fi
    done < <(git -C "$ROOT" tag -l 'v*-build.*')
    if [ "$highest" -ge "$BUILD" ] && [ "$highest_tag" != "$TAG" ]; then
        problems+=("el build $BUILD no supera el mayor ya etiquetado ($highest_tag). El número de build solo crece: ¿historial reescrito o rama atrasada?")
    fi

    # La confirmación no interactiva se valida ANTES de archivar: no se gastan diez
    # minutos para descubrir al final que no se podía subir.
    if [ -n "$CONFIRM" ] && [ "$CONFIRM" != "$TAG" ]; then
        problems+=("--confirm '$CONFIRM' no coincide con la etiqueta calculada $TAG. No se sube un build distinto del confirmado.")
    elif [ -z "$CONFIRM" ] && ! [ -t 0 ]; then
        problems+=("sin terminal interactiva no se puede confirmar la subida. Pasa --confirm $TAG, solo con la confirmación explícita de Paul.")
    fi
fi

if [ "${#problems[@]}" -gt 0 ]; then
    echo >&2
    for p in "${problems[@]}"; do
        echo "  ✗ $p" >&2
    done
    echo >&2
    die "no se archiva: ${#problems[@]} precondición(es) sin cumplir."
fi
say "precondiciones en verde."

# ── 2. Gates ─────────────────────────────────────────────────────────────────
section "2/5 · Gates"
if ! bash "$ROOT/Scripts/check-project-shape.sh" "$ROOT"; then
    die "check-project-shape.sh en rojo: no se archiva."
fi
if ! bash "$ROOT/Scripts/verify-domain.sh"; then
    die "verify-domain.sh en rojo: no se archiva."
fi

# Nada puede mover el commit ni ensuciar el árbol entre las precondiciones y la
# subida: lo que se sube es exactamente lo que se etiqueta. Se comprueba tras los
# gates, tras el archivo y justo antes de exportar.
assert_unchanged() {
    local when="$1" what="$2"
    if [ "$(git -C "$ROOT" rev-parse HEAD)" != "$HEAD_SHA" ]; then
        die "HEAD cambió $when: no se $what."
    fi
    if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]; then
        die "el árbol quedó sucio $when: no se $what."
    fi
}
assert_unchanged "mientras corrían los gates" "archiva"

# ── 3. Archivo ───────────────────────────────────────────────────────────────
section "3/5 · Archivo Release"
OUT="$ROOT/build/release/$TAG"
[ "$DRY_RUN" -eq 1 ] && OUT="$OUT-ensayo"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT/export"
rm -rf "$OUT"
mkdir -p "$OUT" || die "no se pudo crear $OUT."

if ! (cd "$ROOT" && xcodegen generate --quiet); then
    die "xcodegen generate falló: no se archiva."
fi

say "archivando (log: $OUT/archive.log)…"
(cd "$ROOT" && xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD") 2>&1 | tee "$OUT/archive.log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ] || ! grep -q '\*\* ARCHIVE SUCCEEDED \*\*' "$OUT/archive.log"; then
    grep -E 'error:|\*\* ARCHIVE' "$OUT/archive.log" | head -n 30 | sed 's/^/  /' >&2
    die "xcodebuild archive salió con $status. Log completo: $OUT/archive.log"
fi

# Un archivo "genérico" (sin `ApplicationProperties`) no se puede distribuir a App
# Store Connect: pasa con cualquier target que se instale fuera de la app
# (`SKIP_INSTALL: NO`). Xcode lo dice tarde y mal ("expected one {}"); aquí, claro.
if ! plutil -extract ApplicationProperties.ApplicationPath raw -o - "$ARCHIVE/Info.plist" >/dev/null 2>&1; then
    extras="$(cd "$ARCHIVE/Products" 2>/dev/null && find . -mindepth 2 -maxdepth 2 -not -path './Applications/*' | sed 's:^\./:      :')"
    die "el archivo es genérico, no de app iOS: App Store Connect no lo acepta. Algún target se instala fuera de la app (¿SKIP_INSTALL: NO?):
${extras:-      (sin productos fuera de Applications/)}"
fi

# El binario tiene que decir lo que dirá la etiqueta. En la app y en la extensión:
# App Store Connect rechaza una extensión con otra versión que su app.
plist_value() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
for bundle in \
    "Products/Applications/$APP_NAME.app/Info.plist" \
    "Products/Applications/$APP_NAME.app/PlugIns/$EXTENSION_NAME.appex/Info.plist"; do
    plist="$ARCHIVE/$bundle"
    [ -f "$plist" ] || die "el archivo no contiene $bundle: no se exporta."
    got_version="$(plist_value "$plist" CFBundleShortVersionString)"
    got_build="$(plist_value "$plist" CFBundleVersion)"
    if [ "$got_version" != "$VERSION" ] || [ "$got_build" != "$BUILD" ]; then
        die "$bundle dice versión '$got_version' build '$got_build'; se esperaba $VERSION ($BUILD). No se exporta."
    fi
done
say "archivo correcto: $APP_NAME $VERSION ($BUILD)."
assert_unchanged "mientras se archivaba" "exporta"

# ── 4. Exportación / subida ──────────────────────────────────────────────────
OPTIONS="$OUT/ExportOptions.plist"
cp "$EXPORT_OPTIONS" "$OPTIONS" || die "no se encontró $EXPORT_OPTIONS."
if [ "$DRY_RUN" -eq 1 ]; then
    section "4/5 · Exportación local (ensayo, sin subida)"
    plutil -replace destination -string export "$OPTIONS" || die "no se pudo preparar la copia de ExportOptions."
else
    section "4/5 · Subida a App Store Connect"
    if [ -z "$CONFIRM" ]; then
        echo "Vas a subir $APP_NAME $VERSION ($BUILD) a App Store Connect."
        echo "El build $BUILD quedará gastado para siempre, suba bien o no."
        printf 'Escribe %s para subir: ' "$TAG"
        read -r answer
        [ "$answer" = "$TAG" ] || die "subida cancelada. Nada subido ni etiquetado."
    fi
fi
assert_unchanged "antes de exportar" "exporta"

SPENT="el build $BUILD puede haber llegado ya a App Store Connect y quedar gastado. Para reintentar hace falta un commit nuevo en origin/$RELEASE_BRANCH (vale git commit --allow-empty, empujado) y otro release."
if [ "$DRY_RUN" -eq 0 ]; then
    trap 'echo; echo "release-testflight: subida interrumpida: NO se etiqueta; $SPENT" >&2; exit 130' INT TERM
fi

say "exportando (log: $OUT/export.log)…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates 2>&1 | tee "$OUT/export.log"
status=${PIPESTATUS[0]}
trap - INT TERM
if [ "$status" -ne 0 ] || ! grep -q '\*\* EXPORT SUCCEEDED \*\*' "$OUT/export.log"; then
    grep -iE 'error|rejected|failed|invalid' "$OUT/export.log" | head -n 30 | sed 's/^/  /' >&2
    if grep -q 'No Accounts' "$OUT/export.log"; then
        echo "  → Xcode no tiene ninguna cuenta de Apple. Xcode → Ajustes → Cuentas → +, con el Apple ID del equipo $(plutil -extract teamID raw -o - "$OPTIONS" 2>/dev/null). Sin ella no hay firma de distribución ni subida." >&2
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        die "la exportación salió con $status. Log completo: $OUT/export.log"
    fi
    die "la subida salió con $status: NO se etiqueta; $SPENT Log completo: $OUT/export.log"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    ipa="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -type f | head -n 1)"
    [ -n "$ipa" ] || die "la exportación dijo que terminó pero no hay .ipa en $EXPORT_DIR."
    section "5/5 · Resultado del ensayo"
    say "versión: $VERSION · build provisional: $BUILD · etiqueta provisional: $TAG."
    say "el número es una vista previa: el real se calcula en $RELEASE_BRANCH al hacer el release."
    say ".ipa: $ipa"
    say "ensayo: sin subida ni etiqueta."
    exit 0
fi

# ── 5. Etiqueta ──────────────────────────────────────────────────────────────
section "5/5 · Etiqueta"
if ! git -C "$ROOT" tag -a "$TAG" "$HEAD_SHA" -m "TestFlight: $APP_NAME $VERSION ($BUILD)"; then
    die "el build $BUILD SE SUBIÓ pero no se pudo crear la etiqueta $TAG. Créala a mano: git tag -a $TAG $HEAD_SHA"
fi
say "versión: $VERSION · build: $BUILD · etiqueta: $TAG (commit ${HEAD_SHA:0:12})."
say "subido. App Store Connect tarda unos minutos en procesarlo antes de aparecer en TestFlight."
say "publica la etiqueta cuando quieras: git push origin $TAG"
exit 0
