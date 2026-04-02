# Docker Setup And Initialization

This folder is designed to live inside a parent project directory such as `/var/www/docker`.

When you run `./install.sh`, the script:

- installs Docker and Docker Compose on supported Linux distributions
- checks the directory one level above the script
- scans each top-level project folder for a `Dockerfile`
- generates the main compose file at the parent level, for example `/var/www/docker-compose.yml`
- starts the stack with `nginxproxy/nginx-proxy`

## Default host behavior

- the first detected Docker project is attached to `abc.com`
- additional detected projects are attached to `<folder-name>.abc.com`
- if no project contains a `Dockerfile`, a default landing page is served on `abc.com`

## Usage

```bash
chmod +x ./install.sh
./install.sh
```

Optional flags:

```bash
./install.sh --domain mysite.com
./install.sh --generate-only
./install.sh --skip-install
```

## Expected layout

```text
/var/www
├── docker
│   ├── install.sh
│   ├── docker-compose.template.yml
│   └── default-site
├── app-one
│   └── Dockerfile
└── app-two
    └── Dockerfile
```

The generated `/var/www/docker-compose.yml` will always contain the proxy plus any buildable
project services discovered in the parent folder.
