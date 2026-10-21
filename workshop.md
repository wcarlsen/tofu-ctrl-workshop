# Tofu controller workshop

## Requirement

* Local Kubernetes cluster distribution like minikube, kind, k3s, etc.
* gh cli
* flux cli
* OpenTofu

## Goals

1. Install tofu-controller
2. Create an AWS IAM role or anything you like using tofu-controller
3. Play around

## Usefull links

* https://fluxcd.io/flux/installation/bootstrap/github/#bootstrap-without-a-github-pat
* https://flux-iac.github.io/tofu-controller/
* https://wcarlsen.github.io/#opentofu-enters-the-gitops-game

## Create local cluster

Create a local Kubernetes cluster in any fashion you like. I use minikube.

```bash
minikube start --wait=all
minikube update-context
```

## Create a public repository in your own GitHub account

Create a public repository and clone it.

```bash
gh repo create <OWNER>/<NAME> --public
```

## Bootstrap fluxcd v2

Bootstrap fluxcd using your private key.

```bash
flux bootstrap git \
  --url=ssh://git@github.com/<OWNER>/<NAME> \
  --branch=main \
  --private-key-file=<PRIVATE_SSH_KEY> \
  --path=/clusters/minikube
```

## Install tofu-controller

Add these manifests to your folder `cluster/minikube/tofu-controller.yaml`.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: tofu-controller
  namespace: flux-system
spec:
  interval: 1h
  url: https://flux-iac.github.io/tofu-controller

---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tofu-controller
  namespace: flux-system
spec:
  interval: 10m
  releaseName: tofu-controller
  targetNamespace: flux-system
  chart:
    spec:
      chart: tofu-controller
      version: ">=0.0.0"
      sourceRef:
        kind: HelmRepository
        name: tofu-controller
        namespace: flux-system
      interval: 1m
```

Verify that it works with `flux get all`.

## Add OpenTofu code and a Terraform resource

Create a folder in the repository root called `infra/` and add a file called `infra/main.tf`. This is where our OpenTofu code will go eventually.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "tofu-ctrl-test"
  assume_role_policy = data.aws_iam_policy_document.this.json
}
```

Then deploy an AWS secret using you local capability credentials (required to already be logged in with `go-aws-sso`).

```bash
aws_creds="$(aws configure export-credentials --format env-no-export)"

printf '%s\n' "$aws_creds" |
  kubectl create secret generic aws-credentials \
    --namespace flux-system  \
    --from-env-file=/dev/stdin \
    --dry-run=client -o yaml | kubectl apply -f -
```

Lastly add this `Terraform` resource to the folder `clusters/minikube/terraform.yaml`.

```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: test
  namespace: flux-system
spec:
  approvePlan: "auto"
  interval: 2m
  destroyResourcesOnDeletion: true
  storeReadablePlan: human
  path: ./infra
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  vars:
  - name: aws_region
    value: "eu-west-1"
  runnerPodTemplate:
    spec:
      envFrom:
        - secretRef:
            name: aws-credentials
```