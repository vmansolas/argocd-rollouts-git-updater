export svc_name := argocd-rollouts-git-updater
export tag := latest


all: docker

docker:
	scripts/build-image

kind:
	USE_KIND=y scripts/build-image