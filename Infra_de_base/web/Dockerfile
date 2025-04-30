# Dockerfile pour Apache HTTPD
FROM ubuntu:22.04

RUN apt update && \
    apt upgrade -y && \
    apt install -y apache2 curl iputils-ping net-tools && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*


RUN a2enmod ssl rewrite headers
COPY ./apache-config/apache2.conf /etc/apache2/apache2.conf
COPY ./apache-config/security.conf /etc/apache2/conf-available/security.conf

EXPOSE 80 443

VOLUME ["/var/www/html"]

CMD ["apache2ctl", "-D", "FOREGROUND"]