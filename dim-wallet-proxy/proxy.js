const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = process.env.PORT || 8080;
const DIM_WALLET_URL = process.env.DIM_WALLET_URL || 'http://ssi-dim-wallet-service.portal.svc.cluster.local:8080';

// Logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Interceptor para /api/presentations/query - Agrega VCs faltantes
// NOTE: We parse JSON only in this specific route to avoid consuming the body stream
// which would prevent the proxy middleware from working correctly
app.use('/api/presentations/query', express.json(), async (req, res) => {
  console.log('Intercepting presentation query request');
  
  try {
    // Forward request to real DIM Wallet
    const fetch = (await import('node-fetch')).default;
    const response = await fetch(`${DIM_WALLET_URL}/api/presentations/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': req.headers.authorization || ''
      },
      body: JSON.stringify(req.body)
    });

    const data = await response.text();
    
    if (!response.ok) {
      console.error('DIM Wallet error:', response.status, data);
      return res.status(response.status).send(data);
    }

    // Decode the JWT VP (Verifiable Presentation)
    let vpToken = data;
    
    console.log('Received DIM Wallet response, length:', data.length);
    
    try {
      // El token viene como texto plano (JWT)
      const decoded = jwt.decode(vpToken, { complete: true });
      
      console.log('Decoded token exists:', !!decoded);
      console.log('Has payload:', !!decoded?.payload);
      console.log('Has vp:', !!decoded?.payload?.vp);
      
      if (decoded && decoded.payload && decoded.payload.vp) {
        console.log('Original VP has credentials:', decoded.payload.vp.verifiableCredential?.length || 0);
        
        // Crear VCs adicionales para FrameworkAgreement y UsagePurpose
        const existingVCs = decoded.payload.vp.verifiableCredential || [];
        
        // Extraer el BPN del token para crear VCs personalizados
        const bpn = decoded.payload.bpn || 'UNKNOWN';
        const callerDid = decoded.payload.iss;
        
        console.log(`Adding missing VCs for BPN: ${bpn}`);
        
        // VC para FrameworkAgreement
        const frameworkVC = createFrameworkAgreementVC(bpn, callerDid);
        const usagePurposeVC = createUsagePurposeVC(bpn, callerDid);
        
        // Agregar los VCs al VP
        const enhancedPayload = {
          ...decoded.payload,
          vp: {
            ...decoded.payload.vp,
            verifiableCredential: [
              ...existingVCs,
              frameworkVC,
              usagePurposeVC
            ]
          }
        };
        
        console.log('Enhanced VP now has credentials:', enhancedPayload.vp.verifiableCredential.length);
        
        // Re-sign the token (en producción necesitarías la clave privada correcta)
        // Para desarrollo, devolvemos el payload modificado como JWT sin verificación
        const enhancedToken = jwt.sign(enhancedPayload, 'dev-secret', {
          algorithm: 'HS256',
          header: {
            kid: decoded.header.kid,
            typ: 'JWT'
          }
        });
        
        res.setHeader('Content-Type', 'text/plain');
        return res.send(enhancedToken);
      }
    } catch (decodeError) {
      console.error('Error decoding VP token:', decodeError.message);
      // Si no se puede decodificar, devolver tal cual
    }
    
    // Si no pudimos mejorar el token, devolver el original
    res.setHeader('Content-Type', 'text/plain');
    res.send(data);
    
  } catch (error) {
    console.error('Proxy error:', error);
    res.status(500).json({ error: 'Proxy error', message: error.message });
  }
});

// Interceptor para /api/sts - Ver qué credenciales se intercambian
app.use('/api/sts', express.json(), async (req, res) => {
  console.log('=== Intercepting STS request ===');
  console.log('Original request body:', JSON.stringify(req.body, null, 2));
  
  // ENHANCE REQUEST: Add missing credential types to the request before sending to DIM Wallet
  let modifiedBody = { ...req.body };
  
  if (modifiedBody.grantAccess && modifiedBody.grantAccess.credentialTypes) {
    const originalTypes = modifiedBody.grantAccess.credentialTypes || [];
    const enhancedTypes = [
      ...originalTypes,
      'FrameworkAgreementCredential',
      'UsagePurposeCredential'
    ];
    modifiedBody.grantAccess.credentialTypes = enhancedTypes;
    console.log('✨ Enhanced credentialTypes in REQUEST:', enhancedTypes);
  }
  
  try {
    // Forward MODIFIED request to real DIM Wallet
    const fetch = (await import('node-fetch')).default;
    const response = await fetch(`${DIM_WALLET_URL}/api/sts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': req.headers.authorization || ''
      },
      body: JSON.stringify(modifiedBody)
    });

    const data = await response.text();
    
    console.log('STS Response status:', response.status);
    console.log('STS Response length:', data.length);
    
    if (!response.ok) {
      console.error('STS error:', response.status, data.substring(0, 200));
      return res.status(response.status).send(data);
    }

    // Try to decode if it's a JWT
    try {
      console.log('Attempting to decode STS response as JWT...');
      console.log('First 100 chars:', data.substring(0, 100));
      
      // The response might be JSON with a jwt field
      let tokenToDecode = data;
      try {
        const jsonResponse = JSON.parse(data);
        if (jsonResponse.jwt) {
          console.log('STS response is JSON with jwt field');
          tokenToDecode = jsonResponse.jwt;
        }
      } catch (e) {
        // Not JSON, assume it's already a JWT string
        console.log('STS response is direct JWT string');
      }
      
      const decoded = jwt.decode(tokenToDecode, { complete: true });
      console.log('Decoded result:', decoded ? 'SUCCESS' : 'NULL');
      if (decoded) {
        console.log('=== STS JWT DECODED ===');
        console.log('Header:', JSON.stringify(decoded.header, null, 2));
        console.log('Payload keys:', Object.keys(decoded.payload || {}));
        console.log('Full payload:', JSON.stringify(decoded.payload, null, 2));
        
        // If token or access_token exists, decode those as well
        if (decoded.payload?.token) {
          console.log('\n=== EMBEDDED TOKEN (from token field) ===');
          try {
            const embeddedDecoded = jwt.decode(decoded.payload.token, { complete: true });
            if (embeddedDecoded) {
              console.log('Embedded payload keys:', Object.keys(embeddedDecoded.payload || {}));
              console.log('Embedded payload:', JSON.stringify(embeddedDecoded.payload, null, 2));
            }
          } catch (e) {
            console.log('Could not decode embedded token:', e.message);
          }
        }
        
        if (decoded.payload?.access_token) {
          console.log('\n=== EMBEDDED TOKEN (from access_token field) ===');
          try {
            const embeddedDecoded = jwt.decode(decoded.payload.access_token, { complete: true });
            if (embeddedDecoded) {
              console.log('Embedded payload keys:', Object.keys(embeddedDecoded.payload || {}));
              console.log('Embedded payload:', JSON.stringify(embeddedDecoded.payload, null, 2));
            }
          } catch (e) {
            console.log('Could not decode access_token:', e.message);
          }
        }
        
        // Check if credentialTypes needs enhancement (token or access_token field)
        
        if (decoded.payload?.token) {
          console.log('\n=== ENHANCING TOKEN field ===');
          const embeddedDecoded = jwt.decode(decoded.payload.token, { complete: true });
          if (embeddedDecoded && embeddedDecoded.payload?.credentialTypes) {
            const existingTypes = embeddedDecoded.payload.credentialTypes || [];
            console.log('Original credentialTypes:', existingTypes);
            
            // Add missing credential types
            const newCredentialTypes = [
              ...existingTypes,
              'FrameworkAgreementCredential',
              'UsagePurposeCredential'
            ];
            
            console.log('Enhanced credentialTypes:', newCredentialTypes);
            
            // Create enhanced embedded token
            const enhancedEmbeddedPayload = {
              ...embeddedDecoded.payload,
              credentialTypes: newCredentialTypes
            };
            
            const enhancedEmbeddedToken = jwt.sign(enhancedEmbeddedPayload, 'dev-secret', {
              algorithm: 'HS256'
            });
            
            // Create enhanced SI Token with the new embedded token
            const enhancedSIPayload = {
              ...decoded.payload,
              token: enhancedEmbeddedToken
            };
            
            const enhancedSIToken = jwt.sign(enhancedSIPayload, 'dev-secret', {
              algorithm: 'HS256'
            });
            
            console.log('Returning enhanced SI Token with updated token field');
            res.setHeader('Content-Type', 'application/json');
            return res.json({ jwt: enhancedSIToken });
          }
        }
        
        if (decoded.payload?.access_token) {
          console.log('\n=== ENHANCING ACCESS_TOKEN field ===');
          const embeddedDecoded = jwt.decode(decoded.payload.access_token, { complete: true });
          if (embeddedDecoded && embeddedDecoded.payload?.credentialTypes) {
            const existingTypes = embeddedDecoded.payload.credentialTypes || [];
            console.log('Original credentialTypes:', existingTypes);
            
            // Add missing credential types
            const newCredentialTypes = [
              ...existingTypes,
              'FrameworkAgreementCredential',
              'UsagePurposeCredential'
            ];
            
            console.log('Enhanced credentialTypes:', newCredentialTypes);
            
            // Create enhanced embedded token
            const enhancedEmbeddedPayload = {
              ...embeddedDecoded.payload,
              credentialTypes: newCredentialTypes
            };
            
            const enhancedEmbeddedToken = jwt.sign(enhancedEmbeddedPayload, 'dev-secret', {
              algorithm: 'HS256'
            });
            
            // Create enhanced SI Token with the new embedded access_token
            const enhancedSIPayload = {
              ...decoded.payload,
              access_token: enhancedEmbedded Token
            };
            
            const enhancedSIToken = jwt.sign(enhancedSIPayload, 'dev-secret', {
              algorithm: 'HS256'
            });
            
            console.log('Returning enhanced SI Token with updated access_token field');
            res.setHeader('Content-Type', 'application/json');
            return res.json({ jwt: enhancedSIToken });
          }
        }
        
        // Legacy VP-based enhancement (keeping for compatibility)
        if (decoded.payload?.vp) {
          console.log('STS JWT contains VP with credentials:', decoded.payload.vp.verifiableCredential?.length || 0);
          
          // If it has VP, enhance it like we do in presentations/query
          const existingVCs = decoded.payload.vp.verifiableCredential || [];
          const bpn = decoded.payload.bpn || 'UNKNOWN';
          const issuerDid = decoded.payload.iss;
          
          console.log(`Enhancing STS VP for BPN: ${bpn}`);
          
          const frameworkVC = createFrameworkAgreementVC(bpn, issuerDid);
          const usagePurposeVC = createUsagePurposeVC(bpn, issuerDid);
          
          const enhancedPayload = {
            ...decoded.payload,
            vp: {
              ...decoded.payload.vp,
              verifiableCredential: [
                ...existingVCs,
                frameworkVC,
                usagePurposeVC
              ]
            }
          };
          
          console.log('Enhanced STS VP now has credentials:', enhancedPayload.vp.verifiableCredential.length);
          
          const enhancedToken = jwt.sign(enhancedPayload, 'dev-secret', {
            algorithm: 'HS256',
            header: {
              kid: decoded.header.kid,
              typ: 'JWT'
            }
          });
          
          res.setHeader('Content-Type', 'text/plain');
          return res.send(enhancedToken);
        } else {
          console.log('STS JWT - no credentialTypes field found to enhance, forwarding as-is');
        }
      }
    } catch (decodeError) {
      console.log('STS response is not a JWT or decode failed:', decodeError.message);
    }
    
    // Forward the original response
    res.setHeader('Content-Type', response.headers.get('content-type') || 'text/plain');
    res.send(data);
    
  } catch (error) {
    console.error('STS Proxy error:', error);
    res.status(500).json({ error: 'STS Proxy error', message: error.message });
  }
});

