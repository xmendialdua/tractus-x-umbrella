# Procedimiento Optimizado para Onboarding de Business Partners

**Versión:** 1.0  
**Fecha:** 27 de Enero de 2026  
**Basado en:** Onboarding exitoso de Ikerlan  
**Tiempo estimado:** 15-20 minutos

---

## ✅ Checklist Rápido

- [ ] PASO 1: Preparar datos del Business Partner
- [ ] PASO 2: Crear invitación en Portal UI
- [ ] PASO 3: Identificar identity provider alias (idp1, idp2, idp3...)
- [ ] PASO 4: Configurar realm en Keycloak (sslRequired: none)
- [ ] PASO 5: Crear cliente OAuth2 (Cl2-CX-Portal)
- [ ] PASO 6: Obtener usuario y configurar contraseña
- [ ] PASO 7: Actualizar base de datos (user_entity_id + BPN)
- [ ] PASO 8: Verificar REQUIRE_HTTPS en false
- [ ] PASO 9: Reiniciar servicios del Portal
- [ ] PASO 10: Probar login

---

## PASO 1: Preparar Datos del Business Partner

Crear archivo `onboarding/<EMPRESA>.txt` con:

```
Nombre legal: [Nombre completo]
CIF/NIF: [Número]
Dirección: [Calle y número]
Código postal: [CP]
Ciudad: [Ciudad]
Email contacto: [email@empresa.com]
BPN asignado: BPNL000000002XXX
```

**Para Assembly (siguiente):**
- BPN: `BPNL000000002ASM`
- Realm esperado: `idp2`

**Para Fagor:**
- BPN: `BPNL000000003FGR`
- Realm esperado: `idp3`

---

## PASO 2: Crear Invitación en Portal UI

1. Login en Portal: `http://portal.51.68.114.44.nip.io`
2. Ir a **"Invite new partner"**
3. Introducir:
   - Email: `contacto@empresa.com`
   - Nombre: `Nombre Legal Empresa`
4. Click **"Invite Business Partner"**

**⚠️ Importante:** El proceso NO se completará automáticamente (falta SMTP). Esto es normal.

---

## PASO 3: Identificar Identity Provider Alias

```bash
# Obtener password de PostgreSQL
PGPASSWORD=$(kubectl get secret -n portal portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)

# Buscar la empresa recién creada
kubectl exec -n portal portal-portal-backend-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD \
  psql -U portal -d postgres -c \
  "SELECT c.id as company_id, c.name, iip.iam_idp_alias, iip.metadata_url 
   FROM portal.companies c 
   JOIN portal.identity_providers ip ON ip.owner_id = c.id 
   JOIN portal.iam_identity_providers iip ON iip.identity_provider_id = ip.id 
   WHERE c.name = 'NOMBRE_EMPRESA' 
   ORDER BY c.date_created DESC LIMIT 1;"
```

**Anotar:**
- `company_id`: [UUID]
- `iam_idp_alias`: [idp1, idp2, idp3...]

**Ejemplo resultado:**
```
company_id              | name     | iam_idp_alias | metadata_url
[UUID]                  | Assembly | idp2          | http://sharedidp.../idp2
```

---

## PASO 4: Configurar Realm en Keycloak

```bash
# Obtener token de administrador
ADMIN_PASS=$(kubectl get secret -n portal portal-sharedidp -o jsonpath='{.data.admin-password}' | base64 -d)

ADMIN_TOKEN=$(curl -s -X POST \
  "http://sharedidp.51.68.114.44.nip.io/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$ADMIN_PASS" | jq -r '.access_token')

# Configurar realm (usar el iam_idp_alias del PASO 3)
REALM_ALIAS="idp2"  # ← CAMBIAR según resultado PASO 3
DISPLAY_NAME="Assembly"  # ← CAMBIAR según empresa

curl -s -X PUT \
  "http://sharedidp.51.68.114.44.nip.io/auth/admin/realms/$REALM_ALIAS" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"realm\": \"$REALM_ALIAS\",
    \"displayName\": \"$DISPLAY_NAME\",
    \"enabled\": true,
    \"sslRequired\": \"none\"
  }"

echo "✅ Realm $REALM_ALIAS configurado"
```

---

## PASO 5: Crear Cliente OAuth2

```bash
curl -s -X POST \
  "http://sharedidp.51.68.114.44.nip.io/auth/admin/realms/$REALM_ALIAS/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "Cl2-CX-Portal",
    "name": "Catena-X Portal Client",
    "enabled": true,
    "publicClient": true,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false,
    "protocol": "openid-connect",
    "redirectUris": [
      "http://portal.51.68.114.44.nip.io/*",
      "http://portal.51.68.114.44.nip.io/home",
      "http://portal.51.68.114.44.nip.io/auth/*"
    ],
    "webOrigins": [
      "http://portal.51.68.114.44.nip.io"
    ],
    "attributes": {
      "post.logout.redirect.uris": "http://portal.51.68.114.44.nip.io/*"
    }
  }'

echo "✅ Cliente OAuth2 creado"
```

