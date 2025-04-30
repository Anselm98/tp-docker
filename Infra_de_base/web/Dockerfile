# Dockerfile pour Apache HTTPD
FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt upgrade -y && \
    apt install -y apache2 curl iputils-ping net-tools php php-mysql libapache2-mod-php mariadb-client tzdata && \
    ln -fs /usr/share/zoneinfo/Europe/Paris /etc/localtime && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*


RUN a2enmod ssl rewrite headers
COPY ./apache-config/apache2.conf /etc/apache2/apache2.conf
COPY ./apache-config/security.conf /etc/apache2/conf-available/security.conf
COPY ./apache-config/server-name.conf /etc/apache2/conf-available/server-name.conf
RUN a2enconf server-name

RUN rm -f /var/www/html/index.html
COPY db-test.php /var/www/html/index.php

RUN chown -R www-data:www-data /var/www/html/

EXPOSE 80 443

CMD ["apache2ctl", "-D", "FOREGROUND"]