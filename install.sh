#!/bin/bash

set -e  # Stop script on any error

echo "==============================="
echo "  DMOJ Online Judge Installer  "
echo "==============================="
echo ""

# --- Define paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMOJ_DIR="$SCRIPT_DIR/dmoj"

# --- Load config ---
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.env not found."
  echo "Please create it based on config.env.example and fill in your values:"
  echo "  cp config.env.example config.env"
  exit 1
fi

source "$CONFIG_FILE"

# --- Validate required variables ---
for VAR in HOST DB_PASS JUDGE_NAME JUDGE_KEY JUDGE_TIER JUDGE_CONCURRENCY ADMIN_USER ADMIN_PASS ADMIN_EMAIL; do
  if [ -z "${!VAR}" ]; then
    echo "ERROR: $VAR is not set in config.env"
    exit 1
  fi
done

# --- Validate JUDGE_TIER value ---
if [[ "$JUDGE_TIER" != "1" && "$JUDGE_TIER" != "2" && "$JUDGE_TIER" != "3" ]]; then
  echo "ERROR: JUDGE_TIER must be 1, 2 or 3"
  exit 1
fi

# --- Check if already installed ---
if [ -d "$DMOJ_DIR" ]; then
  echo "ERROR: $DMOJ_DIR directory already exists."
  echo "If you want to reinstall, run uninstall.sh"
  exit 1
fi

# --- Check and install Python 3 ---
if ! command -v python3 &> /dev/null; then
  echo "Python 3 not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y python3
  echo "Python 3 installed successfully."
fi

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")

echo "Using:"
echo "  HOST        = $HOST"
echo "  JUDGE_NAME  = $JUDGE_NAME"
echo "  JUDGE_TIER  = $JUDGE_TIER"
echo "  INSTALL_DIR = $DMOJ_DIR"
echo ""

# --- Check and install Docker ---
echo "[0/7] Checking Docker..."

if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker $USER
  echo "Docker installed successfully."
  echo "IMPORTANT: To use Docker without sudo, you need to restart your session."
  echo "  - On WSL: run 'wsl --shutdown' in PowerShell, then reopen WSL."
  echo "  - On Ubuntu: run 'newgrp docker' or log out and back in."
  echo "Then run install.sh again."
  exit 0
else
  echo "Docker is already installed."
fi

# --- Clone repositories ---
echo "[1/7] Cloning repositories..."
mkdir -p "$DMOJ_DIR"
cd "$DMOJ_DIR"

git clone https://github.com/Ninjaclasher/dmoj-docker dmoj-docker
cd dmoj-docker
git submodule update --init --recursive
cd "$DMOJ_DIR"

git clone --recursive https://github.com/DMOJ/judge-server.git judge-server

cd "$DMOJ_DIR/dmoj-docker/dmoj"

echo "[2/7] Initializing configs..."
./scripts/initialize

# --- Removing mathoid ---
echo "[2.5/7] Removing mathoid..."
sed -i '/^  mathoid:/,/^  [a-z]/ { /^  [a-z]/!d; /^  mathoid:/d }' docker-compose.yml
sed -i '/- mathoid/d' docker-compose.yml

# --- Removing 'version' from docker-compose ---
sed -i '/^version:/d' docker-compose.yml

# --- Configure environment ---
echo "[3/7] Setting up environment variables..."

cat > environment/mysql.env <<EOF
MYSQL_DATABASE=dmoj
MYSQL_USER=dmoj
MYSQL_PASSWORD=$DB_PASS
MYSQL_ROOT_PASSWORD=${DB_PASS}_root
EOF

cat > environment/mysql-admin.env <<EOF
MYSQL_ROOT_PASSWORD=${DB_PASS}_root
EOF

cat > environment/site.env <<EOF
HOST=$HOST
DEBUG=0
SECRET_KEY=$SECRET_KEY
EOF

# --- Configure nginx ---
sed -i "s/server_name .*/server_name $HOST;/" nginx/conf.d/nginx.conf

# --- Build images ---
echo "[4/7] Building Docker images (this may take a few minutes)..."
docker compose build --parallel

# --- First run ---
echo "[5/7] Starting database and site..."
docker compose up -d site
echo "Waiting for database to start..."
sleep 15

# --- Migrations and fixtures ---
echo "[6/7] Running migrations and loading fixtures..."
./scripts/migrate
./scripts/copy_static
./scripts/manage.py loaddata navbar
./scripts/manage.py loaddata language_small
./scripts/manage.py loaddata demo

# --- Automate DB Setup (Admin + Profile + Judge) ---
echo "Automating superuser, profile, and judge registration..."
cat <<EOF | docker compose exec -T site python3 manage.py shell
from django.contrib.auth.models import User
from judge.models import Profile, Judge

# 1. Create superuser
user, created = User.objects.get_or_create(
    username='$ADMIN_USER', 
    defaults={'email': '$ADMIN_EMAIL'}
)
user.set_password('$ADMIN_PASS')
user.is_superuser = True
user.is_staff = True
user.save()

# 2. Fix 500 error by creating a Profile
Profile.objects.get_or_create(user=user)

# 3. Register judge in the DB
Judge.objects.update_or_create(
    name='$JUDGE_NAME',
    defaults={'auth_key': '$JUDGE_KEY', 'is_blocked': False}
)
EOF

# --- Judge ---
echo "[7/7] Setting up judge-server (tier${JUDGE_TIER})..."

# Create judge.yml
cat > problems/judge.yml <<EOF
id: $JUDGE_NAME
key: $JUDGE_KEY

problem_storage_root: /problems
EOF

# Build judge image
cd "$DMOJ_DIR/judge-server/.docker"
make judge-tier${JUDGE_TIER}
cd "$DMOJ_DIR/dmoj-docker/dmoj"

# Start all containers
docker compose up -d

# Wait for bridged to start and get its IP
echo "Waiting for bridged to start..."
sleep 10
BRIDGED_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' $(docker ps -qf "name=bridged") | grep -v '^$' | head -1)

# Start judge container with concurrency limits
docker run \
  --name judge \
  --network dmoj_db \
  -v "$DMOJ_DIR/dmoj-docker/dmoj/problems:/problems" \
  --cap-add=SYS_PTRACE \
  -d \
  --restart=always \
  dmoj/judge-tier${JUDGE_TIER}:latest \
  run -c "$JUDGE_CONCURRENCY" -p9999 -c /problems/judge.yml \
  $BRIDGED_IP $JUDGE_NAME $JUDGE_KEY

echo ""
echo "==============================="
echo "  Installation complete!       "
echo "==============================="
echo ""
echo "Site is available at: http://$HOST"
echo "Admin panel is at:    http://$HOST/admin"
echo ""
echo "You can now log in using the ADMIN_USER and ADMIN_PASS"
echo "defined in your config.env file."
echo "Your judge has been automatically connected!"
echo ""