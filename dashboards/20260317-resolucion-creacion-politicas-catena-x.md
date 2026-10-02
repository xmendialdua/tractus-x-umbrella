# Resolución de Problemas en Creación de Políticas EDC Catena-X

**Fecha:** 17 de marzo de 2026  
**Sistema:** Tractus-X EDC 0.11.1 - Management API v3  
**Conectores:** MASS (BPNL00000000MASS) e IKLN (BPNL00000002IKLN)  
**Objetivo:** Dashboard de publicación de assets con políticas restrictivas por BPN

---

## 📋 Resumen Ejecutivo

Durante el desarrollo del dashboard de publicación de assets EDC, nos encontramos con un **bug crítico en el validador de políticas** del EDC 0.11.1 que producía mensajes de error contradictorios al intentar crear políticas con constraints de Catena-X (BusinessPartnerNumber, FrameworkAgreement, UsagePurpose).

**Solución:** El problema se resolvió utilizando el formato oficial documentado en `tractus-x-umbrella`, que incluye **contexts JSON-LD específicos de Catena-X** que no estábamos usando inicialmente.

---

## 🎯 Tipos de Políticas en Eclipse Dataspace Connector

Antes de describir las políticas específicas, es importante entender los diferentes tipos de políticas disponibles en EDC y cuándo usar cada una.

### 1. Access Policy (Política de Acceso)

**Propósito:**  
Determina **quién puede VER** un asset en el catálogo del proveedor. Actúa como filtro de visibilidad.

**Cuándo usarla:**
- Para restringir qué participantes del dataspace pueden descubrir tus assets
- Para implementar control de acceso basado en atributos (BPN, membresía, etc.)
- Como primera barrera de seguridad antes de la negociación de contratos

**Action ODRL:** `access`

**Ejemplo de uso:**  
"Solo los partners con BPN A, B y C pueden ver este asset en su catálogo"

**Importante:** Si un consumer no cumple la Access Policy, **ni siquiera verá el asset** al consultar el catálogo del provider.

---

### 2. Contract Policy / Usage Policy (Política de Contrato/Uso)

**Propósito:**  
Define las **condiciones de uso** del asset una vez que se ha iniciado una negociación de contrato. Controla cómo se puede usar el dato.

**Cuándo usarla:**
- Para establecer términos de uso (propósito, frecuencia, duración, etc.)
- Para requerir acuerdos marco específicos (FrameworkAgreement)
- Para controlar permisos, prohibiciones y obligaciones del uso de datos

**Action ODRL:** `use`

**Ejemplo de uso:**  
"Este asset solo puede usarse para casos de uso de industrycore, bajo el acuerdo DataExchangeGovernance 1.0"

**Importante:** Cumplir la Contract Policy NO garantiza que el contrato se creará automáticamente, solo que el consumer es **elegible para iniciar la negociación**.

---

### 3. Policy Types - Comparativa

| Aspecto | Access Policy | Contract/Usage Policy |
|---------|---------------|----------------------|
| **Momento** | Durante catalog discovery | Durante contract negotiation |
| **Acción ODRL** | `access` | `use` |
| **Propósito** | Control de visibilidad | Control de términos de uso |
| **Si no se cumple** | Asset no aparece en catálogo | Negociación rechazada |
| **Constraints típicos** | BPN, Membership | UsagePurpose, FrameworkAgreement |
| **Obligatoria** | ✅ Sí (en Contract Definition) | ✅ Sí (en Contract Definition) |

---

### 4. Otros Tipos de Políticas

**Prohibition (Prohibición):**  
Define acciones que están explícitamente prohibidas. Por ejemplo: "No se permite redistribuir los datos".

**Obligation (Obligación):**  
Define acciones que el consumer DEBE realizar. Por ejemplo: "El consumer debe notificar al provider cada vez que use el dato".

**Nota:** En la práctica de Catena-X, las políticas `Permission` con constraints son las más utilizadas.

---

## 🔍 Problema Encontrado: Loop de Validación Contradictorio

### Contexto Inicial

Al intentar crear políticas con constraints de Catena-X usando el formato JSON-LD "estándar" del EDC, nos encontramos con errores contradictorios del validador.

### Síntomas del Bug

