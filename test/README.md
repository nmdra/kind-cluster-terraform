# Test Ingress

### Apply Ingress and Resources

Apply all resources defined in the `kustomize` directory:

```bash
kubectl apply -k kustomize/
```
### Update `/etc/hosts`

```bash
echo "127.0.0.1 httpbin.local" | sudo tee -a /etc/hosts
```

**Reason:**

* The Ingress routes traffic based on the **Host header** (`httpbin.local`).
* Your local machine DNS doesn’t know this hostname.
* Updating `/etc/hosts` maps `httpbin.local` to `127.0.0.1` (Kind node), allowing your machine to reach the Ingress controller.

> [!NOTE]  
> If you prefer, you can test without updating `/etc/hosts` by manually passing the Host header in curl:
>
> ```bash
> curl -H "Host: httpbin.local" http://127.0.0.1
> ```

### Test the Ingress

With `/etc/hosts` updated:

```bash
curl http://httpbin.local
```

Or explicitly set the Host header:

```bash
curl -H "Host: httpbin.local" http://127.0.0.1
```