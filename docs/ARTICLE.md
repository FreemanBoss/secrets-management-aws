# Secrets Management for Containers: Parameter Store vs Secrets Manager vs HashiCorp Vault on AWS

> A hands-on comparison of the three leading secrets management solutions for containerized workloads on Amazon EKS

---

## Introduction

Managing secrets in containerized environments is critical for cloud-native security. When running containers on AWS, you have three primary options:

1. **AWS Systems Manager Parameter Store** — Simple, cost-effective storage
2. **AWS Secrets Manager** — Purpose-built with rotation capabilities  
3. **HashiCorp Vault** — Enterprise-grade with dynamic secrets

This guide implements all three on Amazon EKS and helps you choose the right one.

---

## Prerequisites

- AWS Account with EKS cluster running
- kubectl and Helm 3.x installed
- IAM OIDC provider configured for IRSA

```bash
kubectl get nodes
kubectl create namespace demo
```

> **📸 Screenshot 1:** Terminal showing `kubectl get nodes` output

---

## Quick Comparison

| Feature | Parameter Store | Secrets Manager | HashiCorp Vault |
|---------|----------------|-----------------|-----------------|
| **Cost** | Free (standard) | $0.40/secret/month | Self-hosted |
| **Rotation** | Manual | Automatic | Dynamic secrets |
| **Complexity** | Low | Low | Medium-High |
| **Multi-cloud** | No | No | Yes |

---

## Approach 1: External Secrets Operator (AWS Secrets Manager)

External Secrets Operator syncs AWS Secrets Manager into Kubernetes Secrets.

### Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace
```

> **📸 Screenshot 2:** External Secrets Operator pods running (`kubectl get pods -n external-secrets`)

### Create Secrets in AWS

```bash
aws secretsmanager create-secret --name "myapp/database/credentials" \
  --secret-string '{"username":"dbadmin","password":"secure-pass","host":"db.example.com"}'
```

> **📸 Screenshot 3:** AWS Console - Secrets Manager showing created secrets

### Configure ClusterSecretStore

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: demo
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: database-credentials
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: myapp/database/credentials
        property: password
```

> **📸 Screenshot 4:** ExternalSecret status showing "SecretSynced" (`kubectl get externalsecrets -n demo`)

### Verification

```bash
kubectl get externalsecrets -n demo
kubectl get secrets -n demo
```

> **📸 Screenshot 5:** Demo pod logs showing secrets accessible (`kubectl logs -n demo -l app=demo-external-secrets`)

---

## Approach 2: Secrets Store CSI Driver (Parameter Store & Secrets Manager)

CSI Driver mounts secrets directly as files—no intermediate Kubernetes Secrets.

### Install CSI Driver

```bash
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace secrets-store-csi --create-namespace

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

> **📸 Screenshot 6:** CSI Driver pods running (`kubectl get pods -n secrets-store-csi`)

### Create SecretProviderClass (Parameter Store)

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-param-store-secrets
  namespace: demo
spec:
  provider: aws
  parameters:
    region: us-east-1
    objects: |
      - objectName: "/myapp/database/password"
        objectType: "ssmparameter"
      - objectName: "/myapp/api/key"
        objectType: "ssmparameter"
```

> **📸 Screenshot 7:** AWS Console - Parameter Store showing parameters

### Create SecretProviderClass (Secrets Manager)

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets-manager-secrets
  namespace: demo
spec:
  provider: aws
  parameters:
    region: us-east-1
    objects: |
      - objectName: "myapp/database/credentials"
        objectType: "secretsmanager"
        jmesPath:
          - path: "username"
            objectAlias: "db-username"
          - path: "password"
            objectAlias: "db-password"
```

> **📸 Screenshot 8:** SecretProviderClasses created (`kubectl get secretproviderclass -n demo`)

### Deploy Application with CSI Volume

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-csi
  namespace: demo
spec:
  template:
    spec:
      containers:
        - name: app
          volumeMounts:
            - name: secrets
              mountPath: "/mnt/secrets"
              readOnly: true
      volumes:
        - name: secrets
          csi:
            driver: secrets-store.csi.k8s.io
            volumeAttributes:
              secretProviderClass: aws-param-store-secrets
```

> **📸 Screenshot 9:** Pod logs showing mounted secrets (`kubectl logs -n demo -l app=demo-csi-parameter-store`)

---

## Approach 3: HashiCorp Vault with CSI Driver

