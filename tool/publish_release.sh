#!/usr/bin/env bash
# Copiado idéntico en firma-digital, mobile-order-flutter y kiosko-pos-flutter.
#
# Sube los instaladores de una versión al bucket privado de R2 y la registra
# en el ERP como borrador (se publica después desde Landlord → Apps).
#
#   tool/publish_release.sh <plataforma> <archivo>...
#
# Cada archivo se llama <APP>-<VERSION>-<abi>.apk (abi "universal" = sin ABI)
# o, en escritorio, cualquier nombre (va sin ABI).
#
# Variables: APP, VERSION, CHANNEL, NOTES_FILE, R2_ENDPOINT, R2_BUCKET,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, ERP_URL, ERP_TOKEN.
set -euo pipefail

platform="$1"
shift

: "${APP:?}" "${VERSION:?}" "${CHANNEL:?}" "${NOTES_FILE:?}"
: "${R2_ENDPOINT:?}" "${R2_BUCKET:?}" "${ERP_URL:?}" "${ERP_TOKEN:?}"

# R2 no acepta los checksums que el AWS CLI v2 manda por defecto.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

prefix="apps/${APP}/${platform}/${VERSION}"
assets='[]'
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT

for file in "$@"; do
  name="$(basename "$file")"
  abi=null
  if [[ "$name" == "${APP}-${VERSION}-"*.apk ]]; then
    suffix="${name#"${APP}-${VERSION}-"}"
    suffix="${suffix%.apk}"
    [[ "$suffix" != "universal" ]] && abi="\"${suffix}\""
  fi

  echo "Subiendo ${name}…"
  aws s3 cp "$file" "s3://${R2_BUCKET}/${prefix}/${name}" \
    --endpoint-url "$R2_ENDPOINT" --region auto --only-show-errors

  assets="$(jq -c \
    --argjson abi "$abi" \
    --arg path "${prefix}/${name}" \
    --arg filename "$name" \
    --arg sha256 "$(sha256sum "$file" | cut -d' ' -f1)" \
    --argjson size "$(stat -c%s "$file")" \
    '. + [{abi: $abi, path: $path, filename: $filename, sha256: $sha256, size: $size}]' <<<"$assets")"
done

jq -n \
  --arg app "$APP" --arg platform "$platform" --arg channel "$CHANNEL" --arg version "$VERSION" \
  --rawfile notes "$NOTES_FILE" --argjson assets "$assets" \
  '{app: $app, platform: $platform, channel: $channel, version: $version, notes: $notes, assets: $assets}' \
  > "$payload"

echo "Registrando ${APP} ${VERSION} (${platform}, ${CHANNEL}) en el ERP…"
curl --fail-with-body -sS --retry 3 --retry-all-errors \
  -X POST "${ERP_URL%/}/api/app-releases" \
  -H "Authorization: Bearer ${ERP_TOKEN}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data "@${payload}"
echo
