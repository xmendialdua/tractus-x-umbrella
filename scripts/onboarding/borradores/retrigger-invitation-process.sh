#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: retrigger-invitation-process.sh
# Fecha: 2026-06-30
#
# Problema:
# - Una invitacion de onboarding puede quedarse bloqueada con un paso FAILED,
#   tipicamente INVITATION_UPDATE_CENTRAL_IDP_URLS, y el paso RETRIGGER_* en
#   estado TODO sin que el worker lo reprocesa automaticamente.
# - En ese estado no se crea mailing_informations y no llega correo a smtp4dev.
#
# Solucion:
# - Reabrir el paso FAILED como TODO para que el worker lo vuelva a ejecutar.
# - Marcar el paso RETRIGGER_* correspondiente como SKIPPED para evitar
#   ambiguedad de reintento.
# - Lanzar un job manual de portal-processes-worker.
# - Mostrar trazas recientes de process_steps y estado de mailing.
#
# Uso:
#   ./scripts/onboarding/retrigger-invitation-process.sh dataspace@partnera.com
#   ./scripts/onboarding/retrigger-invitation-process.sh dataspace@partnera.com --force-skip-405
#
# Requisitos:
# - kubeconfig disponible (usa KUBECONFIG actual o kubeconfig.yaml del repo).
# - Acceso al namespace portal.
#
# Que hace:
# - Muestra estado de invitación y application status.
# - Lista los process_steps recientes.
# - Comprueba si existe mailing_informations y su estado (PENDING o SENT).
# -----------------------------------------------------------------------------

set -euo pipefail

EMAIL="${1:-}"
FORCE_SKIP_405="${2:-}"
if [[ -z "$EMAIL" ]]; then
	echo "Uso: $0 <email-invitado> [--force-skip-405]"
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "${KUBECONFIG:-}" && -f "$REPO_ROOT/kubeconfig.yaml" ]]; then
	export KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"
fi

NAMESPACE="portal"
PGPOD="portal-portal-backend-postgresql-0"
DB_USER="portal"
DB_NAME="postgres"

echo "[1/6] Leyendo password de PostgreSQL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NAMESPACE" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/6] Obteniendo process_id para $EMAIL"
PROCESS_ID="$(kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
	psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
SELECT ci.process_id
FROM portal.company_invitations ci
WHERE lower(ci.email) = lower('$EMAIL')
LIMIT 1;
")"

if [[ -z "$PROCESS_ID" ]]; then
	echo "No se encontro process_id para el email: $EMAIL"
	exit 1
fi

echo "process_id encontrado: $PROCESS_ID"

echo "[3/6] Reabriendo pasos de invitacion (transaccion)"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
	psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
BEGIN;

UPDATE portal.process_steps
SET process_step_status_id = 1,
		date_last_changed = NOW(),
		message = NULL
WHERE process_id = '$PROCESS_ID'
	AND process_step_type_id = 405
	AND process_step_status_id = 4;

UPDATE portal.process_steps
SET process_step_status_id = 3,
		date_last_changed = NOW()
WHERE process_id = '$PROCESS_ID'
	AND process_step_type_id = 415
	AND process_step_status_id = 1;

COMMIT;
"

echo "[4/6] Lanzando portal-processes-worker manual"
JOB_NAME="portal-processes-worker-manual-$(date +%s)"
kubectl create job --from=cronjob/portal-processes-worker "$JOB_NAME" -n "$NAMESPACE"

echo "[5/6] Esperando fin del job manual ($JOB_NAME)"
kubectl wait --for=condition=complete --timeout=180s "job/$JOB_NAME" -n "$NAMESPACE" || true

# Si el step 405 sigue fallando y se pidio modo forzado, salta ese paso para
# permitir que el flujo continue con el step 406.
LATEST_405_STATUS="$(kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
		psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
SELECT pss.label
FROM portal.process_steps ps
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE ps.process_id = '$PROCESS_ID'
	AND ps.process_step_type_id = 405
ORDER BY ps.date_created DESC
LIMIT 1;
")"

if [[ "$LATEST_405_STATUS" == "FAILED" && "$FORCE_SKIP_405" == "--force-skip-405" ]]; then
		echo "[5b/6] Step 405 sigue en FAILED. Aplicando fallback forzado (--force-skip-405)"

		kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
				psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
BEGIN;

UPDATE portal.process_steps
SET process_step_status_id = 3,
		date_last_changed = NOW(),
		message = COALESCE(message, '') || ' [force-skip-405:' || NOW() || ']'
WHERE id = (
		SELECT id
		FROM portal.process_steps
		WHERE process_id = '$PROCESS_ID'
			AND process_step_type_id = 405
		ORDER BY date_created DESC
		LIMIT 1
);

UPDATE portal.process_steps
SET process_step_status_id = 3,
		date_last_changed = NOW()
WHERE process_id = '$PROCESS_ID'
	AND process_step_type_id = 415
	AND process_step_status_id = 1;

INSERT INTO portal.process_steps (id, process_step_type_id, process_step_status_id, date_created, process_id)
SELECT gen_random_uuid(), 406, 1, NOW(), '$PROCESS_ID'
WHERE NOT EXISTS (
		SELECT 1
		FROM portal.process_steps
		WHERE process_id = '$PROCESS_ID'
			AND process_step_type_id = 406
			AND process_step_status_id IN (1,2)
);

COMMIT;
"

		JOB_NAME_FALLBACK="portal-processes-worker-manual-fallback-$(date +%s)"
		echo "[5c/6] Lanzando job manual tras fallback: $JOB_NAME_FALLBACK"
		kubectl create job --from=cronjob/portal-processes-worker "$JOB_NAME_FALLBACK" -n "$NAMESPACE"
		kubectl wait --for=condition=complete --timeout=180s "job/$JOB_NAME_FALLBACK" -n "$NAMESPACE" || true
elif [[ "$LATEST_405_STATUS" == "FAILED" ]]; then
		echo "[5b/6] Aviso: step 405 sigue en FAILED."
		echo "      Puedes reintentar en modo forzado: $0 $EMAIL --force-skip-405"
fi

echo "[6/6] Verificacion: process_steps y mailing"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
	psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT ps.date_created, pst.label AS step_type, pss.label AS step_status, ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE ps.process_id = '$PROCESS_ID'
ORDER BY ps.date_created DESC
LIMIT 20;
"

kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
	psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT ci.email, ci.process_id, mi.id AS mailing_id, ms.label AS mailing_status
FROM portal.company_invitations ci
LEFT JOIN portal.mailing_informations mi ON mi.process_id = ci.process_id
LEFT JOIN portal.mailing_statuses ms ON ms.id = mi.mailing_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "Script finalizado"
