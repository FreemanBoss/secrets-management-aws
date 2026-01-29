# Secrets Management for Containers on AWS

> Comparing Parameter Store, Secrets Manager, and HashiCorp Vault for EKS workloads

[![AWS](https://img.shields.io/badge/AWS-EKS-orange)](https://aws.amazon.com/eks/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-purple)](https://www.terraform.io/)
[![Vault](https://img.shields.io/badge/HashiCorp-Vault-black)](https://www.vaultproject.io/)

## Overview

This project provides a production-ready comparison of three secrets management solutions for containerized workloads on Amazon EKS:

| Solution | Integration | Best For |
|----------|-------------|----------|
| **AWS Parameter Store** | CSI Driver | Simple config, cost-sensitive |
| **AWS Secrets Manager** | External Secrets Operator | Auto-rotation, RDS credentials |
| **HashiCorp Vault** | CSI Driver | Dynamic secrets, multi-cloud |

## Project Structure

```
├── terraform/              # Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/           # VPC with public/private subnets
│   │   ├── eks/           # EKS cluster with node groups
│   │   ├── rds/           # PostgreSQL RDS instance
│   │   ├── secrets/       # AWS Secrets Manager & Parameter Store
│   │   └── iam/           # IRSA roles for secrets access
│   └── environments/
├── kubernetes/
│   ├── demo/              # Demo applications (all 3 approaches)
│   ├── helm-values/       # Helm chart configurations
│   └── base/              # Base Kubernetes resources
├── app/                   # Sample Python application
├── scripts/               # Deployment scripts
└── docs/                  # Documentation & article
```

## Quick Start

### Prerequisites

- AWS CLI configured
- kubectl installed
- Helm 3.x installed
- Terraform >= 1.0

### Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### Connect to EKS

```bash
aws eks update-kubeconfig --name secrets-mgmt-dev-eks --region us-east-1
```

### Deploy Demo Applications

```bash
cd kubernetes/demo
kubectl apply -f .
```

### Verify All Approaches

```bash
# External Secrets (AWS Secrets Manager)
kubectl logs -n demo -l app=demo-external-secrets

# CSI Driver (Parameter Store)
kubectl logs -n demo -l app=demo-csi-parameter-store

# CSI Driver (Secrets Manager)
kubectl logs -n demo -l app=demo-csi-secrets-manager

# Vault CSI
kubectl logs -n demo -l app=demo-vault-csi
```

## Comparison

| Feature | Parameter Store | Secrets Manager | Vault |
|---------|----------------|-----------------|-------|
| Cost | Free (standard) | $0.40/secret/mo | Self-hosted |
| Rotation | Manual | Automatic | Dynamic |
| Multi-cloud | ❌ | ❌ | ✅ |
| Audit | CloudTrail | CloudTrail | Built-in |

## Key Features

- 🔐 **Three Secrets Solutions** — Parameter Store, Secrets Manager, and HashiCorp Vault
- 🏗️ **Production-Ready Terraform** — Modular IaC for VPC, EKS, RDS, and IAM
- 🔑 **IRSA Integration** — Secure pod-level AWS authentication
- 📦 **Demo Applications** — Working examples for each integration pattern
- 🛡️ **CSI Driver & ESO** — Multiple Kubernetes integration approaches

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Amazon EKS                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ External Secrets│  │ CSI Driver      │  │ Vault       │ │
│  │ Operator        │  │ (AWS Provider)  │  │ CSI Provider│ │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘ │
└───────────┼─────────────────────┼─────────────────┼────────┘
            │                     │                 │
            ▼                     ▼                 ▼
    ┌───────────────┐     ┌───────────────┐   ┌──────────┐
    │ AWS Secrets   │     │ AWS Parameter │   │ HashiCorp│
    │ Manager       │     │ Store         │   │ Vault    │
    └───────────────┘     └───────────────┘   └──────────┘
```

## License

MIT
