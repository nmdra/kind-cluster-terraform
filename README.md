# kind-cluster-terraform
Terraform configuration to initialize a local Kind cluster for my personal development and testing workflows.

## Usage

```bash
# Run with ingress disabled
terraform apply

# Run with ingress enabled
terraform apply -var="kind_cluster_ingress=true"
```
👉 [Test Ingress](./test/README.md) 

## Resources

- [registry.terraform.io/providers/tehcyx/kind/latest/docs](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
- [spacelift.io/blog/what-is-tflint](https://spacelift.io/blog/what-is-tflint)
- [nickjanetakis.com/blog/configuring-a-kind-cluster-with-nginx-ingress-using-terraform-and-helm](https://nickjanetakis.com/blog/configuring-a-kind-cluster-with-nginx-ingress-using-terraform-and-helm)
- [kind.sigs.k8s.io/docs/user/ingress](https://kind.sigs.k8s.io/docs/user/ingress)