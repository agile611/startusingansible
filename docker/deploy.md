# Genera les claus SSH si no existeixen
mkdir -p ssh
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""

# Elimina xarxes residuals
docker network prune -f

# Construeix i arrenca
docker compose build
docker compose up -d

# Verifica
docker compose ps
ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.20