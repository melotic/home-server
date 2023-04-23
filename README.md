# home-server

🚀 Automated deployments to my home server. Complete with good 'ol fashioned rsync.

*Ansible*? Never heard of it.

```
       _,met$$$$$gg.          justin@morpheus
    ,g$$$$$$$$$$$$$$$P.       ---------------
  ,g$$P"     """Y$$.".        OS: Debian GNU/Linux 11 (bullseye) x86_64
 ,$$P'              `$$$.     Kernel: 5.10.0-21-amd64
',$$P       ,ggs.     `$$b:   Uptime: 43 days, 2 hours, 41 mins
`d$$'     ,$P"'   .    $$$    Packages: 775 (dpkg)
 $$P      d$'     ,    $$P    Shell: bash 5.1.4
 $$:      $$.   -    ,d$$'    Terminal: /dev/pts/0
 $$;      Y$b._   _,d$P'      CPU: AMD Ryzen 5 1600 (12) @ 3.200GHz
 Y$$.    `.`"Y$$$$P"'         GPU: NVIDIA GeForce GTX 1070
 `$$b      "-.__              Memory: 3296MiB / 15927MiB
  `Y$$
   `Y$$.
     `$$b.
       `Y$$b.
          `"Y$b._
              `"""
```

## How it works

1. `git push` to this repo
2. GitHub Actions runs the `deploy.yml` workflow
3. Download *secrets* (some of them really aren't secret)
   1. Secrets for the docker-compose variables are stored in Azure Key Vault.
   2. [`secrets/download-secrets-kv.sh`](secrets/download-secrets-kv.sh) downloads the secrets from Azure Key Vault and formats them into a `.env` file. 
4. Verify the `docker-compose.yml` has no missing *secrets* (*i.e.*, all env variables are defined)
   1. [`secrets/check-secrets.sh`](secrets/check-secrets.sh) runs `docker compose config` to check for missing env variables.
5. 🚀 Ship it
   1. VPN with [Tailscale](https://tailscale.com/)
   2. rsync the `docker-compose.yml` and `.env` files to the server, as well as all files in the [`tests`](tests) directory.
   3. ssh in and run  `docker compose up -d --remove-orphans` on the server to start the containers.

### "*E2E*" tests

I configured some netdata alarms to monitor the health of the containers, and some HTTP healthchecks. If any of these fail, the deployment will fail.

We query the netdata API, `http://localhost:19999/api/v1/alarms`, and check for any alarms.

See [`tests/netdata.sh`](tests/netdata.sh) for the implementation.

## Rollbacks

If the deployment fails, the server will be left in a broken state. To fix this, you can either:

1. Manually fix the server
2. Rollback to the previous deployment

So, we rollback. We do this by running `git checkout HEAD^`, and then running the same deployment again.

This leaves the server in a working state, but the repo's `main` branch no longer reflects the state of the server. [It is what it is.](https://www.youtube.com/shorts/KpXsfimrkFo)