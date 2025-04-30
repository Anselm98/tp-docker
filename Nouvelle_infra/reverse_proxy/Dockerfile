FROM nginx:latest

# Create directory for nginx configuration
RUN mkdir -p /etc/nginx/conf.d

# Copy the custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
