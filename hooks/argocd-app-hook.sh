#!/usr/bin/env bash

if [[ $1 == "--config" ]]; then
  cat <<EOF
configVersion: v1
kubernetes:
  - name: execute_on_changes_of_app
    kind: Application
    apiVersion: argoproj.io/v1alpha1
    executeHookOnEvent: ["Modified"]
    executeHookOnSynchronization: false
    jqFilter: ".status.health.status"
    namespace:
      nameSelector: 
        matchNames: ["argocd"]
EOF
else
  type=$(jq -r '.[0].type' ${BINDING_CONTEXT_PATH})
  if [[ $type == "Event" ]]; then
    name=$(jq -r '.[0].object.metadata.name' ${BINDING_CONTEXT_PATH})
    kind=$(jq -r '.[0].object.kind' ${BINDING_CONTEXT_PATH})
    echo "${kind}/${name} object was updated"
  else
    echo "Update not recognized"
    exit 0
  fi
  set -e
  set -o pipefail

  ARGOCDCM="${CONFIG_CM:=argocd-cm}"

  APP_STATUS=$(jq -r '.[0].object.status.health.status' ${BINDING_CONTEXT_PATH})
  APP_GIT_URL=$(jq -r '.[0].object.spec.source.repoURL' ${BINDING_CONTEXT_PATH})
  APP_GIT_REF=$(jq -r '.[0].object.spec.source.targetRevision' ${BINDING_CONTEXT_PATH})
  APP_GIT_PATH=$(jq -r '.[0].object.spec.source.path' ${BINDING_CONTEXT_PATH})

  APP_GIT_URL_BASE=$(echo $APP_GIT_URL | perl -pe 's!(http(s|)://(.*?))/.*!$1!g')

  if [ "$APP_STATUS" != "Degraded" ]; then
    echo "Skipping: App not Degraded"
    exit 0
  fi

  sourceType=$(jq -r '.[].object.status.sourceType' ${BINDING_CONTEXT_PATH})
  if [ $sourceType != "Kustomize" ]; then
    echo "Skipping: App not using Kustomize"
    exit 0
  fi

  rolloutstatus=$(jq -r '.[0].object.status.resources[]|select(.kind == "Rollout").health.status' ${BINDING_CONTEXT_PATH})
  if [[ ! " ${rolloutstatus[*]} " =~ "Degraded" ]]; then
    echo "Skipping: No Rollout found in Degraded state"
    exit 0
  fi

  message=$(jq -r '.[].object.status.operationState.syncResult.resources[]|select((.kind == "Rollout") and (.message |contains("unchanged")| not))' ${BINDING_CONTEXT_PATH})
  if [ -z "$message" ]; then
    echo "Skipping: Rollout resources were not updated during the last Sync action"
    exit 0
  fi

  TEMPDIR=/tmp/$RANDOM
  mkdir -p $TEMPDIR

  if kubectl get cm $ARGOCDCM >/dev/null 2>&1; then
    echo "Checking git credentials from $ARGOCDCM"

    kubectl get cm $ARGOCDCM -oyaml | yq e '.data.["repository.credentials"]' - >$TEMPDIR/gitcreds.txt

    cat $TEMPDIR/gitcreds.txt | yq e '.[] |select(.url == "'$APP_GIT_URL_BASE'*").passwordSecret' - >$TEMPDIR/gitcredssecret.txt
    if [ -s $TEMPDIR/gitcredssecret.txt ]; then
      echo "Credentials found for $APP_GIT_URL_BASE"
      export GIT_TOKEN=$(kubectl get secret $(cat $TEMPDIR/gitcredssecret.txt | yq e '.name' -) -oyaml | yq e '.data.'$(cat $TEMPDIR/gitcredssecret.txt | yq e '.key' -) - | base64 -d)
      echo 'echo $GIT_TOKEN' >$TEMPDIR/.git-askpass && chmod +x $TEMPDIR/.git-askpass
      export GIT_ASKPASS=$TEMPDIR/.git-askpass
    else
      echo "No credentials found for $APP_GIT_URL_BASE"
    fi
  fi

  git config --global user.name "argocd-rollouts-git-updater"
  git config --global user.email argocd-rollouts-git-updater@argocd-rollouts-git-updater.gitops

  git clone $(if [ "$APP_GIT_REF" != "null" ]; then echo "-b $APP_GIT_REF"; fi) $APP_GIT_URL $TEMPDIR/repo
  cd $TEMPDIR/repo/$APP_GIT_PATH

  #for images already in kustomization loop through them and update with the latest from the app_list
  imagelist=($(cat kustomization.yaml | yq e '.images[] as $item ireduce ({}; .[$item | .name]= ($item | .newName + ":"  + .newTag) )' - | perl -pe 's/.*?: //g'))
  appimagelist=($(jq -r '.[0].object.status.summary.images[]' ${BINDING_CONTEXT_PATH} | tac | awk -F ':' '!seen[$1]++'))

  for i in $imagelist; do
    echo "Checking $i"
    if [[ ! " ${appimagelist[*]} " =~ " ${i} " ]]; then
      echo "App does not contain image, Checking other tags"
      imagename=$(echo $i | awk -F ':' '{print $1}')
      newimage=$(printf '%s\n' "${appimagelist[@]}" | grep "^$imagename" | tail -1)
      echo "Updating kustomization.yaml:  $imagename=$newimage"
      updatedimages="$updatedimages,$imagename=$newimage"
      kustomize edit set image $imagename=$newimage
    fi
  done
  cat kustomization.yaml | yq e '.' - >kustomization-new.yaml
  mv kustomization-new.yaml kustomization.yaml
  git add .
  
  message="Rollout Failed: Images updated: $updatedimages"
  git diff --ignore-space-at-eol -b -w --ignore-blank-lines --staged --quiet || git commit -m "${message}..."
  git push

  rm -rf $TEMPDIR

fi
