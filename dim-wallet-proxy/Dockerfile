FROM node:18-alpine

WORKDIR /app

# Copiar package files
COPY package*.json ./

# Install dependencies
RUN npm install --only=production

# Copiar código fuente
COPY proxy.js ./

# Exponer puerto
EXPOSE 8080

# Variables de entorno por defecto
ENV PORT=8080
ENV DIM_WALLET_URL=http://ssi-dim-wallet-service.portal.svc.cluster.local:8080

# Usuario no root para seguridad
USER node

CMD ["node", "proxy.js"]
