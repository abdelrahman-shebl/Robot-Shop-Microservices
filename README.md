# Robot Shop - Microservices Application

A simple microservices-based e-commerce application demonstrating Docker Compose networking and service architecture.

---

## 🏗️ Architecture

### Services Overview

![Robot Shop Architecture](images/Robot%20Shop%20Architecture.png)

### Network Layers

**Frontend Layer (Public Access)**
- web: Nginx reverse proxy, exposed on port 8080

**API Services Layer (Internal)**
- catalogue: Node.js service, retrieves product information from MongoDB
- user: Node.js service, manages users and sessions with MongoDB and Redis
- cart: Node.js service, shopping cart with Redis backend
- shipping: Java/Spring Boot service, calculates shipping with MySQL
- payment: Python/Flask service, processes payments via RabbitMQ
- ratings: PHP service, manages product ratings with MySQL

**Data Services Layer (Internal, No Public Access)**
- mongodb: Stores catalogue and user data
- mysql: Stores shipping and ratings data
- redis: Caches cart and session data

**Message Queue Layer (Internal)**
- rabbitmq: Message broker for async processing
- dispatch: Go service, consumes messages and processes orders

---

## 📡 Service Communication

### Network Layers & Service Assignments

**FRONTEND NETWORK** (Public Access)
- web: Nginx gateway, listens on localhost:8080
  - Talks to: catalogue, user, cart, shipping, payment, ratings
  - Connected to: frontend, api-services

**API SERVICES NETWORK** (Internal)
- catalogue (Node.js): Product catalog service
  - Talks to: mongodb
  - Connected to: api-services, data-services
  
- user (Node.js): User management service
  - Talks to: mongodb, redis
  - Connected to: api-services, data-services
  
- cart (Node.js): Shopping cart service
  - Talks to: redis, catalogue
  - Connected to: api-services, data-services
  
- shipping (Java/Spring Boot): Shipping calculation service
  - Talks to: mysql, cart
  - Connected to: api-services, data-services
  
- payment (Python/Flask): Payment processing service
  - Talks to: rabbitmq, cart, user
  - Connected to: api-services, message-queue
  
- ratings (PHP): Product ratings service
  - Talks to: mysql
  - Connected to: api-services, data-services

**DATA SERVICES NETWORK** (Internal, No Public Access)
- mongodb: Document database
  - Stores: catalogue data, user data
  - Connected to: data-services
  - Accessed by: catalogue, user
  
- mysql: Relational database
  - Stores: shipping data, ratings data
  - Connected to: data-services
  - Accessed by: shipping, ratings
  
- redis: In-memory cache
  - Stores: cart sessions, user cache
  - Connected to: data-services
  - Accessed by: user, cart

**MESSAGE QUEUE NETWORK** (Internal, Async Processing)
- rabbitmq: Message broker
  - Broker for: payment messages
  - Connected to: message-queue
  - Used by: payment (publisher), dispatch (consumer)
  
- dispatch (Go): Order processing worker
  - Listens to: rabbitmq messages
  - Processes: Orders asynchronously
  - Connected to: message-queue

### Communication Flow Summary

| Source | Destination | Network Path | Protocol |
|--------|-------------|--------------|----------|
| web | catalogue | frontend→api-services→data-services | HTTP |
| web | user | frontend→api-services→data-services | HTTP |
| web | cart | frontend→api-services→data-services | HTTP |
| web | shipping | frontend→api-services→data-services | HTTP |
| web | payment | frontend→api-services→message-queue | HTTP |
| web | ratings | frontend→api-services→data-services | HTTP |
| catalogue | mongodb | api-services→data-services | MongoDB driver |
| user | mongodb | api-services→data-services | MongoDB driver |
| user | redis | api-services→data-services | Redis protocol |
| cart | redis | api-services→data-services | Redis protocol |
| cart | catalogue | api-services | HTTP |
| shipping | mysql | api-services→data-services | JDBC |
| shipping | cart | api-services | HTTP |
| ratings | mysql | api-services→data-services | PDO |
| payment | rabbitmq | api-services→message-queue | AMQP |
| payment | cart | api-services | HTTP |
| payment | user | api-services | HTTP |
| dispatch | rabbitmq | message-queue | AMQP |

---

## 🔧 Required Environment Variables

Create a `.env` file with these **required** variables:

