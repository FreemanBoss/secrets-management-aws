# Secrets Management for Containers on AWS

Comparing Parameter Store, Secrets Manager, and HashiCorp Vault for EKS workloads.

## Solutions

| Solution | Integration | Best For |
|----------|-------------|----------|
| AWS Parameter Store | CSI Driver | Simple config, cost-sensitive |
| AWS Secrets Manager | External Secrets Operator | Auto-rotation, RDS credentials |
| HashiCorp Vault | CSI Provider | Dynamic secrets, multi-cloud |

## Structure

```
terraform/           # VPC, EKS, RDS, IAM (modular)
kubernetes/
  demo/              # Demo apps for all 3 approaches
  helm-values/       # Helm configurations
app/                 # Sample Python application
scripts/             # Deployment automation
```

## Quick Start

```bash
# Deploy infrastructure
cd terraform && terraform init && terraform apply

# Connect to EKS
aws eks update-kubeconfig --name secrets-mgmt-dev-eks --region us-east-1

# Deploy demos
cd kubernetes/demo && ./setup-demo.sh
```

## Verify

```bash
kubectl logs -n demo -l app=demo-external-secrets
kubectl logs -n demo -l app=demo-csi-parameter-store
kubectl logs -n demo -l app=demo-vault-csi
```

## Comparison

| Feature | Parameter Store | Secrets Manager | Vault |
|---------|----------------|-----------------|-------|
| Cost | Free tier | $0.40/secret/mo | Self-hosted |
| Rotation | Manual | Automatic | Dynamic |
| Multi-cloud | No | No | Yes |

## License

MIT
