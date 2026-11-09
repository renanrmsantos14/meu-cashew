#!/usr/bin/env bash
# Uso: scripts/compilar.sh apk|apk-debug|web <destino-web>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/budget"
quando="$(TZ=America/Sao_Paulo date '+%d/%m/%Y %H:%M')"
case "${1:-}" in
  apk) flutter build apk --release --dart-define=MB_COMPILADO="$quando" ;;
  apk-debug) flutter build apk --debug --dart-define=MB_COMPILADO="$quando" ;;
  web) dest="${2:?informe a pasta de destino}"
       flutter build web --release --base-href /app/ --no-web-resources-cdn --web-renderer canvaskit --pwa-strategy none --dart-define=MB_COMPILADO="$quando"
       mkdir -p "$dest" && rsync -a --delete build/web/ "$dest/" ;;
  *) echo "Uso: $0 apk|apk-debug|web <destino>" >&2; exit 1 ;;
esac