```bash
# Intento 1: Usando operador "EQ" con objetos @id
curl -X POST .../policydefinitions -d '{
  "odrl:operator": {"@id": "odrl:eq"},
  "odrl:leftOperand": {"@id": "cx-policy:BusinessPartnerNumber"}
}'

# ❌ Error: "Invalid operator: must be IS_ANY_OF, received EQ"

# Intento 2: Cambiando a IS_ANY_OF
curl -X POST .../policydefinitions -d '{
  "odrl:operator": {"@id": "odrl:isAnyOf"},
  "odrl:rightOperand": ["BPNL00000002IKLN"]
}'

# ❌ Error: "Invalid operator: must be EQ, received IS_ANY_OF"

# Intento 3: Usando LogicalConstraint con EQ
# ❌ Error: "Invalid operator: must be IS_ANY_OF"

# Intento 4: Sin LogicalConstraint con IS_ANY_OF  
# ❌ Error: "Invalid operator: must be EQ"
```

### Análisis del Problema

Después de ~20 iteraciones de pruebas con `curl`, identificamos que:

1. **Diferentes formatos JSON-LD producían diferentes mensajes de error**
2. El validador parecía tener **múltiples validadores compitiendo** entre sí
3. Los mensajes de error se contradecían dependiendo de la estructura del JSON
4. No había ejemplos de políticas con constraints en el sistema (todas las políticas existentes estaban vacías)

### Causa Raíz

**El problema NO era el operador ni la estructura**, sino la **falta de contexts JSON-LD de Catena-X**. Sin estos contexts, el EDC no podía:
- Interpretar correctamente los leftOperands simples como strings
- Expandirlos a las URLs completas de Catena-X
- Aplicar los validadores correctos para cada constraint

---

## ✅ Solución: Uso de Contexts JSON-LD de Catena-X

### Fuente de la Solución

La solución se encontró en la **documentación oficial de tractus-x-umbrella**:

**Ubicación:**
- `docs/user/common/guides/data-exchange/provide-data.md` (líneas 381-500)
- `docs/common/api/bruno/Umbrella-bru/01-Provide_Data/05-Create The Policy.bru`
- `docs/common/api/bruno/Umbrella-bru/01-Provide_Data/05_2-Create The Policy.bru`

### Elemento Crítico: El @context Correcto

```json
{
  "@context": [
    "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",      ← CRÍTICO
    "https://w3id.org/catenax/2025/9/policy/context.jsonld",   ← CRÍTICO
    {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    }
  ]
}
```

**¿Qué hacen estos contexts?**

1. **`odrl.jsonld`:** Define el vocabulario ODRL y mapea operadores/acciones
2. **`context.jsonld`:** Define los constraints específicos de Catena-X y sus validadores
3. **`@vocab`:** Namespace por defecto para el vocabulario EDC

Con estos contexts, el EDC puede:
- Interpretar `"leftOperand": "BusinessPartnerNumber"` (string simple)
- Expandirlo internamente a `"https://w3id.org/catenax/2025/9/policy/BusinessPartnerNumber"`
- Aplicar los validadores correctos registrados para ese constraint

---

## 📝 Política 1: cx-policy-ikln-access-test

### a) ¿Para qué es?

Esta política controla **quién puede VER** los assets de MASS en su catálogo. Actúa como filtro de visibilidad para restringir el acceso solo a participantes autorizados (en este caso, IKLN con BPN `BPNL00000002IKLN`).

**Escenario de uso:**  
Cuando IKLN (consumer) realiza un catalog request hacia MASS (provider), el EDC de MASS evalúa esta Access Policy. Si IKLN cumple los constraints (tiene el BPN correcto, membresía activa, y acepta el FrameworkAgreement), entonces los assets asociados a esta política aparecerán en el catálogo devuelto a IKLN.

---

### b) Tipo de Política

**Tipo:** Access Policy (Política de Acceso)

**Significado:**  
Define criterios que determinan si un participante del dataspace puede **descubrir y ver** un asset específico en el catálogo del provider. Es la primera barrera de seguridad.

**Action ODRL:** `access`

**¿Por qué "access" y no "use"?**  
Porque esta política se evalúa **antes** de la negociación de contratos, durante la fase de catalog discovery. Si no se cumple, el consumer ni siquiera sabrá que el asset existe.

