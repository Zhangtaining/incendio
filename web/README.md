# Incendio Web

Static website for Incendio LLC.

## Run Locally

```sh
python3 -m http.server 5173
```

Open `http://localhost:5173`.

## Run on an EC2 Instance

This site can run as a small Nginx container on any EC2 instance with Docker.

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
