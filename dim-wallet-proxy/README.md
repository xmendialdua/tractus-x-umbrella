# DIM Wallet Proxy

Proxy interceptor para el DIM Wallet Stub que agrega automáticamente las credenciales verificables (VCs) faltantes que requieren las policies de Catena-X.

## Problema que resuelve

El DIM Wallet Stub actual solo devuelve `MembershipCredential`, pero las policies de Catena-X requieren mínimo:
- `FrameworkAgreementCredential`
- `UsagePurposeCredential`

Este proxy intercepta las respuestas del DIM Wallet y agrega automáticamente estos VCs a la Verifiable Presentation (VP).

## Arquitectura

```
EDC Connectors → dim-wallet-proxy:8080 → ssi-dim-wallet-service:8080
                 (agrega VCs faltantes)
```

## Construcción

### Build de la imagen Docker

```bash
cd dim-wallet-proxy
docker build -t dim-wallet-proxy:latest .
```

### Para clusters locales (kind/minikube)

```bash
# Cargar la imagen en el cluster
kind load docker-image dim-wallet-proxy:latest --name <cluster-name>
# O para minikube:
minikube image load dim-wallet-proxy:latest
```

### Para registry remoto

```bash
docker tag dim-wallet-proxy:latest <your-registry>/dim-wallet-proxy:latest
docker push <your-registry>/dim-wallet-proxy:latest
```

## Despliegue

```bash
kubectl apply -f deployment.yaml
```

Verificar:
```bash
kubectl get pods -n portal -l app=dim-wallet-proxy
kubectl logs -n portal -l app=dim-wallet-proxy -f
```

## Actualizar EDC Connectors

Modificar los values de los conectores para usar el proxy:

```yaml
# En values-ikln-connector.yaml y values-mass-connector.yaml

iatp:
  sts:
    dim:
      url: http://dim-wallet-proxy.portal.svc.cluster.local:8080/api/sts
    oauth:
      token_url: http://dim-wallet-proxy.portal.svc.cluster.local:8080/oauth/token

controlplane:
  env:
    TX_IAM_IATP_CREDENTIALSERVICE_URL: http://dim-wallet-proxy.portal.svc.cluster.local:8080/api

dataplane:
  env:
    TX_IAM_IATP_CREDENTIALSERVICE_URL: http://dim-wallet-proxy.portal.svc.cluster.local:8080/api
```

Redesplegar conectores:
```bash
./deploy-ikln-connector.sh
./deploy-mass-connector.sh
```

## Testing

```bash
# Test OAuth token endpoint (pass-through)
curl http://dim-wallet-proxy.portal.svc.cluster.local:8080/oauth/token

# Ver logs del proxy
kubectl logs -n portal -l app=dim-wallet-proxy -f
```

## Notas de desarrollo

⚠️ **Este proxy es solo para desarrollo/testing**. En producción:
- Usar un DIM Wallet real configurado correctamente
- O implementar un servicio de credenciales completo
- Las firmas JWT usan 'dev-secret' (inseguro)

## Troubleshooting

### El proxy no arranca
```bash
kubectl describe pod -n portal -l app=dim-wallet-proxy
```

### No se agregan las credenciales
Revisar logs para ver si la interceptación está funcionando:
```bash
kubectl logs -n portal -l app=dim-wallet-proxy | grep "Intercepting"
```
