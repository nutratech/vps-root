# SSL Certificates

## resolving "Split Certificate" Issues

If you add new subdomains (like `element.nutra.tk` or `cinny.nutra.tk`) using `certbot --nginx -d ...`, Certbot might create a second certificate file (e.g., `dev.nutra.tk-0001`) instead of expanding the existing one.

When this happens:
1.  Nginx might continue using the old certificate for the main domain, which doesn't include the new subdomains.
2.  The new subdomains might default to the `default_server` block (often the main Svelte app) because Nginx can't find a valid certificate/SNI match for them in the main config.

### The Fix: Consolidate Certificates

You need to force Certbot to merge all domains into a single certificate file.

**Command:**
```bash
sudo certbot certonly --nginx --cert-name dev.nutra.tk \
  -d dev.nutra.tk \
  -d api.dev.nutra.tk \
  -d api-dev.nutra.tk \
  -d chat.nutra.tk \
  -d git.nutra.tk \
  -d mail.nutra.tk \
  -d matrix.nutra.tk \
  -d www.dev.nutra.tk \
  -d element.nutra.tk \
  -d cinny.nutra.tk \
  --expand
```

**Verify:**
After running the above, reload Nginx:
```bash
sudo systemctl reload nginx
```

Check certificates to ensure everything is under `dev.nutra.tk`:
```bash
sudo certbot certificates
```
