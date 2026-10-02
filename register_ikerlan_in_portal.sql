-- ===============================================================================
-- Script: Registro de Ikerlan como Business Partner en Portal
-- Fecha: 28 de Enero de 2026
-- Objetivo: Registrar la empresa Ikerlan en la base de datos del Portal
-- ===============================================================================

-- PASO 1: Verificar empresas existentes
SELECT id, name, business_partner_number FROM portal.companies WHERE name LIKE '%Ikerlan%';

-- PASO 2: Insertar la empresa Ikerlan
-- UUID para Ikerlan: usaremos uno generado
-- BPN: BPNL000000001IKL (ya definido)
INSERT INTO portal.companies (
    id,
    date_created,
    business_partner_number,
    name,
    shortname,
    company_status_id
) VALUES (
    'df8b4b7e-3c61-4a8f-9e5c-1a2b3c4d5e6f',  -- UUID generado para Ikerlan
    NOW(),
    'BPNL000000001IKL',
    'Ikerlan, S. Coop.',
    'Ikerlan',
    1  -- 1 = ACTIVE (verificar valores correctos en portal.company_statuses)
)
ON CONFLICT (id) DO NOTHING;

-- PASO 3: Verificar company_status_id correcto
SELECT id, label FROM portal.company_statuses;

-- PASO 4: Verificar que se insertó correctamente
SELECT id, name, business_partner_number, company_status_id, date_created 
FROM portal.companies 
WHERE business_partner_number = 'BPNL000000001IKL';

-- PASO 5: Buscar el usuario de Ikerlan en identities
-- Primero en la base de Keycloak obtuvimos: 6ce4fdb0-7264-41b1-aeb6-4b224ebb7b1f
-- Necesitamos relacionar este usuario con la empresa

-- PASO 6: Insertar en company_user_assigned_identity si la tabla existe
-- (Verificar estructura de tablas de identities)

-- PASO 7: Verificar tablas relacionadas con identities y users
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'portal' AND table_name LIKE '%identity%';

SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'portal' AND table_name LIKE '%user%';

-- ===============================================================================
-- NOTAS:
-- - El UUID de Ikerlan company: df8b4b7e-3c61-4a8f-9e5c-1a2b3c4d5e6f
-- - El BPN: BPNL000000001IKL
-- - El usuario Keycloak ID: 6ce4fdb0-7264-41b1-aeb6-4b224ebb7b1f
-- - Revisar si hay tablas adicionales que necesiten registros (address, etc.)
-- ===============================================================================
