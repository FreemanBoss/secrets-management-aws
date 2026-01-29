# Demo Applications Guide

## Secrets Management Demo on EKS

This guide covers the demo applications deployed in the `demo` namespace that showcase all four secrets management approaches.

## 🎯 Demo Applications Overview

| Demo App | Secrets Source | Integration Method | K8s Resources |
|----------|----------------|-------------------|---------------|
| `demo-external-secrets` | AWS Secrets Manager | External Secrets Operator | ExternalSecret → K8s Secret |
| `demo-csi-parameter-store` | AWS Parameter Store | Secrets Store CSI Driver | SecretProviderClass → Files |
| `demo-csi-secrets-manager` | AWS Secrets Manager | Secrets Store CSI Driver | SecretProviderClass → Files |
| `demo-vault-csi` | HashiCorp Vault | Secrets Store CSI Driver | SecretProviderClass → Files |

## 📁 Demo Files

```
kubernetes/demo/
├── 01-service-account.yaml      # IRSA-annotated service accounts
├── 02-external-secrets.yaml     # External Secrets Operator config
├── 03-secrets-store-csi.yaml    # AWS CSI SecretProviderClasses
├── 04-vault-integration.yaml    # Vault CSI SecretProviderClass
├── 05-demo-deployments.yaml     # Demo application deployments
└── setup-demo.sh                # Automated setup script
```

## 🚀 Quick Deploy

```bash
# Run the automated setup
cd kubernetes/demo
chmod +x setup-demo.sh
./setup-demo.sh
```

Or manually:

```bash
# Apply in order
kubectl apply -f 01-service-account.yaml
kubectl apply -f 02-external-secrets.yaml
kubectl apply -f 03-secrets-store-csi.yaml
kubectl apply -f 04-vault-integration.yaml
kubectl apply -f 05-demo-deployments.yaml
```

## ✅ Verification

### Check Pod Status

```bash
kubectl get pods -n demo
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
demo-csi-parameter-store-xxxxx             1/1     Running   0          5m
demo-csi-secrets-manager-xxxxx             1/1     Running   0          5m
demo-external-secrets-xxxxx                1/1     Running   0          5m
demo-vault-csi-xxxxx                       1/1     Running   0          5m
```

### Check Secrets Created

```bash
kubectl get secrets -n demo
```

Expected secrets:
- `api-credentials` - From External Secrets (Secrets Manager)
- `database-credentials` - From External Secrets (Secrets Manager)
- `param-store-secrets` - From CSI Driver (Parameter Store)
- `secrets-manager-csi-secrets` - From CSI Driver (Secrets Manager)
- `vault-csi-secrets` - From Vault CSI

### View Demo Logs

```bash
# External Secrets Operator Demo
kubectl logs -n demo -l app=demo-external-secrets

# CSI Driver - Parameter Store Demo
kubectl logs -n demo -l app=demo-csi-parameter-store

# CSI Driver - Secrets Manager Demo
kubectl logs -n demo -l app=demo-csi-secrets-manager

# Vault CSI Demo
kubectl logs -n demo -l app=demo-vault-csi
```

## 📊 Demo Output Examples

### External Secrets Operator
```
=============================================
Demo: External Secrets Operator
=============================================
Secrets synced from AWS Secrets Manager to K8s Secret

Database Credentials:
  DB_USER: dbadmin
  DB_PASSWORD: [REDACTED - 32 chars]
  DB_HOST: secrets-mgmt-dev-postgres.cj8kqco46f82.us-east-1.rds.amazonaws.com
  DB_PORT: 5432
  DB_NAME: appdb

API Credentials:
  API_KEY: [REDACTED - 32 chars]
  API_SECRET: [REDACTED - 64 chars]

Secrets are refreshed automatically based on refreshInterval
=============================================
```

### CSI Driver (Parameter Store)
```
=============================================
Demo: Secrets Store CSI Driver (Parameter Store)
=============================================
Secrets mounted directly from AWS Parameter Store

Mounted Secret Files in /mnt/secrets-store:
  api-key
  db-connection-string
  db-password

Secret Contents:
  api-key: [REDACTED - 32 chars]
  db-connection-string: postgresql://...
  db-password: [REDACTED - 32 chars]
=============================================
```

### Vault CSI
```
=============================================
Demo: Vault with CSI Driver
=============================================
Secrets mounted from HashiCorp Vault via CSI Driver

Vault secrets directory /mnt/vault-secrets:
  api-key
  db-host
  db-password
  db-username

Secret Contents:
  api-key: [REDACTED - 21 chars]
  db-host: secrets-mgmt-dev-postgres...
  db-password: [REDACTED - 17 chars]
  db-username: dbadmin

Environment Variables (from synced K8s Secret):
  DB_USER: dbadmin
  DB_PASSWORD: [REDACTED]
  API_KEY: [REDACTED]
=============================================
```

## 🔧 Troubleshooting

### External Secrets Not Syncing

1. Check ClusterSecretStore status:
```bash
kubectl get clustersecretstore aws-secrets-manager -o yaml
```

2. Check ExternalSecret status:
```bash
kubectl get externalsecret -n demo
kubectl describe externalsecret database-credentials -n demo
```

3. Verify IRSA configuration:
```bash
kubectl get sa external-secrets -n external-secrets -o yaml | grep annotations -A3
```

### CSI Driver Mount Failures

1. Check SecretProviderClass:
```bash
kubectl get secretproviderclass -n demo
kubectl describe secretproviderclass aws-param-store-secrets -n demo
```

2. Check CSI driver pods:
```bash
kubectl get pods -n secrets-store-csi
kubectl logs -n kube-system -l app=secrets-store-csi-driver-provider-aws
```

3. Check pod events:
```bash
kubectl describe pod <pod-name> -n demo | tail -20
```

### Vault Authentication Failures

1. Verify Vault is unsealed:
```bash
kubectl exec -n vault vault-0 -- vault status
```

2. Check Kubernetes auth role:
```bash
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/demo-app
```

3. Verify service account token mount:
```bash
kubectl get pod -n demo -l app=demo-vault-csi -o yaml | grep -A10 volumes
```

## 🧹 Cleanup

```bash
# Delete demo resources
kubectl delete -f kubernetes/demo/

# Or delete entire namespace
kubectl delete namespace demo
```

## 📚 Related Documentation

- [01-introduction.md](01-introduction.md) - Problem statement
- [02-architecture-patterns.md](02-architecture-patterns.md) - Architecture details
- [03-comparison-matrix.md](03-comparison-matrix.md) - Feature comparison
- [04-security-best-practices.md](04-security-best-practices.md) - Security guide
