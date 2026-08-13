#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  bash scripts/field-test/collect-ios-field-log.sh \
    --case-id D1-NOISE-01 \
    --run-id RUN-20260813T230000Z \
    --node-alias IOS-A \
    --device-id <identificador-devicectl> \
    [--duration 240] \
    [--bundle-id com.hearthbit.app] \
    [--output-dir artifacts/field-test]

Requisitos:
  - macOS con Xcode 15 o posterior y Command Line Tools seleccionadas.
  - iPhone con iOS 17 o posterior, confiable, desbloqueado, con Developer Mode
    y HearthBit instalado (`devicectl` no admite captura en iOS 16).
  - El identificador se obtiene con: xcrun devicectl list devices

La captura usa `devicectl ... process launch --console --terminate-existing`,
por lo que reinicia HearthBit en el iPhone. No guarda el identificador del
dispositivo. Toda salida se sanea antes de escribirse y el resultado queda
PENDING.
EOF
}

case_id=''
run_id=''
node_alias=''
device_id=''
duration=240
bundle_id='com.hearthbit.app'
output_dir=''

while (($# > 0)); do
  case "$1" in
    --case-id)
      case_id="${2:-}"
      shift 2
      ;;
    --run-id)
      run_id="${2:-}"
      shift 2
      ;;
    --node-alias)
      node_alias="${2:-}"
      shift 2
      ;;
    --device-id)
      device_id="${2:-}"
      shift 2
      ;;
    --duration)
      duration="${2:-}"
      shift 2
      ;;
    --bundle-id)
      bundle_id="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento desconocido: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$case_id" =~ ^D1-[A-Z0-9]+(-[A-Z0-9]+)*$ ]] || {
  printf 'case-id no cumple el formato D1-...\n' >&2
  exit 2
}
[[ "$run_id" =~ ^[A-Z0-9][A-Z0-9_-]{5,63}$ ]] || {
  printf 'run-id no cumple el formato seguro esperado.\n' >&2
  exit 2
}
[[ "$node_alias" =~ ^[A-Z0-9][A-Z0-9-]{1,31}$ ]] || {
  printf 'node-alias no cumple el formato seguro esperado.\n' >&2
  exit 2
}
[[ "$device_id" =~ ^[A-Za-z0-9._:-]+$ ]] || {
  printf 'device-id está vacío o contiene caracteres no permitidos.\n' >&2
  exit 2
}
[[ "$duration" =~ ^[0-9]+$ ]] && ((duration >= 10 && duration <= 3600)) || {
  printf 'duration debe estar entre 10 y 3600 segundos.\n' >&2
  exit 2
}
[[ "$bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || {
  printf 'bundle-id no cumple el formato esperado.\n' >&2
  exit 2
}

for dependency in xcrun perl shasum awk; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf 'Falta el requisito: %s\n' "$dependency" >&2
    exit 127
  }
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
if [[ -z "$output_dir" ]]; then
  output_dir="$repository_root/artifacts/field-test"
