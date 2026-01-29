# 1. Create the base directory
mkdir -p K8s

# 2. Create Statefull Services (Databases & Queues)
# Using StatefulSet because they need stable storage (PVC) and stable network IDs.
for service in mongodb mysql rabbitmq redis; do
    mkdir -p K8s/$service
    touch K8s/$service/statefulset.yaml
    touch K8s/$service/service.yaml
    touch K8s/$service/secret.yaml  # For passwords
    touch K8s/$service/pvc.yaml     # Persistent Volume Claim
done

# 3. Create Stateless Services (Backend APIs & Frontend)
# Using Deployment because these can scale up/down freely without losing data.
for service in catalogue user cart shipping ratings payment dispatch web; do
    mkdir -p K8s/$service
    touch K8s/$service/deployment.yaml
    touch K8s/$service/service.yaml
    touch K8s/$service/configmap.yaml # For environment variables like URLs
done

# 4. Special handling for services requiring Secrets (DB passwords in env vars)
# Adding secret files to apps that connect to DBs with passwords
touch K8s/shipping/secret.yaml
touch K8s/ratings/secret.yaml

# 5. Special handling for Web (Frontend)
# Often needs an Ingress resource for outside access
touch K8s/web/ingress.yaml

# 6. Global Configs (Optional but good practice)
mkdir -p K8s/common
touch K8s/common/namespace.yaml

echo "✅ Folder structure created successfully in ./K8s"