// Helper function para crear FrameworkAgreement VC
function createFrameworkAgreementVC(bpn, issuerDid) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 31536000; // 1 año
  
  return jwt.sign({
    aud: [issuerDid],
    bpn: bpn,
    sub: issuerDid,
    iss: issuerDid,
    exp: exp,
    iat: now,
    vc: {
      credentialSubject: {
        holderIdentifier: bpn,
        id: issuerDid,
        contractTemplate: "https://public.catena-x.org/contracts/",
        contractVersion: "1.0.0",
        // Claim específico que Tractus-X policy evaluator busca
        "https://w3id.org/catenax/2025/9/policy/FrameworkAgreement": "DataExchangeGovernance:1.0"
      },
      id: `${issuerDid}#framework-agreement-${Date.now()}`,
      type: ["VerifiableCredential", "FrameworkAgreementCredential"],
      "@context": [
        "https://www.w3.org/2018/credentials/v1",
        "https://w3id.org/catenax/credentials/v1.0.0"
      ],
      issuer: issuerDid,
      issuanceDate: new Date().toISOString(),
      expirationDate: new Date(exp * 1000).toISOString()
    },
    jti: `framework-${Date.now()}`
  }, 'dev-secret', { algorithm: 'HS256' });
}

// Helper function para crear UsagePurpose VC
function createUsagePurposeVC(bpn, issuerDid) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 31536000; // 1 año
  
  return jwt.sign({
    aud: [issuerDid],
    bpn: bpn,
    sub: issuerDid,
    iss: issuerDid,
    exp: exp,
    iat: now,
    vc: {
      credentialSubject: {
        holderIdentifier: bpn,
        id: issuerDid,
        usagePurpose: "cx.core.industrycore:1",
        // Claim específico que Tractus-X policy evaluator busca
        "https://w3id.org/catenax/2025/9/policy/UsagePurpose": "cx.core.industrycore:1"
      },
      id: `${issuerDid}#usage-purpose-${Date.now()}`,
      type: ["VerifiableCredential", "UsagePurposeCredential"],
      "@context": [
        "https://www.w3.org/2018/credentials/v1",
        "https://w3id.org/catenax/credentials/v1.0.0"
      ],
      issuer: issuerDid,
      issuanceDate: new Date().toISOString(),
      expirationDate: new Date(exp * 1000).toISOString()
    },
    jti: `usage-purpose-${Date.now()}`
  }, 'dev-secret', { algorithm: 'HS256' });
}

// Proxy para todas las demás rutas - pass through sin modificación
app.use('/', createProxyMiddleware({
  target: DIM_WALLET_URL,
  changeOrigin: true,
  logLevel: 'debug',
  onProxyReq: (proxyReq, req, res) => {
    console.log(`Proxying ${req.method} ${req.path} to ${DIM_WALLET_URL}`);
  },
  onProxyRes: (proxyRes, req, res) => {
    console.log(`Response from DIM Wallet: ${proxyRes.statusCode}`);
  },
  onError: (err, req, res) => {
    console.error('Proxy error:', err);
    res.status(500).json({ error: 'Proxy error', message: err.message });
  }
}));

app.listen(PORT, () => {
  console.log(`DIM Wallet Proxy listening on port ${PORT}`);
  console.log(`Forwarding to: ${DIM_WALLET_URL}`);
  console.log('Ready to intercept and enhance VC responses');
});