---

### c) ¿Qué Controla?

Esta política controla **3 constraints principales**:

#### 1. Membership (Membresía)
```json
{
  "leftOperand": "Membership",
  "operator": "eq",
  "rightOperand": "active"
}
```
**Significado:** El participante debe tener membresía activa en el dataspace Catena-X.

#### 2. FrameworkAgreement (Acuerdo Marco)
```json
{
  "leftOperand": "FrameworkAgreement",
  "operator": "eq",
  "rightOperand": "DataExchangeGovernance:1.0"
}
```
**Significado:** El participante debe haber aceptado el acuerdo marco "DataExchangeGovernance versión 1.0", que define las reglas de gobernanza del intercambio de datos.

#### 3. BusinessPartnerNumber (Número de Socio Comercial)
```json
{
  "leftOperand": "BusinessPartnerNumber",
  "operator": "isAnyOf",
  "rightOperand": ["BPNL00000002IKLN"]
}
```
**Significado:** El participante debe tener uno de los BPNs listados (en este caso, solo IKLN). Este es el control más específico para permitir acceso solo a partners seleccionados.

**Nota sobre operadores:**
- `Membership` y `FrameworkAgreement` usan `eq` (igualdad estricta)
- `BusinessPartnerNumber` usa `isAnyOf` (pertenencia a lista) para permitir múltiples BPNs

---

### d) ¿Cómo se Debe Utilizar?

#### Paso 1: Crear la Política

```bash
curl -X POST 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/policydefinitions' \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Key: mass-api-key-change-in-production' \
  --data-raw '{
    "@context": [
      "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",
      "https://w3id.org/catenax/2025/9/policy/context.jsonld",
      {
        "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
      }
    ],
    "@id": "cx-policy-ikln-access",
    "@type": "PolicyDefinition",
    "policy": {
      "@type": "Set",
      "permission": [{
        "action": "access",
        "constraint": [{
          "and": [
            {
              "leftOperand": "Membership",
              "operator": "eq",
              "rightOperand": "active"
            },
            {
              "leftOperand": "FrameworkAgreement",
              "operator": "eq",
              "rightOperand": "DataExchangeGovernance:1.0"
            },
            {
              "leftOperand": "BusinessPartnerNumber",
              "operator": "isAnyOf",
              "rightOperand": ["BPNL00000002IKLN"]
            }
          ]
        }]
      }]
    }
  }'
```

#### Paso 2: Vincularla a un Asset mediante Contract Definition

La Access Policy **no funciona sola**. Debe estar vinculada a un asset mediante una Contract Definition:

```bash
curl -X POST 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/contractdefinitions' \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Key: mass-api-key-change-in-production' \
  --data-raw '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@id": "contract-def-ikln",
    "@type": "ContractDefinition",
    "accessPolicyId": "cx-policy-ikln-access",      ← Referencia a Access Policy
    "contractPolicyId": "cx-policy-ikln-usage",     ← Referencia a Usage Policy
    "assetsSelector": [{
      "operandLeft": "@id",
      "operator": "=",
      "operandRight": "asset-sharepoint-ikln"
    }]
  }'
```

#### Paso 3: Verificación

Desde IKLN (consumer), hacer catalog request:
```bash
curl -X POST 'https://edc-ikln-control.51.178.94.25.nip.io/management/v3/catalog/request' \
  -H 'X-Api-Key: ikln-api-key' \
  --data-raw '{
    "counterPartyAddress": "http://edc-mass-control.51.178.94.25.nip.io/api/v1/dsp",
    "protocol": "dataspace-protocol-http"
  }'
```

**Resultado esperado:** El asset aparecerá en el catálogo si IKLN cumple los constraints.

---

### e) Problema y Correcciones Aplicadas

#### Problema Original

**Intentos fallidos (formato incorrecto):**

```json
// ❌ Intento 1: Sin contexts de Catena-X, con objetos @id
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/",
    "cx-policy": "https://w3id.org/catenax/2025/9/policy/"
  },
  "policy": {
    "@type": "odrl:Set",
    "odrl:permission": [{
      "odrl:action": {"@id": "odrl:use"},
      "odrl:constraint": [{
        "odrl:leftOperand": {"@id": "cx-policy:BusinessPartnerNumber"},
        "odrl:operator": {"@id": "odrl:eq"},
        "odrl:rightOperand": "BPNL00000002IKLN"
      }]
    }]
  }
}
```

