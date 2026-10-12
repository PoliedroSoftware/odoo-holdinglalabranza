#!/usr/bin/env bash
set -Eeuo pipefail

archive_name="${1:-}"
install_modules="${2:-}"
update_modules="${3:-}"
[[ "$archive_name" =~ ^holdinglalabranza-[0-9a-f]{40}\.tar\.gz$ ]] || { echo "Nombre de paquete inválido." >&2; exit 2; }

validate_module_list() {
  local value="$1"
  [[ -z "$value" ]] && return 0
  [[ "$value" =~ ^holdinglalabranza_[A-Za-z0-9_]+(,holdinglalabranza_[A-Za-z0-9_]+)*$ ]]
}
validate_module_list "$install_modules" || { echo "Lista install_modules inválida." >&2; exit 2; }
validate_module_list "$update_modules" || { echo "Lista update_modules inválida." >&2; exit 2; }

base=/opt/poliedro-odoo
custom_addons="$base/src/custom-addons"
incoming="$base/incoming/$archive_name"
[[ -f "$incoming" && -d "$custom_addons" ]] || { echo "No se encontró el paquete o la ruta de addons." >&2; exit 2; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$base/backups/holdinglalabranza/$stamp"
stage="$base/sync/holdinglalabranza-$stamp"
mkdir -p "$backup/previous" "$backup/failed-new" "$stage/addons"

module_names=()
deployment_started=0
rollback() {
  local status=$?
  trap - ERR
  if (( deployment_started )); then
    echo "Despliegue fallido; restaurando los addons previos. Backup de BD: $backup/odoo_dev.dump" >&2
    docker compose -f "$base/compose.yml" -p poliedro-odoo stop odoo || true
    for module in "${module_names[@]}"; do
      target="$custom_addons/$module"
      if [[ -e "$target" ]]; then
        mv "$target" "$backup/failed-new/$module" || true
      fi
      if [[ -e "$backup/previous/$module" ]]; then
        mv "$backup/previous/$module" "$target" || true
      fi
    done
    docker compose -f "$base/compose.yml" -p poliedro-odoo up -d odoo || true
  fi
  exit "$status"
}
trap rollback ERR

tar -xzf "$incoming" --no-same-owner --no-same-permissions -C "$stage/addons"
[[ -z "$(find "$stage/addons" -type l -print -quit)" ]] || { echo "No se aceptan enlaces simbólicos en addons." >&2; exit 2; }
for module_dir in "$stage/addons"/*; do
  [[ -d "$module_dir" ]] || { echo "El paquete debe contener solo carpetas de módulos." >&2; exit 2; }
  module="$(basename "$module_dir")"
  [[ "$module" =~ ^holdinglalabranza_[A-Za-z0-9_]+$ ]] || { echo "Nombre de módulo inválido: $module" >&2; exit 2; }
  [[ -f "$module_dir/__manifest__.py" ]] || { echo "Falta __manifest__.py en $module." >&2; exit 2; }
  module_names+=("$module")
done
((${#module_names[@]} > 0)) || { echo "El paquete no contiene addons." >&2; exit 2; }
for value in "$install_modules" "$update_modules"; do
  [[ -z "$value" ]] && continue
  IFS=',' read -ra requested <<< "$value"
  for module in "${requested[@]}"; do
    [[ " ${module_names[*]} " == *" $module "* ]] || { echo "Módulo solicitado fuera del paquete: $module" >&2; exit 2; }
  done
done

docker compose -f "$base/compose.yml" -p poliedro-odoo exec -T db \
  pg_dump -U odoo -Fc --no-owner --no-acl odoo_dev > "$backup/odoo_dev.dump"
docker compose -f "$base/compose.yml" -p poliedro-odoo stop odoo
deployment_started=1
for module in "${module_names[@]}"; do
  target="$custom_addons/$module"
  if [[ -e "$target" ]]; then
    mv "$target" "$backup/previous/$module"
  fi
  mv "$stage/addons/$module" "$target"
done

odoo_args=(-d odoo_dev)
[[ -z "$install_modules" ]] || odoo_args+=(-i "$install_modules")
[[ -z "$update_modules" ]] || odoo_args+=(-u "$update_modules")
if ((${#odoo_args[@]} > 2)); then
  docker compose -f "$base/compose.yml" -p poliedro-odoo run --rm odoo "${odoo_args[@]}" --stop-after-init
fi

docker compose -f "$base/compose.yml" -p poliedro-odoo up -d odoo
for attempt in $(seq 1 30); do
  if docker compose -f "$base/compose.yml" -p poliedro-odoo exec -T odoo \
    python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8069/web/login', timeout=3)" >/dev/null 2>&1; then
    deployment_started=0
    trap - ERR
    mv "$incoming" "$backup/source-upload.tar.gz"
    echo "Despliegue verificado. Backup de BD: $backup/odoo_dev.dump"
    exit 0
  fi
  sleep 2
done
docker compose -f "$base/compose.yml" -p poliedro-odoo logs --tail=100 odoo >&2
echo "Odoo no pasó la verificación de salud." >&2
exit 1
