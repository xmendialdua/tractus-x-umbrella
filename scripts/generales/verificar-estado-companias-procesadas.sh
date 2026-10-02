
export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"
PORTAL_SCHEMA="portal"


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