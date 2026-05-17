# =============================================================================
# Dockerfile - App Web PHP del Gimnasio
# =============================================================================
# Imagen: PHP 8.2 con Apache integrado
# Extensión: mysqli para conectar con MySQL/RDS
# Puerto: 80 (HTTP interno, Nginx en el bastion lo expone como HTTPS 443)
#
# Uso:
#   docker build -t tfg-gym-app .
#   docker run -d --name gym-app -p 80:80 \
#     -e DB_HOST="<RDS_ENDPOINT>" \
#     -e DB_USER="admin" \
#     -e DB_PASSWORD="<password>" \
#     -e DB_NAME="gym" \
#     -e DB_PORT="3306" \
#     tfg-gym-app
# =============================================================================

FROM php:8.2-apache

# Instalar extensión mysqli (necesaria para conectar con MySQL/RDS)
RUN docker-php-ext-install mysqli

# Copiar los ficheros de la aplicación al directorio raíz de Apache
COPY index.php /var/www/html/index.php
COPY health.php /var/www/html/health.php

# Puerto HTTP (interno, el bastion con Nginx lo expone como HTTPS)
EXPOSE 80
