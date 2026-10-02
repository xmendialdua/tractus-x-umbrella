
###############################################################################
# Este script muestra todos los pasos realizado en el proceso de registro para la compañia 
###############################################################################

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"
PORTAL_SCHEMA="portal"


kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -d "$PGDATABASE" -c "
SELECT
  pst.label AS step_type,
  pss.label AS step_status,
  ps.message,
  ps.date_created
FROM portal.company_invitations ci
JOIN portal.process_steps ps ON ps.process_id = ci.process_id
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE lower(ci.email) = lower('dataspace@partnera.com')
ORDER BY ps.date_created;"