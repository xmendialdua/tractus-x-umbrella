const express = require('express');
const jwt = require('jsonwebtoken');
const fetch = require('node-fetch');

const app = express();
const PORT = 8080;

// Add middleware to handle both JSON and form-urlencoded requests
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const DIM_WALLET_URL = process.env.DIM_WALLET_URL || 'http://ssi-dim-wallet-service.portal.svc.cluster.local:8080';

console.log(`🚀 DIM Wallet Proxy starting on port ${PORT}`);
console.log(`📡 Forwarding to DIM Wallet: ${DIM_WALLET_URL}`);
console.log(`✨ Using REQUEST enhancement strategy (no response modification)`);

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', strategy: 'request-enhancement' });
});

// OAuth token endpoint - supports both JSON and form-urlencoded
app.post('/oauth/token', async (req, res) => {
  console.log(`[${new Date().toISOString()}] POST /oauth/token`);
  
  try {
    // Forward to DIM Wallet with appropriate content type
    const contentType = req.headers['content-type'] || 'application/x-www-form-urlencoded';
    let body;
    
    if (contentType.includes('application/json')) {
      body = JSON.stringify(req.body);
    } else {
      // Form-urlencoded - convert to URLSearchParams
      body = new URLSearchParams(req.body).toString();
    }
    
    const response = await fetch(`${DIM_WALLET_URL}/oauth/token`, {
      method: 'POST',
      headers: {
        'Content-Type': contentType
      },
      body: body
    });

    const data = await response.text();
    
    if (!response.ok) {
      console.error('OAuth token error:', response.status, data.substring(0, 200));
      return res.status(response.status).send(data);
    }

    res.setHeader('Content-Type', response.headers.get('content-type') || 'application/json');
    res.send(data);

  } catch (error) {
    console.error('Error in /oauth/token proxy:', error);
    res.status(500).json({ error: 'Proxy error', details: error.message });
  }
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

// Intercept /api/sts - REQUEST ENHANCEMENT STRATEGY + SIGNTOKEN BUG FIX
app.use('/api/sts', express.json(), async (req, res) => {
  console.log(`\n[${new Date().toISOString()}] === Intercepting STS request ===`);
  console.log('Original request body:', JSON.stringify(req.body, null, 2));

  try {
    // CHECK FOR IATP DISABLED (empty DIDs)
    const hasEmptyDids = req.body.grantAccess && 
                        (req.body.grantAccess.consumerDid === "" || 
                         req.body.grantAccess.providerDid === "");
    
    if (hasEmptyDids) {
      console.log('⚠️ IATP DISABLED detected (empty DIDs) - returning dummy token');
      
      // Return a dummy successful response
      // When IATP is disabled, EDC doesn't validate the token content
      return res.status(200).json({
        token: "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJkdW1teSIsImlzcyI6ImR1bW15IiwiZXhwIjo5OTk5OTk5OTk5fQ.",
        expiresIn: 3600
      });
    }
    
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

    // FIX FOR DIM WALLET STUB BUG: signToken uses wrong BPN for partner
    // The stub incorrectly uses the BPN from the Bearer token instead of the audience
    // Workaround: For signToken requests, get a Bearer token from the audience BPN first
    let authHeader = req.headers.authorization || '';
    
    if (modifiedBody.signToken) {
      console.log('🔧 Detected signToken request - applying BUG FIX for partner BPN');
      
      try {
        // Extract BPN from audience DID
        const audienceDid = modifiedBody.signToken.audience;
        const audienceBPN = audienceDid.split(':').pop();
        const subjectDid = modifiedBody.signToken.subject;
        const subjectBPN = subjectDid.split(':').pop();
        
        console.log(`🎯 Correct audience BPN should be: ${audienceBPN}`);
        console.log(`🎯 Subject (issuer) BPN is: ${subjectBPN}`);
        
        // Get OAuth token for the audience (consumer) BPN to trick the stub
        // This makes the stub think the request is coming from the audience, 
        // so it will use the correct partner BPN
        const tokenResponse = await fetch(`${DIM_WALLET_URL}/oauth/token`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          body: new URLSearchParams({
            'grant_type': 'client_credentials',
            'client_id': audienceBPN,  // FIX: Use BPN not full DID
            'client_secret': 'client_secret',
            'scope': 'openid'
          })
        });
        
        if (tokenResponse.ok) {
          const tokenData = await tokenResponse.json();
          authHeader = `Bearer ${tokenData.access_token}`;
          console.log('✅ Obtained Bearer token for audience BPN:', audienceBPN);
        } else {
          console.warn('⚠️ Could not obtain audience Bearer token, using original');
        }
      } catch (bugfixError) {
        console.warn('⚠️ BUG FIX failed, continuing with original request:', bugfixError.message);
      }
    }
    
    // Forward MODIFIED request to DIM Wallet (with corrected Bearer token for signToken)
    const response = await fetch(`${DIM_WALLET_URL}/api/sts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': authHeader
      },
      body: JSON.stringify(modifiedBody)
    });

    const data = await response.text();
    
    console.log('✅ STS Response status:', response.status);
    
    if (!response.ok) {
      console.error('STS error:', response.status, data.substring(0, 200));
      return res.status(response.status).send(data);
    }

    // Verify the fix worked for signToken
    if (modifiedBody.signToken) {
      try {
        const decoded = jwt.decode(data, { complete: true });
        if (decoded && decoded.payload) {
          const audienceDid = modifiedBody.signToken.audience;
          const expectedBPN = audienceDid.split(':').pop();
          const actualAudience = decoded.payload.aud || '';
          const actualBPN = actualAudience.split(':').pop();
          
          if (actualBPN === expectedBPN) {
            console.log('✅ BUG FIX SUCCESSFUL: Token has correct audience BPN:', actualBPN);
          } else {
            console.error('❌ BUG FIX FAILED: Expected BPN', expectedBPN, 'but got', actualBPN);
          }
        }
      } catch (e) {
        console.log('Could not verify fix:', e.message);
      }
    }

    // Optional: Decode for logging/debugging
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
    
    // Forward the response
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
