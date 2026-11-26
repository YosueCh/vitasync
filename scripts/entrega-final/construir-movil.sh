#!/bin/bash
# Compila la vista móvil (Flutter Web / PWA) con la ruta base /movil/ y la copia al sitio Angular (vitasync-frontend/public/movil/),
# que la sirve junto con el resto del sitio. Parcial 3 de la propuesta.
#   bash scripts/entrega-final/construir-movil.sh [-- opciones extra de flutter, p. ej. --dart-define=AUTH_BASE=https://identitytoolkit.googleapis.com --dart-define=FIREBASE_API_KEY=<clave web>]
set -e
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ/vitasync-frontend/flutter-mobile-app"
export MSYS_NO_PATHCONV=1   # Git Bash convertiría /movil/ en una ruta de Windows
flutter pub get
flutter build web --release --base-href /movil/ "$@"
rm -rf "$RAIZ/vitasync-frontend/public/movil"
cp -r build/web "$RAIZ/vitasync-frontend/public/movil"
echo "Vista móvil lista en vitasync-frontend/public/movil/ ($(du -sh "$RAIZ/vitasync-frontend/public/movil" | cut -f1))"