**Error recibido:**
```
Invalid operator: this constraint only allows the following operators: [IS_ANY_OF], but received 'EQ'
```

**¿Por qué fallaba?**
1. Faltaban los contexts JSON-LD de Catena-X
2. Los operadores estaban como objetos `{@id: "odrl:eq"}` en lugar de strings
3. El `@type` era `odrl:Set` en lugar de `Set` (sin namespace)
4. La acción era `use` en lugar de `access`

---

#### Correcciones Aplicadas

**✅ Formato correcto que funcionó:**

```json
{
  "@context": [
    "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",      // ← AÑADIDO
    "https://w3id.org/catenax/2025/9/policy/context.jsonld",   // ← AÑADIDO
    {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    }
  ],
  "@id": "cx-policy-ikln-access-test",
  "@type": "PolicyDefinition",
  "policy": {
    "@type": "Set",                                            // ← SIN namespace odrl:
    "permission": [{                                           // ← SIN namespace odrl:
      "action": "access",                                      // ← String simple, no objeto
      "constraint": [{
        "and": [
          {
            "leftOperand": "Membership",                       // ← String simple
            "operator": "eq",                                  // ← String simple
            "rightOperand": "active"
          },
          {
            "leftOperand": "FrameworkAgreement",
            "operator": "eq",
            "rightOperand": "DataExchangeGovernance:1.0"
          },
          {
            "leftOperand": "BusinessPartnerNumber",
            "operator": "isAnyOf",                             // ← isAnyOf para BPN
            "rightOperand": ["BPNL00000002IKLN"]              // ← Array
          }
        ]
      }]
    }]
  }
}
```

**Cambios clave:**

| Aspecto | ❌ Incorrecto | ✅ Correcto |
|---------|--------------|-------------|
| **@context** | Solo namespace EDC | Incluye contexts Catena-X |
| **@type policy** | `"odrl:Set"` | `"Set"` |
| **action** | `{"@id": "odrl:use"}` | `"access"` |
| **leftOperand** | `{"@id": "cx-policy:BPN"}` | `"BusinessPartnerNumber"` |
| **operator** | `{"@id": "odrl:eq"}` | `"eq"` o `"isAnyOf"` |
| **rightOperand BPN** | String simple | Array `["BPN"]` |

---

## 📝 Política 2: cx-policy-ikln-usage-test

### a) ¿Para qué es?

Esta política define **cómo se puede USAR** el asset una vez que se ha descubierto en el catálogo y se está iniciando una negociación de contrato. Establece los términos y condiciones de uso del dato.

**Escenario de uso:**  
Después de que IKLN ve el asset en el catálogo (gracias a pasar la Access Policy), cuando intenta iniciar una Contract Negotiation, el EDC de MASS evalúa esta Usage Policy. Si IKLN cumple los constraints (membresía, acuerdo marco, y propósito de uso válido), entonces la negociación puede proceder.

---

### b) Tipo de Política

**Tipo:** Contract Policy / Usage Policy (Política de Contrato/Uso)

**Significado:**  
Define las condiciones bajo las cuales un asset puede ser utilizado. Se evalúa durante la negociación de contratos para determinar si el consumer es elegible para obtener acceso al dato.

**Action ODRL:** `use`

**¿Por qué "use" y no "access"?**  
Porque esta política se evalúa **durante** la negociación de contratos, no durante el catalog discovery. Define términos de USO, no de VISIBILIDAD.

---

### c) ¿Qué Controla?

Esta política controla **3 constraints principales**:

#### 1. Membership (Membresía)
```json
{
  "leftOperand": "Membership",
  "operator": "eq",
  "rightOperand": "active"
}
```
**Significado:** Igual que en Access Policy - membresía activa requerida.

#### 2. FrameworkAgreement (Acuerdo Marco)
```json
{
  "leftOperand": "FrameworkAgreement",
  "operator": "eq",
  "rightOperand": "DataExchangeGovernance:1.0"
}
```
**Significado:** Igual que en Access Policy - acuerdo marco requerido.

