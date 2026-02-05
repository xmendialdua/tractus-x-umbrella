#!/bin/bash

###############################################################################
# Unblock Application After Manual BPN Assignment
###############################################################################
# Este script desbloquea una aplicación después de asignar manualmente el BPN
# cuando el proceso automático ha fallado en CREATE_BUSINESS_PARTNER_NUMBER_PUSH.
#
# Pasos que realiza:
# 1. Marca RETRIGGER_ASSIGN_BPN_TO_USERS como DONE
# 2. Crea un Job manual del processes-worker para forzar procesamiento
# 3. Espera a que el Job complete
# 4. Verifica el estado final de la aplicación
#
# Prerequisitos:
# - El BPN debe estar ya asignado manualmente en portal.companies
#
# Uso: ./unblock-application-after-bpn.sh <realm_name>
#
# Ejemplos:
#   ./unblock-application-after-bpn.sh idp1  # MondragonAssembly
#   ./unblock-application-after-bpn.sh idp2  # Ikerlan
###############################################################################

set -e

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"

# Validar argumentos
if [ $# -ne 1 ]; then
    echo "❌ ERROR: Falta el realm name"
    echo ""
    echo "Uso: $0 <realm_name>"
    echo ""
    echo "Ejemplos:"
    echo "  $0 idp1  # MondragonAssembly"
    echo "  $0 idp2  # Ikerlan"
    echo ""
    exit 1
fi

REALM_NAME="$1"

echo "=========================================="
echo "Unblock Application After BPN Assignment"
echo "=========================================="
echo "Realm: $REALM_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Buscar el process_id asociado al realm
echo "🔍 Buscando process_id para realm $REALM_NAME..."
echo ""

PROCESS_LOOKUP=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
SELECT DISTINCT p.id
FROM portal.processes p
WHERE p.process_type_id = 1  -- APPLICATION_CHECKLIST
AND EXISTS (
    SELECT 1 FROM portal.process_steps ps
    WHERE ps.process_id = p.id
    AND ps.message LIKE '%$REALM_NAME%'
)
LIMIT 1;
")

# Si no lo encuentra por mensaje, buscar por order de creación (asumiendo idp1=primero, idp2=segundo, etc)
if [ -z "$PROCESS_LOOKUP" ] || [ "$PROCESS_LOOKUP" = " " ]; then
    echo "⚠️  No encontrado por mensaje, buscando por orden..."
    
    # Extraer el número del realm (idp1 -> 1, idp2 -> 2)
    REALM_NUM=$(echo "$REALM_NAME" | grep -o '[0-9]*$')
    
    if [ -z "$REALM_NUM" ]; then
        echo "❌ ERROR: No se pudo extraer el número del realm: $REALM_NAME"
        exit 1
    fi
    
    PROCESS_LOOKUP=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
    SELECT p.id
    FROM portal.processes p
    WHERE p.process_type_id = 1
    ORDER BY p.id
    LIMIT 1 OFFSET $((REALM_NUM - 1));
    ")
fi

PROCESS_ID=$(echo "$PROCESS_LOOKUP" | tr -d ' ')

if [ -z "$PROCESS_ID" ]; then
    echo "❌ ERROR: No se encontró el process_id para el realm $REALM_NAME"
    echo ""
    echo "Procesos disponibles:"
    kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
    SELECT 
        p.id as process_id,
        COUNT(ps.id) as num_steps
    FROM portal.processes p
    LEFT JOIN portal.process_steps ps ON p.id = ps.process_id
    WHERE p.process_type_id = 1
    GROUP BY p.id
    ORDER BY p.id;
    "
    exit 1
fi

echo "✅ Process ID encontrado: $PROCESS_ID"
echo ""

# Verificar que el pod existe
if ! kubectl get pod -n "$NAMESPACE" "$POD" &>/dev/null; then
    echo "❌ ERROR: Pod $POD no encontrado en namespace $NAMESPACE"
    exit 1
fi

# Paso 1: Verificar el estado actual
echo "📋 Verificando estado actual del proceso..."
echo ""

CURRENT_STATE=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
SELECT 
    pst.label as step_type,
    pss.label as step_status,
    ps.id as step_id
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON ps.process_step_type_id = pst.id
JOIN portal.process_step_statuses pss ON ps.process_step_status_id = pss.id
WHERE ps.process_id = '$PROCESS_ID'
  AND pst.label = 'RETRIGGER_ASSIGN_BPN_TO_USERS'
ORDER BY ps.date_created DESC
LIMIT 1;
")

if [ -z "$CURRENT_STATE" ]; then
    echo "❌ ERROR: No se encontró el step RETRIGGER_ASSIGN_BPN_TO_USERS para este process_id"
    echo "   Verifica que el process_id sea correcto"
    exit 1
fi

echo "Estado encontrado:"
echo "$CURRENT_STATE"
echo ""

# Extraer el step_id
STEP_ID=$(echo "$CURRENT_STATE" | awk '{print $NF}')

if [ -z "$STEP_ID" ]; then
    echo "❌ ERROR: No se pudo extraer el step_id"
    exit 1
fi

echo "Step ID a actualizar: $STEP_ID"
echo ""

# Verificar que el BPN está asignado
echo "🔍 Verificando que el BPN está asignado..."
echo ""

# Primero obtener el company_id desde el process
COMPANY_INFO=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
SELECT 
    c.name,
    c.business_partner_number
FROM portal.companies c
WHERE c.id IN (
    SELECT DISTINCT ca.company_id
    FROM portal.company_applications ca
    WHERE ca.id IN (
        SELECT DISTINCT ps.process_id 
        FROM portal.process_steps ps
        WHERE ps.process_id = '$PROCESS_ID'
        LIMIT 1
    )
    OR EXISTS (
        SELECT 1 
        FROM portal.process_steps ps2
        WHERE ps2.id IN (
            SELECT id FROM portal.process_steps 
            WHERE process_id = '$PROCESS_ID' 
            LIMIT 1
        )
    )
)
LIMIT 1;
")

# Si no funciona, buscar por el application_id relacionado con el proceso
if [ -z "$COMPANY_INFO" ] || echo "$COMPANY_INFO" | grep -q "^[[:space:]]*$"; then
    echo "   Buscando por método alternativo..."
    
    COMPANY_INFO=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
    SELECT c.name, c.business_partner_number
    FROM portal.companies c
    JOIN portal.company_applications ca ON c.id = ca.company_id
    WHERE c.name LIKE '%' || (
        CASE 
            WHEN '$REALM_NAME' = 'idp1' THEN 'Mondragon%'
            WHEN '$REALM_NAME' = 'idp2' THEN 'Ikerlan%'
            WHEN '$REALM_NAME' = 'idp3' THEN '%'
            ELSE '%'
        END
    )
    ORDER BY ca.date_created DESC
    LIMIT 1;
    ")
fi

echo "$COMPANY_INFO"

echo "$COMPANY_INFO"

if echo "$COMPANY_INFO" | grep -q "^[[:space:]]*$"; then
    echo ""
    echo "❌ ERROR: No se encontró la compañía asociada al proceso"
    exit 1
fi

BPN=$(echo "$COMPANY_INFO" | awk '{print $NF}')
COMPANY_NAME=$(echo "$COMPANY_INFO" | awk '{$NF=""; print $0}' | sed 's/[[:space:]]*$//')

if [ "$BPN" = "" ] || [ "$BPN" = "bpn" ]; then
    echo ""
    echo "❌ ERROR: El BPN no está asignado"
    echo "   Asígnalo manualmente antes de continuar"
    exit 1
fi

echo ""
echo "✅ Compañía: $COMPANY_NAME"
echo "✅ BPN asignado: $BPN"
echo ""

# Paso 2: Marcar RETRIGGER_ASSIGN_BPN_TO_USERS como DONE
echo "📝 Marcando RETRIGGER_ASSIGN_BPN_TO_USERS como DONE..."
echo ""

UPDATE_RESULT=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
UPDATE portal.process_steps 
SET 
    process_step_status_id = 3,  -- DONE
    date_last_changed = NOW()
WHERE id = '$STEP_ID'
  AND process_step_status_id = 1;  -- Solo si está en TODO
")

if echo "$UPDATE_RESULT" | grep -q "UPDATE 1"; then
    echo "✅ Step actualizado correctamente"
else
    echo "⚠️  Step no actualizado (posiblemente ya estaba en DONE o SKIPPED)"
fi

echo ""

# Paso 2b: Insertar FINISH_APPLICATION_ACTIVATION si no existe
echo "📝 Insertando FINISH_APPLICATION_ACTIVATION si no existe..."
echo ""

CHECK_FINISH=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -t -c "
SELECT COUNT(*) 
FROM portal.process_steps 
WHERE process_id = '$PROCESS_ID' 
  AND process_step_type_id = 38;  -- FINISH_APPLICATION_ACTIVATION
")

if [ "$(echo $CHECK_FINISH | tr -d ' ')" = "0" ]; then
    echo "   Insertando step FINISH_APPLICATION_ACTIVATION..."
    
    INSERT_RESULT=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
    INSERT INTO portal.process_steps (id, process_step_type_id, process_step_status_id, date_created, process_id)
    VALUES (gen_random_uuid(), 38, 1, NOW(), '$PROCESS_ID');
    ")
    
    if echo "$INSERT_RESULT" | grep -q "INSERT"; then
        echo "   ✅ Step FINISH_APPLICATION_ACTIVATION insertado"
    else
        echo "   ❌ Error al insertar step"
    fi
else
    echo "   ✅ Step FINISH_APPLICATION_ACTIVATION ya existe"
fi

echo ""

# Paso 3: Crear Job manual del processes-worker
echo "🚀 Creando Job manual del processes-worker..."
echo ""

JOB_NAME="portal-processes-worker-manual-$(date +%s)"

kubectl create job "$JOB_NAME" \
  --from=cronjob/portal-processes-worker \
  -n "$NAMESPACE"

echo "✅ Job creado: $JOB_NAME"
echo ""

# Paso 4: Esperar a que el Job complete
echo "⏳ Esperando a que el Job complete (timeout: 120s)..."
echo ""

TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    JOB_STATUS=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    
    if [ "$JOB_STATUS" = "True" ]; then
        echo "✅ Job completado exitosamente"
        break
    fi
    
    JOB_FAILED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    
    if [ "$JOB_FAILED" = "True" ]; then
        echo "❌ Job falló"
        echo ""
        echo "Ver logs con:"
        echo "  kubectl logs -n $NAMESPACE job/$JOB_NAME"
        exit 1
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done

echo ""
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "⚠️  Timeout esperando el Job"
    echo ""
    echo "Ver estado con:"
    echo "  kubectl get job $JOB_NAME -n $NAMESPACE"
    echo ""
    echo "Ver logs con:"
    echo "  kubectl logs -n $NAMESPACE job/$JOB_NAME"
    echo ""
fi

# Paso 5: Verificar el estado final
echo "🔍 Verificando estado final del proceso..."
echo ""

FINAL_STATE=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
SELECT 
    pst.label as step_type,
    pss.label as step_status,
    ps.date_created
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON ps.process_step_type_id = pst.id
JOIN portal.process_step_statuses pss ON ps.process_step_status_id = pss.id
WHERE ps.process_id = '$PROCESS_ID'
ORDER BY ps.date_created DESC
LIMIT 5;
")

echo "$FINAL_STATE"
echo ""

# Verificar estado de la aplicación
echo "📊 Estado de la aplicación:"
echo ""

APP_STATE=$(kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
SELECT 
    c.name as company_name,
    c.business_partner_number as bpn,
    cs.label as company_status,
    ca.application_status_id
FROM portal.companies c
JOIN portal.company_statuses cs ON c.company_status_id = cs.id
JOIN portal.company_applications ca ON c.id = ca.company_id
WHERE c.name = '$COMPANY_NAME'
LIMIT 1;
")

echo "$APP_STATE"
echo ""

# Verificar si hay emails pendientes
echo "📧 Verificando emails enviados..."
echo ""

EMAIL_COUNT=$(curl -s http://smtp4dev.51.178.94.25.nip.io/api/Messages 2>/dev/null | grep -o '"subject"' | wc -l || echo "0")

echo "Emails en smtp4dev: $EMAIL_COUNT"
echo ""
echo "Ver emails en: http://smtp4dev.51.178.94.25.nip.io"
echo ""

echo "=========================================="
echo "Proceso completado"
echo "=========================================="
echo ""
echo "Si la aplicación no se activó completamente:"
echo "1. Revisa los logs del job:"
echo "   kubectl logs -n $NAMESPACE job/$JOB_NAME"
echo ""
echo "2. Verifica el estado de los process_steps:"
echo "   kubectl exec -n $NAMESPACE $POD -- env PGPASSWORD=\"$PGPASSWORD\" psql -U $PGUSER -d $PGDATABASE -c \\"
echo "     \"SELECT pst.label, pss.label, ps.date_created FROM portal.process_steps ps"
echo "      JOIN portal.process_step_types pst ON ps.process_step_type_id = pst.id"
echo "      JOIN portal.process_step_statuses pss ON ps.process_step_status_id = pss.id"
echo "      WHERE ps.process_id = '$PROCESS_ID' ORDER BY ps.date_created;\""
echo ""
echo "3. Espera al siguiente CronJob (cada 5 minutos):"
echo "   watch kubectl get jobs -n $NAMESPACE | grep processes-worker"
echo ""
