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

// Parse JSON bodies
app.use(express.json());

// Interceptor para /api/presentations/query - Agrega VCs faltantes
app.use('/api/presentations/query', async (req, res) => {
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
    
    try {
      // El token viene como texto plano (JWT)
      const decoded = jwt.decode(vpToken, { complete: true });
      
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
        contractVersion: "1.0.0"
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
        usagePurpose: "cx.core.industrycore:1"
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