#### 3. UsagePurpose (Propósito de Uso)
```json
{
  "leftOperand": "UsagePurpose",
  "operator": "isAnyOf",
  "rightOperand": ["cx.core.industrycore:1"]
}
```
**Significado:** El dato solo puede usarse para el propósito declarado "industrycore versión 1". Esto impide que el consumer use el dato para propósitos diferentes a los acordados.

**Diferencia clave con Access Policy:**  
- Access Policy usa `BusinessPartnerNumber` (QUIÉN)
- Usage Policy usa `UsagePurpose` (PARA QUÉ)

---

### d) ¿Cómo se Debe Utilizar?

#### Paso 1: Crear la Política

```bash
curl -X POST 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/policydefinitions' \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Key: mass-api-key-change-in-production' \
  --data-raw '{
    "@context": [
      "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",
      "https://w3id.org/catenax/2025/9/policy/context.jsonld",
      {
        "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
      }
    ],
    "@type": "PolicyDefinition",
    "@id": "cx-policy-ikln-usage",
    "policy": {
      "@type": "Set",
      "permission": [{
        "action": "use",
        "constraint": {
          "and": [
            {
              "leftOperand": "Membership",
              "operator": "eq",
              "rightOperand": "active"
            },
            {
              "leftOperand": "FrameworkAgreement",
              "operator": "eq",
              "rightOperand": "DataExchangeGovernance:1.0"
            },
            {
              "leftOperand": "UsagePurpose",
              "operator": "isAnyOf",
              "rightOperand": ["cx.core.industrycore:1"]
            }
          ]
        }
      }],
      "prohibition": [],
      "obligation": []
    }
  }'
```

#### Paso 2: Vincularla a Contract Definition

Esta Usage Policy debe ir junto con la Access Policy en la Contract Definition:

```bash
curl -X POST 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/contractdefinitions' \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Key: mass-api-key-change-in-production' \
  --data-raw '{
    "@context": {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@id": "contract-def-ikln",
    "@type": "ContractDefinition",
    "accessPolicyId": "cx-policy-ikln-access",      ← Access Policy
    "contractPolicyId": "cx-policy-ikln-usage",     ← Usage Policy (ESTA)
    "assetsSelector": [{
      "operandLeft": "@id",
      "operator": "=",
      "operandRight": "asset-sharepoint-ikln"
    }]
  }'
```

#### Paso 3: Negociación de Contrato

Desde IKLN, iniciar negociación:
```bash
curl -X POST 'https://edc-ikln-control.51.178.94.25.nip.io/management/v3/contractnegotiations' \
  -H 'X-Api-Key: ikln-api-key' \
  --data-raw '{
    "counterPartyAddress": "http://edc-mass-control.51.178.94.25.nip.io/api/v1/dsp",
    "protocol": "dataspace-protocol-http",
    "counterPartyId": "BPNL00000000MASS",
    "providerId": "BPNL00000000MASS",
    "offer": {
      "offerId": "offer-id-from-catalog",
      "assetId": "asset-sharepoint-ikln",
      "policy": { ... }
    }
  }'
```

**Resultado esperado:** La negociación procederá si IKLN cumple los constraints de uso.

---

### e) Problema y Correcciones Aplicadas

#### Problema Original

El problema fue **exactamente el mismo** que con la Access Policy: validación contradictoria por falta de contexts de Catena-X.

**Intento fallido:**

```json
// ❌ Sin contexts de Catena-X
{
  "@context": {
    "@vocab": "https://w3id.org/edc/v0.0.1/ns/",
    "odrl": "http://www.w3.org/ns/odrl/2/"
  },
  "policy": {
    "@type": "odrl:Set",
    "odrl:permission": [{
      "odrl:action": {"@id": "odrl:use"},
      "odrl:constraint": [{
        "odrl:leftOperand": {"@id": "https://w3id.org/catenax/2025/9/policy/UsagePurpose"},
        "odrl:operator": {"@id": "odrl:isAnyOf"},
        "odrl:rightOperand": ["cx.core.industrycore:1"]
      }]
    }]
  }
}
```

**Errores recibidos:**
```
Invalid operator: this constraint only allows the following operators: EQ, but received 'IS_ANY_OF'
```

*(Luego al cambiar a EQ, decía que debía ser IS_ANY_OF - mismo loop contradictorio)*

