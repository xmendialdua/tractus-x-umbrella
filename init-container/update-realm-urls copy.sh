#!/bin/bash
# Script para actualizar las URLs en los archivos realm.json antes del despliegue
# Uso: ./update-realm-urls.sh <nuevo_dominio>
# Ejemplo: ./update-realm-urls.sh 51.68.114.44.nip.io

set -e

if [ -z "$1" ]; then
    echo "Error: Debe proporcionar el nuevo dominio"
    echo "Uso: $0 <nuevo_dominio>"
    echo "Ejemplo: $0 51.68.114.44.nip.io"
    exit 1
fi

NEW_DOMAIN="$1"
OLD_DOMAIN="tx.test"

echo "=========================================="
echo "Actualizando URLs de realm.json"
echo "=========================================="
echo "Dominio antiguo: ${OLD_DOMAIN}"
echo "Dominio nuevo: ${NEW_DOMAIN}"
echo ""

# Directorio base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAM_DIR="${SCRIPT_DIR}/iam"

# Función para reemplazar URLs en un archivo
update_realm_file() {
    local file="$1"
    local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  Archivo no encontrado: $file"
        return 1
    fi
    
    echo "📝 Procesando: $(basename $file)"
    
    # Crear backup
    cp "$file" "$backup"
    echo "   ✅ Backup creado: $(basename $backup)"
    
    # Reemplazar URLs (usamos sed con delimitador | para evitar conflictos con /)
    sed -i "s|${OLD_DOMAIN}|${NEW_DOMAIN}|g" "$file"
    
    # Contar reemplazos
    local changes=$(diff "$backup" "$file" | grep -c "^[<>]" || true)
    echo "   ✅ Cambios realizados: $((changes / 2)) líneas modificadas"
    
    return 0
}

# Procesar centralidp
echo ""
echo "🔹 CentralIDP"
echo "----------------------------------------"
update_realm_file "${IAM_DIR}/centralidp/CX-Central-realm.json"

if [ -f "${IAM_DIR}/centralidp/CX-Central-realm_MAssembly.json" ]; then
    update_realm_file "${IAM_DIR}/centralidp/CX-Central-realm_MAssembly.json"
fi

# Procesar sharedidp
echo ""
echo "🔹 SharedIDP"
echo "----------------------------------------"
if [ -f "${IAM_DIR}/sharedidp/CX-Operator-realm.json" ]; then
    update_realm_file "${IAM_DIR}/sharedidp/CX-Operator-realm.json"
else
    echo "⚠️  No se encontró archivo de realm para sharedidp"
fi

echo ""
echo "=========================================="
echo "✅ Actualización completada"
echo "=========================================="
echo ""
echo "Próximos pasos:"
echo "1. Revisar los cambios: git diff init-container/iam/"
echo "2. Reconstruir imagen init-container:"
echo "   cd init-container"
echo "   docker build -t <registry>/init-container:latest ."
echo "   docker push <registry>/init-container:latest"
echo "3. Hacer helm upgrade con la nueva imagen"
echo ""
echo "Para restaurar desde backup:"
echo "   find ${IAM_DIR} -name '*.backup-*' -exec bash -c 'mv \"\$1\" \"\${1%.backup-*}\"' _ {} \;"
