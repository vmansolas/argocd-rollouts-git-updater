## argocd-rollouts-git-updater

This project's purpose is to provide a GitOps experience for ArgoCD + Argo Rollouts users during automated rollback.
When Rollout steps include a metrics-based Analysis that fails, the Rollout will revert all traffic back to the previous ReplicaSet, aborting the Rollout. In an environment where deployments are performed by updating the image tag/reference in git, this Rollout failure is not depicted with a git update. The indication that this occurred is through the health status of the Rollout resource and subsequently the ArgoCD Application.

The controller runs on the same cluster as the argocd server and watches for updates to the health of the Applications.

ref: https://github.com/argoproj/argo-rollouts/issues/1153

#### Restrictions/Assumptions:
For the controller to work smoothly the following need to be met:
- The App is using Kustomize
- Image updates are controlled by the "images" in Kustomization.yaml
- The application references a branch or HEAD

### TODOs
- Metrics
- Notifications
- Annotation argocd-rollouts-git-updater/enabled: true
- ...

### Build

Prerequisite Tools: bash, awk, git
Build shell-operator image with custom script:

```
docker build . -t <org>/argocd-rollouts-git-updater:v0.1
docker push <org>/argocd-rollouts-git-updater:v0.1
```

Deploy Manifests:

```
kustomize build manifests| kubectl apply -f -
```


