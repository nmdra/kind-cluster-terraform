# kind-cluster-terraform

Terraform configuration to provision a **local Kind (Kubernetes in Docker) cluster** for personal development and testing workflows.

This setup optionally enables **Ingress and LoadBalancer support** using **cloud-provider-kind**, which runs as a Docker container alongside the Kind cluster.

> [!NOTE]  
> Starting from **cloud-provider-kind v0.9.0**, Ingress is supported natively. No third-party ingress controllers (such as NGINX) are required by default.


## Features

- Local Kubernetes cluster using **Kind**
- Optional **Ingress + LoadBalancer** support via **cloud-provider-kind**
- cloud-provider-kind runs as a **Docker container**
- Fully controlled using Terraform variables
- Ideal for local development and testing

## How It Works

- By default, the Kind cluster is created **without** Ingress or LoadBalancer support.
- When the `enable_ingress_lb` variable is set to `true`:
  - `cloud-provider-kind` is automatically deployed
  - Kubernetes `Service` resources of type `LoadBalancer` are supported
  - Ingress works out-of-the-box without installing a third-party controller

## Usage

```bash
# Create cluster with ingress & load balancer disabled
terraform apply

# Create cluster with ingress & load balancer enabled
terraform apply -var="enable_ingress_lb=true"
```

👉 **[Test Ingress](./test/README.md)** for example workloads and verification steps.

## Requirements

* Docker
* Terraform
* Kind
* kubectl

## Resources & References

* [Terraform Kind Provider](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
* [What is TFLint?](https://spacelift.io/blog/what-is-tflint)
* [Configuring Kind with Ingress (NGINX example)](https://nickjanetakis.com/blog/configuring-a-kind-cluster-with-nginx-ingress-using-terraform-and-helm)
* [Kind Ingress Documentation](https://kind.sigs.k8s.io/docs/user/ingress)
