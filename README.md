# Docker Setup And Initialization

This folder is designed to live inside a parent project directory such as `/var/www/docker`.

When you run `./install.sh`, the script:

- installs Docker and Docker Compose on supported Linux distributions
- checks the directory one level above the script
- scans each top-level project folder for a `Dockerfile`
- generates the main compose file at the parent level, for example `/var/www/docker-compose.yml`
- starts the stack with `nginxproxy/nginx-proxy`

## Default host behavior

- the script asks you for a domain when it detects a project
- the first detected project usually becomes your main domain
- additional detected projects get a suggested default like `<folder-name>.<main-domain>`
- if no project contains a `Dockerfile`, the script asks for the landing page domain

## Usage

```bash
chmod +x ./install.sh
./install.sh
```

During an interactive run, the script will prompt you for the domain for each detected project.

Optional flags:

```bash
./install.sh --domain mysite.com
./install.sh --generate-only
./install.sh --skip-install
```

## Important editing rule

Do not manually edit the generated `/var/www/docker-compose.yml`.

That file is rebuilt every time `./install.sh` runs.

If you need to add shared services such as MySQL, Postgres, Redis, Mailpit, or MinIO, add them to:

```text
/var/www/docker/docker-compose.template.yml
```

If you need to add or update an app, put a `Dockerfile` inside that app folder and rerun the script.

## Expected layout

```text
/var/www
|-- docker
|   |-- install.sh
|   |-- docker-compose.template.yml
|   |-- default-site
|   `-- STACKS.md
|-- app-one
|   `-- Dockerfile
`-- app-two
    `-- Dockerfile
```

The generated `/var/www/docker-compose.yml` will always contain the proxy plus any buildable
project services discovered in the parent folder.

## Stack recipes

Copy/paste examples for Laravel, React, Vue, Next.js, Node, Python, static sites, and shared
services are in [STACKS.md](./STACKS.md).