---

#### Correcciones Aplicadas

**✅ Formato correcto que funcionó:**

```json
{
  "@context": [
    "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",      // ← AÑADIDO
    "https://w3id.org/catenax/2025/9/policy/context.jsonld",   // ← AÑADIDO
    {
      "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    }
  ],
  "@type": "PolicyDefinition",
  "@id": "cx-policy-ikln-usage-test",
  "policy": {
    "@type": "Set",                                            // ← SIN namespace
    "permission": [{
      "action": "use",                                         // ← String simple
      "constraint": {
        "and": [
          {
            "leftOperand": "Membership",                       // ← String simple
            "operator": "eq",
            "rightOperand": "active"
          },
          {
            "leftOperand": "FrameworkAgreement",
            "operator": "eq",
            "rightOperand": "DataExchangeGovernance:1.0"
          },
          {
            "leftOperand": "UsagePurpose",                     // ← String simple
            "operator": "isAnyOf",
            "rightOperand": ["cx.core.industrycore:1"]        // ← Array
          }
        ]
      }
    }],
    "prohibition": [],
    "obligation": []
  }
}
```

**Diferencias con Access Policy:**

| Aspecto | Access Policy | Usage Policy |
|---------|---------------|--------------|
| **action** | `"access"` | `"use"` |
| **Constraint específico** | `BusinessPartnerNumber` (QUIÉN) | `UsagePurpose` (PARA QUÉ) |
| **Estructura constraint** | Array `[{and: [...]}]` | Objeto `{and: [...]}` |
| **prohibition/obligation** | Opcional | Opcional pero recomendado incluir vacío |

**Nota importante sobre la estructura:**  
Ambas estructuras funcionan (constraint como array o como objeto). La Usage Policy en la documentación oficial usa objeto directo sin array wrapper, pero ambas son válidas.

---

## 🔧 Resumen de Cambios Necesarios

### Cambios Críticos que Resuelven el Problema

1. **Añadir contexts de Catena-X:**
   ```json
   "@context": [
     "https://w3id.org/catenax/2025/9/policy/odrl.jsonld",
     "https://w3id.org/catenax/2025/9/policy/context.jsonld",
     {"@vocab": "https://w3id.org/edc/v0.0.1/ns/"}
   ]
   ```

2. **Usar strings simples, NO objetos @id:**
   - ✅ `"action": "access"`
   - ❌ `"odrl:action": {"@id": "odrl:access"}`

3. **Usar tipos sin namespace explícito:**
   - ✅ `"@type": "Set"`
   - ❌ `"@type": "odrl:Set"`

4. **Operadores específicos por constraint:**
   - `Membership`: usa `"eq"` con string
   - `FrameworkAgreement`: usa `"eq"` con string
   - `BusinessPartnerNumber`: usa `"isAnyOf"` con **array**
   - `UsagePurpose`: usa `"isAnyOf"` con **array**

### Cambios NO Necesarios (funcionan ambas formas)

- Constraint como array `[{and: [...]}]` vs objeto `{and: [...]}`
- Incluir o no `prohibition` y `obligation` vacíos
- Orden de los constraints dentro del `and`

---

## 📊 Resultados de las Pruebas

### Políticas Creadas Exitosamente

```bash
# Verificar Access Policy
curl -X GET 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/policydefinitions/cx-policy-ikln-access-test' \
  -H 'X-Api-Key: mass-api-key-change-in-production'

# ✅ Respuesta: HTTP 200 - Política creada correctamente
```

```bash
# Verificar Usage Policy
curl -X GET 'https://edc-mass-control.51.178.94.25.nip.io/management/v3/policydefinitions/cx-policy-ikln-usage-test' \
  -H 'X-Api-Key: mass-api-key-change-in-production'

# ✅ Respuesta: HTTP 200 - Política creada correctamente
```

### Estructura Interna Resultante

El EDC almacena las políticas expandiendo los contexts. Por ejemplo, `"leftOperand": "BusinessPartnerNumber"` se expande internamente a:

```json
{
  "odrl:leftOperand": {
    "@id": "https://w3id.org/catenax/2025/9/policy/BusinessPartnerNumber"
  }
}
```

Esto confirma que los contexts están funcionando correctamente.

---

