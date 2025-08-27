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

> [NOTE]  
> If you prefer, you can test without updating `/etc/hosts` by manually passing the Host header in curl:
>
> ```bash
> curl -H "Host: httpbin.local" http://127.0.0.1
> ```

---

### 3️⃣ Test the Ingress

With `/etc/hosts` updated:

```bash
curl http://httpbin.local
```

Or explicitly set the Host header:

```bash
curl -H "Host: httpbin.local" http://127.0.0.1
```

You should see the HTTP response from the `httpbin` pod.

---

✅ **Tip:**

* Make sure the Ingress controller pods are running and ready:

```bash
kubectl get pods -n ingress-nginx
```

* If the response fails, check that the service has active endpoints:

```bash
kubectl get svc httpbin
kubectl get endpoints httpbin
```

---

If you want, I can **rewrite the entire README** to include **Terraform setup + Kustomize + testing instructions** in a clean, step-by-step format that’s ready for GitHub.

Do you want me to do that?