FROM nginx:alpine

COPY nginx.conf /etc/nginx/nginx.conf

# Supprime la conf par défaut pour éviter tout conflit
RUN rm /etc/nginx/conf.d/default.conf || true
