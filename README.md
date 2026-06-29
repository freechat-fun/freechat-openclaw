# Scripts for OpenClaw (Kustomize deployment)

Deployment wrapper for [OpenClaw](https://github.com/openclaw/openclaw) on Kubernetes, using the
official [Kustomize manifests](https://docs.openclaw.ai/install/kubernetes) (the deprecated
`serhanekicii/openclaw-helm` chart is no longer used).

## Layout

```
configs/k8s/
├── base/                       # vendored official manifests (tracked; pvc.yaml excluded locally)
├── overlay/                    # private overlay (tracked)
│   ├── kustomization.yaml
│   ├── ingress.yaml            # public /voice ingress + TLS
│   ├── deployment-patch.yaml   # image, chromium sidecar, voice port, envFrom, claimName, init
│   ├── service-patch.yaml      # voice:3334 port
│   ├── pvc.yaml                # standalone PVC `freechat-openclaw` (applied by install.sh if missing)
│   └── openclaw-config-cm.yaml # TRACKED ConfigMap patch placeholder (`openclaw.json: "{}"`; non-sensitive)
├── openclaw.json               # REAL runtime config, plain JSON (gitignored)
├── deploy.env                  # non-secret params + image tags (gitignored)
├── secrets.env                 # KEY=value secrets (gitignored)
└── kube-private.conf           # kubeconfig (gitignored)
scripts/                        # install/upgrade/render/uninstall/restart + pod helpers + sync-base
```

The overlay adds (on top of the official base): a chromium sidecar for browser automation, the
voice port 3334 + `/voice` ingress, `envFrom` the `openclaw-secrets` Secret, and reuses the existing
data PVC `freechat-openclaw` (claimName patched in `deployment-patch.yaml`). The privileged
`init-permissions` container was dropped in favor of `fsGroup: 1000` per official hardening. Gateway
and chromium image tags come from `deploy.env` (`OPENCLAW_IMAGE` / `CHROMIUM_IMAGE`) via a Kustomize
`images:` transformer, so version bumps don't touch tracked manifests.

### Data preservation

The Deployment mounts the existing PVC **`freechat-openclaw`** (the legacy Helm release's data PVC,
which carries `helm.sh/resource-policy: keep` and survives `helm uninstall`). `scripts/install.sh`
creates that PVC only if it is missing (from `configs/k8s/overlay/pvc.yaml`); on a migrated install
the existing PVC — with all `~/.openclaw` data — is reused untouched. The `init-config` container
overwrites `openclaw.json` from the ConfigMap each start (matching the legacy `CONFIG_MODE=overwrite`);
runtime state (paired devices, sessions) lives in SQLite on the PVC and is never touched.

## Setup

1. Place the kubeconfig at `configs/k8s/kube-private.conf`.
2. Fill `configs/k8s/deploy.env` (namespace, ingress host, cert-manager version, **Let's Encrypt email**).
3. Fill `configs/k8s/secrets.env` with `KEY=value` lines for every runtime env var
   (`OPENCLAW_GATEWAY_TOKEN`, provider API keys, Telegram/Twilio tokens, phone numbers, etc.).
   These are loaded into `Secret/openclaw-secrets` and consumed via `envFrom`.
4. Put the real `openclaw.json` at `configs/k8s/openclaw.json` (plain JSON; `${ENV}`
   substitution from the Secret is supported). The tracked
   `configs/k8s/overlay/openclaw-config-cm.yaml` is a non-sensitive placeholder
   (`openclaw.json: "{}"`); the scripts inject the real config as a temp patch on top
   of it at install/upgrade/render time (see `merge_openclaw_config` in
   `scripts/setenv.sh`), so the placeholder stays clean and visible to git. Edit
   `openclaw.json`, never the placeholder content (keep it `"{}"`).

All four files are gitignored — they never leave your machine.

## Cluster prerequisites (optional, for the public /voice ingress)

```bash
scripts/install-in.sh   # ingress-nginx (namespace ingress-default)
scripts/install-cm.sh   # cert-manager + Let's Encrypt ClusterIssuer (needs LETSENCRYPT_EMAIL)
```

## Lifecycle

```bash
scripts/install.sh     # apply Secret + overlay, rollout
scripts/upgrade.sh     # re-apply after editing manifests/secrets, rollout
scripts/render.sh      # kubectl kustomize (print manifests, no apply)
scripts/restart.sh     # rollout restart
scripts/uninstall.sh   # delete workloads + Secret; keeps PVC + namespace
```

Pod helpers (target the `gateway` container, port 18789):

```bash
scripts/pod-logs.sh      # tail gateway logs
scripts/pod-shell.sh     # interactive bash in gateway
scripts/pod-connect.sh   # background port-forward 18789 (auto-reconnect)
scripts/pod-cp.sh <a> <b>          # upload file into gateway
scripts/pod-cp.sh -d <a> <b>       # download file from gateway
```

Common flags for all scripts: `--kubeconfig <path>`, `-n|--namespace <ns>`, `-p|--project <name>`
(Deployment name, default `openclaw`), `-v|--verbose`.

## Notes for operators

- The gateway Control UI (18789) is **not** exposed publicly; use `scripts/pod-connect.sh` or
  `kubectl port-forward svc/freechat-openclaw 18789:18789`. Only `https://<INGRESS_HOST>/voice/webhook`
  is public (for the voice-call plugin).
- To upgrade OpenClaw or the chromium sidecar, edit `OPENCLAW_IMAGE` / `CHROMIUM_IMAGE`
  in `configs/k8s/deploy.env`. The scripts feed the tag into a Kustomize `images:`
  transformer at apply/render time, so tracked manifests are never modified for bumps.
- To change the public host/TLS, edit both `configs/k8s/overlay/ingress.yaml` and `INGRESS_HOST`
  in `deploy.env`.

## Migrating from the legacy Helm deployment

If you previously deployed with the deprecated chart, uninstall the legacy releases first:

```bash
helm --kubeconfig configs/k8s/kube-private.conf uninstall freechat-openclaw -n fun-freechat
helm --kubeconfig configs/k8s/kube-private.conf uninstall freechat-openclaw-in -n ingress-default
# keep cert-manager if already present; otherwise scripts/install-cm.sh
```

`helm uninstall` deletes the legacy Deployment/Service/Ingress/ConfigMap but **keeps the
`freechat-openclaw` PVC** (it carries `helm.sh/resource-policy: keep`), so your `~/.openclaw`
data survives. `scripts/install.sh` then reuses that PVC and recreates the workloads with the
same legacy names (via the `namePrefix: freechat-` in the overlay).

> **Must uninstall first.** The new Deployment uses the selector `app: openclaw` (official base),
> while the legacy used `app.kubernetes.io/name: freechat-openclaw`. Deployment selectors are
> immutable, so applying over the legacy Deployment in place would fail. Uninstalling first
> (above) deletes the legacy Deployment so the new one is created fresh.

The legacy `values-private.yaml` has been split into `deploy.env` + `secrets.env` +
`openclaw.json` (the real runtime config, injected as a temp patch on top of
the tracked `overlay/openclaw-config-cm.yaml` placeholder at apply time) — the retired `configs/helm/`
directory and Helm-render scratch files have been removed.

### Naming differences from the legacy (no functional impact)

- Service port 18789 is named `gateway` (official base) vs legacy `http` — referenced only by
  number, never by name.
- The main container is named `gateway` (official base) vs legacy `main` — the `pod-*` scripts
  target `gateway` (set `CONTAINER` in `deploy.env` to override).
- The `init-skills` container is not included; ClawHub skills already installed on the PVC
  persist. Re-add an init-skills step if you need to install/upgrade skills at startup.

## Syncing the base from upstream

The manifests under `configs/k8s/base/` are vendored from the official
`openclaw` repo (`scripts/k8s/manifests/`). They do **not** auto-update — run
this to inherit upstream Kubernetes improvements (new probes, securityContext
tightening, new resources like NetworkPolicy/PDB, etc.):

```bash
scripts/sync-base.sh                     # from the sibling ../openclaw checkout
scripts/sync-base.sh --source <path>/scripts/k8s/manifests   # explicit path
```

It copies the upstream manifests into `configs/k8s/base/`, re-applies the one
local customization (excluding `pvc.yaml` so the existing data PVC is reused),
and runs `render.sh` to validate. New resources upstream adds are preserved; if
an upstream rename breaks an overlay patch, `render.sh` fails loudly and you
edit `configs/k8s/overlay/*-patch.yaml` to match. Review with
`git diff configs/k8s/base` and commit.
