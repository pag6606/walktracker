#!/bin/bash
#
# Informe de la caminata del gate 8.4.
#
# Lee el registro de medición de la app (`OSLog`, subsistema `com.walktracker.app`,
# categoría `Medicion`) y escribe el informe con `Scripts/walk-report/report.js`.
#
# Acepta:
#   - un `.logarchive` (o cualquier directorio): lo extrae con `log show --archive`;
#   - un fichero de texto ya exportado con `log show` en estilo default, compact o syslog
#     (json y ndjson se rechazan con un mensaje claro).
#
# Protocolo completo en README.md, sección "Gate 8.4". Resumen:
#   sudo log collect --device --last 2h --output caminata.logarchive
#   bash Scripts/walk-report.sh caminata.logarchive
#
# Sale ≠ 0 si el registro no existe, si `log show` falla o si no hay líneas de medición.
#
# Uso:  bash Scripts/walk-report.sh <archivo.logarchive | registro.txt>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="$SCRIPT_DIR/walk-report/report.js"
PREDICATE='subsystem == "com.walktracker.app" AND category == "Medicion"'

if [ $# -ne 1 ]; then
    echo "Uso: bash Scripts/walk-report.sh <archivo.logarchive | registro.txt>" >&2
    exit 2
fi
INPUT="$1"

if [ ! -e "$INPUT" ]; then
    echo "walk-report: no existe '$INPUT'." >&2
    exit 2
fi

if ! command -v node >/dev/null 2>&1; then
    echo "walk-report: hace falta node para el informe." >&2
    exit 2
fi

if [ -d "$INPUT" ]; then
    if ! command -v log >/dev/null 2>&1; then
        echo "walk-report: '$INPUT' es un archivo de log y hace falta \`log\` (macOS) para leerlo." >&2
        exit 2
    fi
    TEXT="$(mktemp "${TMPDIR:-/tmp}/walk-report.XXXXXX")" || exit 2
    trap 'rm -f "$TEXT" "$TEXT.err"' EXIT
    # `notice` es el nivel por defecto de `log show`: no hace falta `--info`.
    if ! log show --archive "$INPUT" --style compact --predicate "$PREDICATE" >"$TEXT" 2>"$TEXT.err"; then
        echo "walk-report: \`log show\` no pudo leer '$INPUT':" >&2
        cat "$TEXT.err" >&2
        exit 1
    fi
    node "$REPORT" "$TEXT"
    exit $?
fi

node "$REPORT" "$INPUT"
exit $?
