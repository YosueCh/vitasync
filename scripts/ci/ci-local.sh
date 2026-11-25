#!/bin/bash
# Reproduce LOCALMENTE los trabajos de .github/workflows/pruebas.yml (mismos comandos, mismo orden) y registra tiempos y resultados.
# No sustituye a GitHub Actions (el entorno es Windows y no Ubuntu), pero valida que cada paso del flujo funciona.
#   bash scripts/ci/ci-local.sh <carpeta de evidencias>      (se omite el trabajo seguridad-e2e: necesita los emuladores de Firebase)
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
SAL="${1:-$RAIZ/ci-local-evidencias}"
MVN="${MVN:-mvn}"
mkdir -p "$SAL"
export GITHUB_STEP_SUMMARY="$SAL/step-summary.md"; : > "$GITHUB_STEP_SUMMARY"
cd "$RAIZ"
resultados=()
inicio_total=$(date +%s)

trabajo() { # nombre, comando...
  local nombre="$1"; shift
  local t0=$(date +%s)
  echo "=== TRABAJO: $nombre ($(date +%H:%M:%S))"
  "$@" > "$SAL/$nombre.log" 2>&1
  local rc=$?
  local seg=$(( $(date +%s) - t0 ))
  echo "=== $nombre: $([ $rc -eq 0 ] && echo APROBADO || echo FALLÓ) en ${seg} s"
  resultados+=("$nombre|$rc|$seg")
}

job_automatizacion() {
  ( cd vitasync-backend && $MVN -B test -Dtest='Aut*' ) && node scripts/ci/resumen-surefire.mjs vitasync-backend/target/surefire-reports "AUT backend (AUT-03 y AUT-05)" \
  && ( cd vitasync-frontend/flutter-mobile-app && flutter pub get && flutter test test/automatizacion --reporter json > ../../aut-flutter.json ) \
  && node scripts/ci/resumen-flutter.mjs aut-flutter.json "AUT app (AUT-01, 02, 04 y 06)"
}
job_backend() { ( cd vitasync-backend && $MVN -B test ) ; rc=$?; node scripts/ci/resumen-surefire.mjs vitasync-backend/target/surefire-reports "Backend (JUnit)"; [ $rc -eq 0 ]; }
job_firmware() { ( cd vitasync-firmware-sim && dart pub get && dart test ); }
job_app() { ( cd vitasync-frontend/flutter-mobile-app && flutter pub get && flutter analyze && flutter test --coverage --reporter json > ../../flutter-resultados.json ); rc=$?; node scripts/ci/resumen-flutter.mjs flutter-resultados.json "App móvil (flutter test)"; [ $rc -eq 0 ]; }
job_web() { ( cd vitasync-frontend && npx ng test --watch=false && npx ng build ); }

trabajo 1-automatizacion job_automatizacion
trabajo 2-backend job_backend
trabajo 3-firmware job_firmware
trabajo 4-app job_app
trabajo 5-web job_web

echo; echo "RESUMEN DEL PIPELINE LOCAL (tiempo total $(( $(date +%s) - inicio_total )) s)"
for r in "${resultados[@]}"; do IFS='|' read -r n rc s <<< "$r"; printf "  %-18s %-9s %5s s\n" "$n" "$([ "$rc" = 0 ] && echo APROBADO || echo FALLÓ)" "$s"; done
echo "Resumen de pruebas por trabajo:"; grep -h -E "^(AUT|Backend|App)" "$SAL"/*.log | sed 's/^/  /'