elif [[ "$output_dir" != /* ]]; then
  output_dir="$repository_root/$output_dir"
fi

started_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
capture_name="$timestamp-$case_id-$run_id-$node_alias"
capture_dir="$output_dir/$capture_name"
partial_dir="$capture_dir.partial.$$"
fifo_path="$partial_dir/console.fifo"
log_name='ios-hearthbit-sanitized.log'
log_path="$partial_dir/$log_name"
capture_pid=''
sanitizer_pid=''

if [[ -e "$capture_dir" ]]; then
  printf 'La captura ya existe y no se sobrescribirá: %s\n' "$capture_dir" >&2
  exit 1
fi

mkdir -p "$output_dir"
mkdir "$partial_dir"
mkfifo "$fifo_path"

cleanup() {
  if [[ -n "$capture_pid" ]]; then
    kill -INT "$capture_pid" 2>/dev/null || true
  fi
  if [[ -n "$sanitizer_pid" ]]; then
    kill "$sanitizer_pid" 2>/dev/null || true
  fi
  rm -f "$fifo_path"
}
trap cleanup EXIT HUP INT TERM

sanitize_stream() {
  perl -pe '
    s/\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/[MAC_REDACTED]/g;
    s/\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b/[UUID_REDACTED]/g;
    s/\b[0-9A-Fa-f]{8,}-[0-9A-Fa-f-]{8,}\b/[DEVICE_ID_REDACTED]/g;
    s/\b(Bearer)\s+\S+/$1 [SECRET_REDACTED]/gi;
    s/\b(token|secret|password|authorization|private[_ -]?key)\s*[:=]\s*\S+/$1=[SECRET_REDACTED]/gi;
    s/\b(address|sender|recipient|peer|from|to)\s*[:=]\s*[0-9A-Fa-f]{8,}/$1=[PEER_REDACTED]/gi;
    s/\b(latitude|longitude|lat|lon)\s*[:=]\s*-?[0-9]+(?:\.[0-9]+)?/$1=[COORDINATE_REDACTED]/gi;
    s/\b(local[_ -]?name|device[_ -]?name|nickname)\s*[:=]\s*[^\s,;]+/$1=[NAME_REDACTED]/gi;
    s/\bon\s+["‘][^"’]+["’]/on [DEVICE_NAME_REDACTED]/gi;
    s/\b[0-9A-Fa-f]{32,}\b/[HEX_REDACTED]/g;
  '
}

sanitize_stream <"$fifo_path" >"$log_path" &
sanitizer_pid=$!

printf 'Capturando %s en %s durante %s s...\n' "$case_id" "$node_alias" "$duration"
printf 'La app se iniciará mediante devicectl. Realice únicamente el caso indicado.\n'

xcrun devicectl device process launch \
  --device "$device_id" \
  --console \
  --terminate-existing \
  "$bundle_id" >"$fifo_path" 2>&1 &
capture_pid=$!

sleep 2
if ! kill -0 "$capture_pid" 2>/dev/null; then
  set +e
  wait "$capture_pid"
  launch_status=$?
  wait "$sanitizer_pid"
  set -e
  capture_pid=''
  sanitizer_pid=''
  printf 'devicectl terminó antes de iniciar la captura (código %s). Revise %s\n' \
    "$launch_status" "$log_path" >&2
  exit 1
fi

sleep "$((duration - 2))"
kill -INT "$capture_pid" 2>/dev/null || true
set +e
wait "$capture_pid"
wait "$sanitizer_pid"
set -e
capture_pid=''
sanitizer_pid=''
rm -f "$fifo_path"

finished_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_sha256="$(shasum -a 256 "$log_path" | awk '{print $1}')"

cat >"$partial_dir/capture.json" <<EOF
{
  "schema_version": 1,
  "run_id": "$run_id",
  "case_id": "$case_id",
  "node_alias": "$node_alias",
  "capture_started_utc": "$started_at",
  "capture_finished_utc": "$finished_at",
  "duration_seconds": $duration,
  "capture_method": "xcrun devicectl device process launch --console --terminate-existing",
  "bundle_id": "$bundle_id",
  "log_file": "$log_name",
  "log_sha256": "$log_sha256",
  "privacy": "MACs, UUIDs, names, coordinates, peer identifiers and common secret fields redacted before writing",
  "result": "PENDING",
  "result_note": "This capture does not prove physical delivery, encryption, background execution or once-only behavior."
}
EOF

mv "$partial_dir" "$capture_dir"
trap - EXIT HUP INT TERM

printf 'Captura saneada: %s/%s\n' "$capture_dir" "$log_name"
printf 'Metadatos e integridad: %s/capture.json\n' "$capture_dir"
printf 'Resultado: PENDING hasta revisión manual de todos los criterios.\n'
