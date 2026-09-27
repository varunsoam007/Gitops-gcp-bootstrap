# GCP GitOps Bootstrap

Welcome to the GitOps repository for our GCP Landing Zone. This repository manages the continuous deployment of applications and core services to our GKE clusters using ArgoCD.

## Repository Structure

We follow a modern GitOps structure optimized for GKE and ArgoCD ApplicationSets:

- **`bootstrap/`**: Contains the root ArgoCD `ApplicationSet`. This resource watches the `apps/` directory and dynamically generates ArgoCD `Application` resources for each environment.
- **`apps/`**: Contains the actual application configurations. We use **Kustomize** to wrap and inflate Helm charts or apply raw Kubernetes YAML.
- **`charts/`**: (Optional) For storing local/custom Helm charts if they aren't available in public repositories.

---

## Important Concepts & Architectural Decisions

### 1. External Secrets Operator (ESO) vs. Secrets Store CSI Driver
If you are coming from Azure (AKS), you might be familiar with the **Secrets Store CSI Driver** and the `SecretProviderClass` resource, which mounts Azure Key Vault secrets as files inside Pod volumes.

In our GCP architecture, we use the **External Secrets Operator (ESO)**. 
**Why?**
- **No `SecretProviderClass`:** Instead, we define a **`ClusterSecretStore`** that tells ESO how to authenticate with GCP Secret Manager.
- **Native GKE Workload Identity:** ESO integrates seamlessly with GCP Workload Identity. We bind the Kubernetes Service Account directly to a GCP Service Account, completely avoiding JSON key files.
- **Native Kubernetes Secrets:** Instead of mounting files via CSI, ESO fetches the secret from GCP and creates a standard Kubernetes `Secret` object. Your Pods can simply use `envFrom` to read these secrets as environment variables, which is much more native and cleaner for developers.

### 2. GKE Load Balancing (Application Gateway Equivalent)
- GKE does **not** require you to manually provision an external Load Balancer (like Azure Application Gateway) via Terraform and manually map it to nodes.
- GKE has a built-in **Ingress Controller**. When you deploy a standard Kubernetes `Ingress` resource, GKE automatically provisions a **Google Cloud Application Load Balancer**, provisions TLS, and maps it to your backend Pods dynamically.
- *Terraform's role* was simply to create the **Proxy-only subnet** (required by Envoy LBs) and reserve a **Static Public IP** for our domain (`jksoam.in`).

### 3. ArgoCD Custom Configurations
During the deployment of ArgoCD via `--server-side`, we encountered a few issues which required custom configurations:
- **Kustomize Helm Inflation:** By default, ArgoCD's embedded Kustomize engine blocks Helm rendering (`helmCharts` in `kustomization.yaml`) for security reasons. To fix this, we patched the `argocd-cm` ConfigMap to include `kustomize.buildOptions: "--enable-helm"`.
- **RBAC API Group Errors:** Modern GKE versions introduce several custom API groups (like `autoscaling.x-k8s.io` and `resource.k8s.io`). The default ArgoCD ClusterRole failed to list these, causing applications to get stuck in a "Deleting" or "Unknown" state (ComparisonErrors). To permanently fix this, we created a `ClusterRoleBinding` granting `cluster-admin` to the `argocd-application-controller` service account.

---

## Progress Log

### Phase 1: Infrastructure (Completed in Terraform)
- Created Host Project and Service Project with Shared VPC architecture.
- Deployed a **VPC-Native GKE Cluster** in the Service Project with `Workload Identity` enabled.
- Reserved Static IP and created a Proxy-only subnet for future Load Balancers.
- Set up Cloud DNS Managed Zone for `jksoam.in`.

### Phase 2: GitOps Setup (Current Phase)
- Installed ArgoCD manually into the GKE cluster via Server-Side Apply.
- Created this GitOps repository and added the root `ApplicationSet`.
- Created the **External Secrets** base configuration integrating with Helm and Kustomize.
- Configured the `ClusterSecretStore` to use GKE Workload Identity for GCP Secret Manager.

### Next Steps
- Create Terraform IAM bindings for the `external-secrets` GCP Service Account.
- Add `cert-manager` configuration.
- Sync applications via ArgoCD!
