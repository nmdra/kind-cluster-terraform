# Test Ingress

### Apply Ingress and Resources

Apply all resources defined in the `kustomize` directory:

```bash
kubectl apply -k kustomize/
```
### Test the Ingress

```bash
# get the Ingress IP
INGRESS_IP=$(kubectl get ingress httpbin -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl  ${INGRESS_IP}/hostname
```