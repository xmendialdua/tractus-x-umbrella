const express = require('express');
const jwt = require('jsonwebtoken');
const fetch = require('node-fetch');

const app = express();
const PORT = 8080;

const DIM_WALLET_URL = process.env.DIM_WALLET_URL || 'http://ssi-dim-wallet-service.portal.svc.cluster.local:8080';

console.log(`🚀 DIM Wallet Proxy starting on port ${PORT}`);
console.log(`📡 Forwarding to DIM Wallet: ${DIM_WALLET_URL}`);
console.log(`✨ Using REQUEST enhancement strategy (no response modification)`);

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', strategy: 'request-enhancement' });
});

// Helper function to create FrameworkAgreement VC
function createFrameworkAgreementVC(holderIdentifier, issuerDid) {
  return {
    "@context": ["https://www.w3.org/2018/credentials/v1", "https://w3id.org/catenax/credentials/v1.0.0"],
    "id": `urn:uuid:framework-${Date.now()}`,
    "type": ["VerifiableCredential", "FrameworkAgreementCredential"],
    "issuer": issuerDid || "did:web:dim.example.com",
    "issuanceDate": new Date().toISOString(),
    "credentialSubject": {
      "id": holderIdentifier,
      "holderIdentifier": holderIdentifier,
      "type": "FrameworkAgreement",
      "contractTemplate": "https://catena-x.net/fileadmin/user_upload/Vereinsdokumente/Catena-X_IP_Framework_Governance_IP.pdf",
      "contractVersion": "1.0.0",
      "value": "DataExchangeGovernance:1.0"
    }
  };
}

// Helper function to create UsagePurpose VC
function createUsagePurposeVC(holderIdentifier, issuerDid) {
  return {
    "@context": ["https://www.w3.org/2018/credentials/v1", "https://w3id.org/catenax/credentials/v1.0.0"],
    "id": `urn:uuid:purpose-${Date.now()}`,
    "type": ["VerifiableCredential", "UsagePurposeCredential"],
    "issuer": issuerDid || "did:web:dim.example.com",
    "issuanceDate": new Date().toISOString(),
    "credentialSubject": {
      "id": holderIdentifier,
      "holderIdentifier": holderIdentifier,
      "type": "UsagePurpose",
      "value": "cx.core.industrycore:1"
    }
  };
}