---

## PASO 6: Obtener Usuario y Configurar Contraseña

```bash
# Buscar usuario (usar email del PASO 2)
USER_EMAIL="contacto@empresa.com"  # ← CAMBIAR

USER_INFO=$(curl -s -X GET \
  "http://sharedidp.51.68.114.44.nip.io/auth/admin/realms/$REALM_ALIAS/users?email=$USER_EMAIL" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

USER_ID=$(echo $USER_INFO | jq -r '.[0].id')
echo "Usuario ID: $USER_ID"

# Establecer contraseña
curl -s -X PUT \
  "http://sharedidp.51.68.114.44.nip.io/auth/admin/realms/$REALM_ALIAS/users/$USER_ID/reset-password" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "password",
    "value": "Welcome2Catena-X!",
    "temporary": false
  }'

echo "✅ Contraseña configurada"
```

---

## PASO 7: Actualizar Base de Datos

```bash
# Usar company_id del PASO 3
COMPANY_ID="[UUID_DEL_PASO_3]"  # ← CAMBIAR
BPN="BPNL000000002ASM"  # ← CAMBIAR según empresa

# Actualizar user_entity_id
kubectl exec -n portal portal-portal-backend-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD \
  psql -U portal -d postgres -c \
  "UPDATE portal.identities 
   SET user_entity_id = '$USER_ID' 
   WHERE company_id = '$COMPANY_ID';"

# Actualizar BPN
kubectl exec -n portal portal-portal-backend-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD \
  psql -U portal -d postgres -c \
  "UPDATE portal.companies 
   SET business_partner_number = '$BPN' 
   WHERE id = '$COMPANY_ID';"

echo "✅ Base de datos actualizada"
```

---

## PASO 8: Verificar REQUIRE_HTTPS

```bash
# Verificar valor actual
CURRENT_VALUE=$(kubectl get deployment -n portal portal-portal \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REQUIRE_HTTPS_URL_PATTERN")].value}')

echo "REQUIRE_HTTPS_URL_PATTERN: $CURRENT_VALUE"

# Si no es 'false', cambiarlo
if [ "$CURRENT_VALUE" != "false" ]; then
  kubectl set env deployment/portal-portal -n portal REQUIRE_HTTPS_URL_PATTERN=false
  echo "✅ Variable actualizada a false"
else
  echo "✅ Variable ya está en false"
fi
```

---

## PASO 9: Reiniciar Servicios del Portal

```bash
kubectl delete pod -n portal -l app.kubernetes.io/name=portal --field-selector=status.phase=Running

echo "⏳ Esperando a que los pods se reinicien..."
sleep 30

kubectl get pods -n portal -l app.kubernetes.io/name=portal

echo "✅ Servicios reiniciados"
```

---

## PASO 10: Probar Login

1. **Abrir navegador en modo incógnito**
2. Navegar a: `http://portal.51.68.114.44.nip.io`
3. Click en **"Login"**
4. Introducir credenciales:
   - Email: `contacto@empresa.com`
   - Password: `Welcome2Catena-X!`
5. **Verificar:**
   - ✅ Redirige a: `http://sharedidp.51.68.114.44.nip.io/auth/realms/idpX/...`
   - ✅ Muestra pantalla de login de Keycloak
   - ✅ Tras login, muestra: "Complete Your Registration"

---

## Verificación Final

```bash
# Verificar empresa en base de datos
kubectl exec -n portal portal-portal-backend-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD \
  psql -U portal -d postgres -c \
  "SELECT id, name, business_partner_number, company_status_id 
   FROM portal.companies 
   WHERE name = 'NOMBRE_EMPRESA';"

# Ver logs recientes del Portal
kubectl logs -n portal -l app.kubernetes.io/name=portal-registration-service --tail=50
```

**✅ Onboarding completado cuando:**
- Usuario puede hacer login sin errores
- Portal muestra "Complete Your Registration"
- BPN aparece en base de datos
- Logs no muestran errores

---

## Troubleshooting Rápido

### Error: "Invalid username or password"
**Solución:** Verificar que la contraseña se configuró correctamente en PASO 6

### Error: "HTTPS required"
**Soluciones:**
1. Verificar `sslRequired: "none"` en PASO 4
2. Verificar REQUIRE_HTTPS en PASO 8
3. Verificar que existe cliente OAuth2 en PASO 5

### Error: Redirige a realm incorrecto
**Solución:** Verificar user_entity_id en base de datos (PASO 7)

### Portal no responde
**Solución:** Verificar que todos los pods están Running tras PASO 9

---

## Valores para Próximos Onboardings

### Assembly
- BPN: `BPNL000000002ASM`
- Realm esperado: `idp2`
- Display Name: `Assembly`

### Fagor
- BPN: `BPNL000000003FGR`
- Realm esperado: `idp3`
- Display Name: `Fagor`

---

**Documento creado:** 27 de Enero de 2026  
**Basado en:** Onboarding exitoso de Ikerlan (idp1)  
**Próxima ejecución:** 28 de Enero de 2026 con Assembly