Vault provides dynamic secrets, comprehensive auditing, and multi-cloud support.

### Install Vault

```bash
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --set "server.standalone.enabled=true" \
  --set "csi.enabled=true"
```

> **📸 Screenshot 10:** Vault pods running (`kubectl get pods -n vault`)

### Initialize and Unseal

```bash
kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>
kubectl exec -n vault vault-0 -- vault status
```

> **📸 Screenshot 11:** Vault status showing "Sealed: false"

### Configure Vault Secrets

```bash
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

kubectl exec -n vault vault-0 -- vault kv put secret/database/credentials \
  username="dbadmin" password="vault-managed-password" host="db.example.com"
```

> **📸 Screenshot 12:** Vault secrets list (`kubectl exec -n vault vault-0 -- vault kv list secret/`)

### Configure Kubernetes Auth

```bash
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/demo-app \
  bound_service_account_names=vault-app \
  bound_service_account_namespaces=demo \
  policies=demo-app ttl=1h
```

### Create Vault SecretProviderClass

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-secrets-csi
  namespace: demo
spec:
  provider: vault
  parameters:
    vaultAddress: "http://vault.vault:8200"
    roleName: "demo-app"
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/database/credentials"
        secretKey: "password"
```

> **📸 Screenshot 13:** Pod logs showing Vault secrets (`kubectl logs -n demo -l app=demo-vault-csi`)

---

## All Demos Running

> **📸 Screenshot 14:** All demo pods running side-by-side (`kubectl get pods -n demo`)

> **📸 Screenshot 15:** All secrets created (`kubectl get secrets -n demo`)

---

## Comparison: When to Use Each

### Choose Parameter Store when:
- ✅ Simple key-value configuration needed
- ✅ Cost is a primary concern
- ✅ No automatic rotation required

### Choose Secrets Manager when:
- ✅ Automatic secret rotation needed
- ✅ Native RDS credential management
- ✅ Prefer fully managed AWS service

### Choose HashiCorp Vault when:
- ✅ Dynamic secrets required (short-lived credentials)
- ✅ Multi-cloud or hybrid environment
- ✅ Comprehensive audit logging needed
- ✅ Advanced features like PKI required

---

## Best Practices

1. **Use IRSA** — Never use static AWS credentials in pods
2. **Least Privilege** — Grant minimum permissions required
3. **Enable Auditing** — CloudTrail for AWS, audit device for Vault
4. **Rotate Regularly** — Use automatic rotation when available
5. **Never Log Secrets** — Configure apps to redact sensitive data

---

## Conclusion

| Scenario | Recommendation |
|----------|----------------|
| **Startups/Small Teams** | AWS Secrets Manager + External Secrets |
| **Enterprise/Compliance** | HashiCorp Vault |
| **Cost-Sensitive** | Parameter Store for config, Secrets Manager for secrets |
| **Multi-Cloud** | HashiCorp Vault |

Any of these solutions is infinitely better than hardcoded secrets. Choose based on your complexity tolerance and requirements.

---

## Screenshot Checklist

| # | Description | Command/Location |
|---|-------------|------------------|
| 1 | EKS nodes | `kubectl get nodes` |
| 2 | External Secrets pods | `kubectl get pods -n external-secrets` |
| 3 | AWS Secrets Manager console | AWS Console |
| 4 | ExternalSecret synced | `kubectl get externalsecrets -n demo` |
| 5 | External Secrets demo logs | `kubectl logs -n demo -l app=demo-external-secrets` |
| 6 | CSI Driver pods | `kubectl get pods -n secrets-store-csi` |
| 7 | AWS Parameter Store console | AWS Console |
| 8 | SecretProviderClasses | `kubectl get secretproviderclass -n demo` |
| 9 | CSI demo logs | `kubectl logs -n demo -l app=demo-csi-parameter-store` |
| 10 | Vault pods | `kubectl get pods -n vault` |
| 11 | Vault status unsealed | `kubectl exec -n vault vault-0 -- vault status` |
| 12 | Vault secrets list | `kubectl exec -n vault vault-0 -- vault kv list secret/` |
| 13 | Vault demo logs | `kubectl logs -n demo -l app=demo-vault-csi` |
| 14 | All demo pods | `kubectl get pods -n demo` |
| 15 | All secrets | `kubectl get secrets -n demo` |

---

*Connect with me on [LinkedIn/Twitter]*