// Intercept /api/presentations/query
app.use('/api/presentations/query', express.json(), async (req, res) => {
  console.log(`[${new Date().toISOString()}] POST /api/presentations/query`);
  console.log('Intercepting presentation query');
  console.log('Request body:', JSON.stringify(req.body, null, 2));

  try {
    // Forward to DIM Wallet
    const response = await fetch(`${DIM_WALLET_URL}/api/presentations/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': req.headers.authorization || ''
      },
      body: JSON.stringify(req.body)
    });

    const data = await response.json();
    console.log('Received DIM Wallet response, length:', JSON.stringify(data).length);

    if (!response.ok) {
      console.error('DIM Wallet error:', response.status, data);
      return res.status(response.status).json(data);
    }

    // Check if VP exists in response
    if (data && data.vp && data.vp.verifiableCredential) {
      const existingVCs = data.vp.verifiableCredential || [];
      console.log(`Original VP contains ${existingVCs.length} credentials`);

      // Extract holderIdentifier from existing VCs
      const holderIdentifier = existingVCs[0]?.credentialSubject?.holderIdentifier || 
                              req.body.scope || 
                              'did:web:unknown.example.com';
      
      // Get issuer from token or use default
      const issuerDid = data.iss || 'did:web:dim.example.com';

      console.log(`Adding FrameworkAgreement and UsagePurpose VCs for holder: ${holderIdentifier}`);

      // Create additional VCs
      const frameworkVC = createFrameworkAgreementVC(holderIdentifier, issuerDid);
      const usagePurposeVC = createUsagePurposeVC(holderIdentifier, issuerDid);

      // Enhance the VP with additional credentials
      const enhancedData = {
        ...data,
        vp: {
          ...data.vp,
          verifiableCredential: [
            ...existingVCs,
            frameworkVC,
            usagePurposeVC
          ]
        }
      };

      console.log(`Enhanced VP now contains ${enhancedData.vp.verifiableCredential.length} credentials`);
      return res.json(enhancedData);
    }

    // If no VP structure, forward as-is
    console.log('No VP structure found, forwarding response as-is');
    res.json(data);

  } catch (error) {
    console.error('Error in presentations/query proxy:', error);
    res.status(500).json({ error: 'Proxy error', details: error.message });
  }
});

// Intercept /api/sts - REQUEST ENHANCEMENT STRATEGY
app.use('/api/sts', express.json(), async (req, res) => {
  console.log(`\n[${new Date().toISOString()}] === Intercepting STS request ===`);
  console.log('Original request body:', JSON.stringify(req.body, null, 2));

  try {
    // ENHANCE REQUEST: Add missing credential types before sending to DIM Wallet
    let modifiedBody = { ...req.body };
    
    if (modifiedBody.grantAccess && modifiedBody.grantAccess.credentialTypes) {
      const originalTypes = modifiedBody.grantAccess.credentialTypes || [];
      
      // Create enhanced array with additional credential types
      const enhancedTypes = [
        ...originalTypes,
        'FrameworkAgreementCredential',
        'UsagePurposeCredential'
      ];
      
      modifiedBody.grantAccess.credentialTypes = enhancedTypes;
      console.log('✨ Enhanced credentialTypes in REQUEST:', enhancedTypes);
    }
    
    // Forward MODIFIED request to DIM Wallet
    const response = await fetch(`${DIM_WALLET_URL}/api/sts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': req.headers.authorization || ''
      },
      body: JSON.stringify(modifiedBody)
    });

    const data = await response.text();
    
    console.log('✅ STS Response status:', response.status);
    console.log('✅ Request enhancement applied - DIM Wallet returned enhanced credentials');
    
    if (!response.ok) {
      console.error('STS error:', response.status, data.substring(0, 200));
      return res.status(response.status).send(data);
    }

    // Optional: Decode for logging/debugging (NO MODIFICATION)
    try {
      let tokenToDecode = data;
      try {
        const jsonResponse = JSON.parse(data);
        if (jsonResponse.jwt) {
          tokenToDecode = jsonResponse.jwt;
        }
      } catch (e) {
        // Not JSON, direct JWT
      }
      
      const decoded = jwt.decode(tokenToDecode, { complete: true });
      if (decoded && decoded.payload?.token) {
        const embeddedDecoded = jwt.decode(decoded.payload.token, { complete: true });
        if (embeddedDecoded && embeddedDecoded.payload?.credentialTypes) {
          console.log('📋 Embedded token credentialTypes:', embeddedDecoded.payload.credentialTypes);
        }
      }
    } catch (decodeError) {
      console.log('Debug decode skipped:', decodeError.message);
    }
    
    // Forward the original response (already enhanced via REQUEST modification)
    res.setHeader('Content-Type', response.headers.get('content-type') || 'application/json');
    res.send(data);

  } catch (error) {
    console.error('Error in /api/sts proxy:', error);
    res.status(500).json({ error: 'Proxy error', details: error.message });
  }
});

// Proxy all other DIM Wallet endpoints
app.use('*', express.json(), async (req, res) => {
  const targetUrl = `${DIM_WALLET_URL}${req.originalUrl}`;
  console.log(`Proxying ${req.method} ${req.originalUrl} -> ${targetUrl}`);

  try {
    const options = {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': req.headers.authorization || ''
      }
    };

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      options.body = JSON.stringify(req.body);
    }

    const response = await fetch(targetUrl, options);
    const contentType = response.headers.get('content-type');
    
    if (contentType && contentType.includes('application/json')) {
      const data = await response.json();
      res.status(response.status).json(data);
    } else {
      const data = await response.text();
      res.status(response.status).send(data);
    }
  } catch (error) {
    console.error(`Error proxying ${req.method} ${req.originalUrl}:`, error);
    res.status(500).json({ error: 'Proxy error', details: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ DIM Wallet Proxy listening on port ${PORT}`);
});
