#!/bin/bash
###############################################################
# Script para crear Policies y Contract Definition en MASS
# Para permitir acceso a IKLN (BPNL00000002IKLN)
###############################################################

set -e

MASS_URL="https://edc-mass-control.51.178.94.25.nip.io"
API_KEY="mass-api-key-change-in-production"
ASSET_ID="test-asset-mass-pdf"
IKLN_BPN="BPNL00000002IKLN"

echo "=========================================="
echo "Creando Policies para MASS Connector"
echo "=========================================="

# Política 1: Access Policy (permite ver en catálogo)
echo -e "\n[1/3] Creando Access Policy..."
curl -k -X POST "${MASS_URL}/management/v3/policydefinitions" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d @- << 'EOF'
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "access-policy-ikln-only",
  "@type": "PolicyDefinition",
  "policy": {
    "@type": "odrl:Set",
    "odrl:permission": [{
      "odrl:action": "odrl:use",
      "odrl:constraint": [{
        "odrl:leftOperand": "BusinessPartnerNumber",
        "odrl:operator": "eq",
        "odrl:rightOperand": "BPNL00000002IKLN"
      }]
    }]
  }
}
EOF

echo -e "\n✅ Access Policy creada\n"

# Política 2: Contract/Usage Policy (controla uso del asset)
echo "[2/3] Creando Contract/Usage Policy..."
curl -k -X POST "${MASS_URL}/management/v3/policydefinitions" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d @- << 'EOF'
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "@id": "contract-policy-ikln-only",
  "@type": "PolicyDefinition",
  "policy": {
    "@type": "odrl:Set",
    "odrl:permission": [{
      "odrl:action": "odrl:use",
      "odrl:constraint": [{
        "odrl:leftOperand": "BusinessPartnerNumber",
        "odrl:operator": "eq",
        "odrl:rightOperand": "BPNL00000002IKLN"
      }]
    }]
  }
}
EOF

echo -e "\n✅ Contract Policy creada\n"

# Contract Definition vinculando asset con policies
echo "[3/3] Creando Contract Definition..."
curl -k -X POST "${MASS_URL}/management/v3/contractdefinitions" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d @- << EOF
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
  },
  "@id": "contract-def-mass-pdf-ikln",
  "@type": "ContractDefinition",
  "accessPolicyId": "access-policy-ikln-only",
  "contractPolicyId": "contract-policy-ikln-only",
  "assetsSelector": {
    "operandLeft": "https://w3id.org/edc/v0.0.1/ns/id",
    "operator": "=",
    "operandRight": "${ASSET_ID}"
  }
}
EOF

echo -e "\n✅ Contract Definition creado\n"

# Verificación
echo "=========================================="
echo "Verificando configuración..."
echo "=========================================="

echo -e "\nPolicies existentes:"
curl -k -s -X POST "${MASS_URL}/management/v3/policydefinitions/request" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"}}' | \
  jq -r '.[]["@id"]' | grep -E "ikln|policy" || echo "No policies found"

echo -e "\nContract Definitions existentes:"
curl -k -s -X POST "${MASS_URL}/management/v3/contractdefinitions/request" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"}}' | \
  jq -r '.[]["@id"]' | grep -E "ikln|mass" || echo "No contract definitions found"

echo -e "\n=========================================="
echo "✅ Configuración completada"
echo "=========================================="
echo ""
echo "El asset '${ASSET_ID}' ahora está disponible en el catálogo"
echo "y puede ser accedido por IKLN (${IKLN_BPN})"
echo ""
