# Incendio Web

Static website for Incendio LLC.

## Run Locally

```sh
python3 -m http.server 5173
```

Open `http://localhost:5173`.

## Run on an EC2 Instance

This site can run as a small Nginx container on any EC2 instance with Docker.

For the current EC2/Nginx setup, the repository includes a one-command deploy
script that uploads the static files, installs Nginx if needed, configures the
site as the default HTTP server, and reloads Nginx:

```sh
../scripts/deploy_ec2_web.sh ec2-18-222-31-20.us-east-2.compute.amazonaws.com /path/to/key.pem
```

You can reuse the same command for a new EC2 instance by replacing the hostname
and SSH key path.

If the instance already has a Let's Encrypt certificate for `incendiollc.com`,
the deploy script preserves HTTPS and redirects HTTP traffic to HTTPS.

## Run on EC2 with Docker

1. Install Docker and Compose on the instance.
2. Copy or clone this `web` directory onto the instance.
3. From this directory, start the site:

```sh
docker compose up -d --build
```

The site will be available on port `80`. Make sure the EC2 security group allows inbound HTTP traffic on port `80`.

To update after changing files:

```sh
docker compose up -d --build
```

To stop the site:

```sh
docker compose down
```
