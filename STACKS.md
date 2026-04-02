# Stack Recipes

This file gives you copy/paste-ready examples for common project types.

## How this setup works

1. Put each app in its own folder one level above `docker/`.
2. Add a `Dockerfile` in that app folder.
3. Make sure the final container serves HTTP and has an `EXPOSE` line.
4. Run `./docker/install.sh` again.
5. The first detected project gets `abc.com`.
6. Extra detected projects get `<folder>.abc.com`.

Example layout:

```text
/var/www
|-- docker
|-- laravel
|   `-- Dockerfile
|-- react
|   `-- Dockerfile
`-- api
    `-- Dockerfile
```

## Important rule for databases and shared tools

Do not add MySQL, Postgres, Redis, Mailpit, or MinIO to the generated `docker-compose.yml`.

Add them to `docker/docker-compose.template.yml`, because `install.sh` rebuilds the generated file.

## Laravel

Best for a straightforward Laravel app that should answer HTTP directly.

`/var/www/laravel/Dockerfile`

```dockerfile
FROM php:8.3-apache

WORKDIR /var/www/html

RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpq-dev \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql zip \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
    /etc/apache2/sites-available/*.conf \
    /etc/apache2/apache2.conf \
    /etc/apache2/conf-available/*.conf

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY . .

RUN composer install --no-interaction --prefer-dist --optimize-autoloader

EXPOSE 80
CMD ["apache2-foreground"]
```

Useful `.env` values:

```env
APP_URL=http://abc.com
APP_ENV=production
APP_DEBUG=false
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=app
DB_USERNAME=app
DB_PASSWORD=secret
```

Optional shared services to paste into `docker/docker-compose.template.yml` under `services:`

```yaml
  mysql:
    image: mysql:8.4
    container_name: mysql
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: app
      MYSQL_USER: app
      MYSQL_PASSWORD: secret
      MYSQL_ROOT_PASSWORD: root
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - proxy

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    networks:
      - proxy
```

Optional top-level volume block to add near the bottom of `docker/docker-compose.template.yml`

```yaml
volumes:
  mysql-data:
```

After the container is running, common Laravel commands are:

```bash
docker compose -f /var/www/docker-compose.yml exec laravel php artisan key:generate
docker compose -f /var/www/docker-compose.yml exec laravel php artisan migrate
docker compose -f /var/www/docker-compose.yml exec laravel php artisan storage:link
```

## React (Vite or CRA)

Good when you want nginx inside the container to serve the built files.

`/var/www/react/Dockerfile`

```dockerfile
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

If your React app outputs to `build/` instead of `dist/`, use:

```dockerfile
COPY --from=build /app/build /usr/share/nginx/html
```

## Vue (Vite)

This is almost the same as React with Vite.

`/var/www/vue/Dockerfile`

```dockerfile
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Next.js

Use this when you want SSR or Next API routes.

`/var/www/next/Dockerfile`

```dockerfile
FROM node:20-alpine AS deps

WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:20-alpine AS builder

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app ./

EXPOSE 3000
CMD ["npm", "run", "start"]
```

Make sure your app starts on `0.0.0.0` when required by your project setup.

## Node / Express API

Good for APIs or backend services that should be reverse-proxied directly.

`/var/www/api/Dockerfile`

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
EXPOSE 3000
CMD ["npm", "start"]
```

Your app should listen on `0.0.0.0`, not only `localhost`.

Example:

```js
app.listen(3000, "0.0.0.0");
```

## Static HTML site

For plain HTML, CSS, JS, or a prebuilt frontend.

`/var/www/site/Dockerfile`

```dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Django

For Django apps served by Gunicorn.

`/var/www/django/Dockerfile`

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "project.wsgi:application"]
```

Update `project.wsgi:application` to match your Django project name.

## Flask

For simple Python web apps.

`/var/www/flask/Dockerfile`

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0
EXPOSE 5000
CMD ["flask", "run"]
```

## PHP site without Laravel

For a plain PHP app or legacy project.

`/var/www/php-site/Dockerfile`

```dockerfile
FROM php:8.3-apache

WORKDIR /var/www/html
RUN a2enmod rewrite

COPY . .

EXPOSE 80
CMD ["apache2-foreground"]
```

## Mailpit

Useful for Laravel, WordPress, and PHP apps during development.

Paste into `docker/docker-compose.template.yml` under `services:`

```yaml
  mailpit:
    image: axllent/mailpit:latest
    container_name: mailpit
    restart: unless-stopped
    ports:
      - "1025:1025"
      - "8025:8025"
    networks:
      - proxy
```

Laravel mail settings:

```env
MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@abc.com"
MAIL_FROM_NAME="${APP_NAME}"
```

## MinIO

Paste into `docker/docker-compose.template.yml` under `services:`

```yaml
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio-data:/data
    networks:
      - proxy
```

Optional top-level volume block to add near the bottom of `docker/docker-compose.template.yml`

```yaml
volumes:
  minio-data:
```

## Run after adding any stack

```bash
cd /var/www/docker
./install.sh
```

If you only want to rebuild the generated file first:

```bash
./install.sh --generate-only --skip-install
```

## Quick checklist

- every app folder must contain a `Dockerfile`
- the app container must expose the HTTP port with `EXPOSE`
- server processes should listen on `0.0.0.0`
- shared services belong in `docker/docker-compose.template.yml`
- rerun `./install.sh` after each Dockerfile or template change
