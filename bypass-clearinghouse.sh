#!/bin/bash
###############################################################################
# Bypass Clearinghouse for Portal Onboarding
###############################################################################
# Este script bypasea el paso del Clearinghouse en el proceso de onboarding
# del Portal, permitiendo que las aplicaciones en estado SUBMITTED (7) sean
# procesadas automáticamente.
#
# El script es GENÉRICO y procesa TODAS las compañías que cumplan:
# - application_status_id = 7 (SUBMITTED)
# - application_checklist_entry_type_id = 6 (Clearinghouse check)
# - application_checklist_entry_status_id = 4 (TO_DO) o 1 (TODO)
#
# Uso: ./bypass-clearinghouse.sh
#
# Referencias:
# - Portal Assets: https://github.com/eclipse-tractusx/portal-assets
# - Clearinghouse Interface: https://github.com/eclipse-tractusx/portal-assets/blob/v2.1.0/docs/developer/Technical%20Documentation/Interface%20Contracts/Clearinghouse.md
###############################################################################

set -e

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"

echo "=========================================="
echo "Bypass Clearinghouse - Portal Onboarding"
echo "=========================================="
echo ""
echo "Namespace: $NAMESPACE"
echo "Pod: $POD"
echo ""

# Verificar que el pod existe
if ! kubectl get pod -n "$NAMESPACE" "$POD" &>/dev/null; then
    echo "❌ ERROR: Pod $POD no encontrado en namespace $NAMESPACE"
    exit 1
fi

echo "✓ Pod encontrado"
echo ""

# Ejecutar el script SQL
echo "Ejecutando bypass del Clearinghouse..."
echo ""

RESULT=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
WITH applications AS (
    SELECT distinct ca.id as Id, ca.checklist_process_id as ChecklistId
    FROM portal.company_applications as ca
             JOIN portal.application_checklist as ac ON ca.id = ac.application_id
    WHERE 
      ca.application_status_id = 7 
    AND ac.application_checklist_entry_type_id = 6
    AND (ac.application_checklist_entry_status_id = 4 OR ac.application_checklist_entry_status_id = 1)
),
updated AS (
 UPDATE portal.application_checklist
     SET application_checklist_entry_status_id = 3
     WHERE application_id IN (SELECT Id FROM applications)
     RETURNING *
)
INSERT INTO portal.process_steps (id, process_step_type_id, process_step_status_id, date_created, date_last_changed, process_id, message)
SELECT gen_random_uuid(), 12, 1, now(), NULL, a.ChecklistId, NULL
FROM applications a;
")

echo "$RESULT"
echo ""

# Verificar resultado
if [[ "$RESULT" == *"INSERT"* ]]; then
    echo "✅ Bypass ejecutado correctamente"
    echo ""
    echo "Esperando 5 segundos para que el proceso automático complete el onboarding..."
    sleep 5
    
    echo ""
    echo "Verificando estado de las compañías procesadas:"
    echo ""
    
    kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
    SELECT 
        c.name as company_name,
        c.business_partner_number as bpn,
        cs.label as status,
        ca.application_status_id
    FROM portal.companies c
    JOIN portal.company_statuses cs ON c.company_status_id = cs.id
    JOIN portal.company_applications ca ON c.id = ca.company_id
    WHERE ca.application_status_id >= 7
    ORDER BY ca.date_last_changed DESC
    LIMIT 10;
    "
else
    echo "⚠️  No se encontraron aplicaciones pendientes de bypass o hubo un error"
fi

echo ""
echo "=========================================="
echo "Proceso completado"
echo "=========================================="