## 🎓 Lecciones Aprendidas

### 1. La Importancia de los Contexts JSON-LD

Los contexts JSON-LD no son opcionales en sistemas basados en Linked Data. Son **fundamentales** para:
- Mapear términos simples a URIs completas
- Definir vocabularios y namespaces
- Habilitar validadores específicos por término
- Permitir interoperabilidad semántica

### 2. Testing Incremental

El enfoque de testing incremental fue clave:
1. Primero políticas vacías (solo action, sin constraints)
2. Luego un constraint
3. Luego dos constraints
4. Finalmente los tres constraints obligatorios

Esto permitió identificar exactamente qué parte fallaba en cada iteración.

### 3. Documentación Oficial es la Fuente de Verdad

Aunque los errores del validador eran confusos, la **documentación oficial de tractus-x-umbrella** contenía el formato correcto desde el inicio. Siempre consultar:
- Docs oficiales del proyecto
- Colecciones API (Bruno/Postman)
- Ejemplos de código en el repositorio

### 4. Versioning de Contexts

Los contexts usan versioning en la URL: `/2025/9/policy/`. Esto es importante porque:
- Diferentes versiones pueden tener diferentes validadores
- Cambios de versión pueden introducir breaking changes
- Siempre usar la versión que coincida con tu release de EDC

---

## 🚀 Próximos Pasos

### 1. Actualizar Backend del Dashboard

Aplicar el formato correcto en:
- `backend.py` - función `create_access_policy()`
- `backend.py` - función `create_contract_policy()`

### 2. Testing de Flujo Completo

Una vez actualizadas las funciones del backend:
1. Crear asset desde dashboard
2. Crear Access Policy con BPN
3. Crear Usage Policy con UsagePurpose
4. Crear Contract Definition vinculando asset + políticas
5. Verificar desde IKLN que el asset aparece en catálogo
6. Intentar negociación de contrato
7. Verificar que la negociación se completa exitosamente

### 3. Documentar en el Dashboard

Añadir tooltips/ayuda en la UI explicando:
- Diferencia entre Access y Usage policies
- Qué BPNs están permitidos
- Qué UsagePurposes son válidos
- Validación de formato antes de enviar al EDC

### 4. Consideraciones de Producción

Para producción, considerar:
- Permitir múltiples BPNs en Access Policy (lista dinámica)
- Permitir múltiples UsagePurposes en Usage Policy
- Validación de BPNs contra BPDM (Business Partner Data Management)
- Logging de intentos de acceso fallidos
- Métricas de uso de políticas

---

## 📚 Referencias

### Documentación Oficial Tractus-X

- **Guía de provisión de datos:**  
  `docs/user/common/guides/data-exchange/provide-data.md`
  
- **Colección Bruno API:**  
  `docs/common/api/bruno/Umbrella-bru/01-Provide_Data/`

### Especificaciones Catena-X

- **Catena-X Policy Context:**  
  `https://w3id.org/catenax/2025/9/policy/context.jsonld`
  
- **ODRL Vocabulary:**  
  `http://www.w3.org/ns/odrl/2/`

### EDC Documentation

- **Eclipse Dataspace Components:**  
  https://github.com/eclipse-edc/Connector
  
- **Tractus-X EDC:**  
  https://github.com/eclipse-tractusx/tractusx-edc

---

## ✅ Conclusión

El problema de validación contradictoria de políticas en EDC 0.11.1 se resolvió mediante el uso del formato oficial documentado en tractus-x-umbrella, que incluye **contexts JSON-LD específicos de Catena-X**.

**Key Takeaway:** Los contexts JSON-LD de Catena-X (`odrl.jsonld` y `context.jsonld`) son **OBLIGATORIOS** para crear políticas con constraints de Catena-X. Sin ellos, el validador del EDC no puede interpretar correctamente los operadores y leftOperands, produciendo errores contradictorios.

Ambas políticas (`cx-policy-ikln-access-test` y `cx-policy-ikln-usage-test`) fueron creadas exitosamente y están listas para ser vinculadas a assets mediante Contract Definitions.

---

**Documento generado:** 17 de marzo de 2026  
**Autor:** Dashboard Development Team  
**Sistema:** Tractus-X EDC 0.11.1 - MASS & IKLN Connectors