```bash
# Docker Images [REQUIRED]
REPO=robotshop
TAG=latest

# MongoDB Credentials [REQUIRED]
MONGO_ROOT_USER=admin
MONGO_ROOT_PASSWORD=secure_password_here

# MongoDB Connection Strings [REQUIRED]
MONGO_CONNECTION_STRING=mongodb://admin:secure_password_here@mongodb:27017/catalogue
MONGO_CONNECTION_STRING_USER=mongodb://admin:secure_password_here@mongodb:27017/users

# MySQL Credentials [REQUIRED]
MYSQL_USER=shipping
MYSQL_PASSWORD=secure_password_here

# MySQL Connection String [REQUIRED]
MYSQL_CONNECTION_STRING=jdbc:mysql://mysql:3306/cities?useSSL=false

# Instana Monitoring [OPTIONAL]
INSTANA_AGENT_KEY=
```

**Copy example file:**
```bash
cp .env.example .env
# Edit .env with your credentials
```

---

## 🚀 Quick Start

### 1. Setup Environment
```bash
# Copy and edit environment file
cp .env.example .env
nano .env  # Change passwords!
```

### 2. Start Services
```bash
# Build and start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f web
```

### 3. Access Application
```bash
# Open in browser
http://localhost:8080
```

### 4. Stop Services
```bash
# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

---

## 🔐 Security Notes

**⚠️ Important:**
1. **Change default passwords** in `.env` file
2. **Never commit** `.env` file to git (already in `.gitignore`)
3. **Use strong passwords** (16+ characters) for production
4. **Databases are not exposed** to host (internal network only)
5. **Only web service (port 8080)** is publicly accessible

---

## 🌐 Network Segmentation

### 4-Tier Network Architecture

| Network | Purpose | Services |
|---------|---------|----------|
| **frontend** | Public web access | web |
| **api-services** | Backend APIs | web, catalogue, user, cart, shipping, payment, ratings |
| **data-services** | Databases | mongodb, redis, mysql + API services |
| **message-queue** | Async messaging | rabbitmq, payment, dispatch |

**Benefits:**
- ✅ Databases isolated from public access
- ✅ Services only talk to required dependencies
- ✅ Message queue separated from data layer
- ✅ Frontend gateway controls all public access

---

## 📊 Service Ports (Internal)

| Service | Internal Port | Public Port | Technology |
|---------|--------------|-------------|------------|
| web | 8080 | 8080 | Nginx |
| catalogue | 8080 | - | Node.js |
| user | 8080 | - | Node.js |
| cart | 8080 | - | Node.js |
| shipping | 8080 | - | Java/Spring Boot |
| payment | 8080 | - | Python/Flask |
| ratings | 80 | - | PHP |
| dispatch | - | - | Go |
| mongodb | 27017 | - | MongoDB |
| mysql | 3306 | - | MySQL |
| redis | 6379 | - | Redis |
| rabbitmq | 5672 | - | RabbitMQ |

**Note:** Only `web` service exposes a public port. All other services communicate via internal Docker networks.

---

## 🔍 Troubleshooting

### Check Service Health
```bash
# All services
docker-compose ps

# Specific service logs
docker-compose logs <service-name>

# Follow logs
docker-compose logs -f catalogue user
```

### Test Database Connections
```bash
# MongoDB
docker-compose exec mongodb mongosh -u admin -p admin

# MySQL
docker-compose exec mysql mysql -u shipping -p

# Redis
docker-compose exec redis redis-cli ping
```

### Restart Services
```bash
# Restart specific service
docker-compose restart catalogue

# Rebuild and restart
docker-compose up -d --build catalogue
```

---

## 📝 Project Structure

```
robot-shop/
├── docker-compose.yaml       # Service orchestration
├── .env.example              # Environment template
├── .env                      # Your credentials (git ignored)
├── cart/                     # Cart service (Node.js)
├── catalogue/                # Catalogue service (Node.js)
├── dispatch/                 # Dispatch service (Go)
├── mongo/                    # MongoDB initialization
├── mysql/                    # MySQL initialization
├── payment/                  # Payment service (Python)
├── ratings/                  # Ratings service (PHP)
├── shipping/                 # Shipping service (Java)
├── user/                     # User service (Node.js)
└── web/                      # Frontend gateway (Nginx)
```

---

## 🐳 Docker Commands Reference

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View running services
docker-compose ps

# View logs
docker-compose logs -f

# Rebuild service
docker-compose build <service>

# Scale service
docker-compose up -d --scale cart=3

# Execute command in service
docker-compose exec <service> <command>

# Clean everything
docker-compose down -v --rmi all
```

---

## 📚 Additional Information

- **Health Checks:** All services have configured health checks
- **Volumes:** Persistent data for MongoDB and MySQL
- **Networking:** Automatic service discovery via Docker DNS
- **Monitoring:** Optional Instana integration (set `INSTANA_AGENT_KEY`)

---

## 📄 License

See [LICENSE](LICENSE) file for details.
