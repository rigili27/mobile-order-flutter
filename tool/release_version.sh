#!/usr/bin/env bash
# Copiado idéntico en firma-digital, mobile-order-flutter y kiosko-pos-flutter.
#
# A partir del tag (vX.Y.Z o vX.Y.Z-beta) escribe en $GITHUB_OUTPUT:
#   version  X.Y.Z (tiene que coincidir con `version:` del pubspec.yaml)
#   channel  stable | beta
#   build    versionCode de Android = (X*10000 + Y*100 + Z) * 10000
#
# El * 10000 deja lugar a los +1000/+2000/+4000 que Flutter le suma al
# versionCode de cada APK partido por ABI: así un cambio de versión siempre
# pesa más que la diferencia entre ABIs, y el APK universal de la versión
# siguiente nunca queda por debajo del APK por ABI de la anterior.
set -euo pipefail

tag="${1:?uso: release_version.sh <tag>}"
raw="${tag#v}"
channel=stable
if [[ "$raw" == *-beta ]]; then
  channel=beta
  raw="${raw%-beta}"
fi

if [[ ! "$raw" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::Tag inválido: ${tag} (se espera vX.Y.Z o vX.Y.Z-beta)"
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

if (( minor > 99 || patch > 99 || major > 20 )); then
  echo "::error::Versión fuera de rango: ${raw} (menor y parche hasta 99, mayor hasta 20)"
  exit 1
fi

pubspec="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
if [[ "$raw" != "$pubspec" ]]; then
  echo "::error::El tag ${tag} no coincide con version: ${pubspec} del pubspec.yaml"
  exit 1
fi

build=$(( (major * 10000 + minor * 100 + patch) * 10000 ))

{
  echo "version=${raw}"
  echo "channel=${channel}"
  echo "build=${build}"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
