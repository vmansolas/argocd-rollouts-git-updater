FROM flant/shell-operator:v1.0.9
RUN apk --no-cache add curl git perl yq
RUN ARCH=$(arch) && if [ "$ARCH" == "aarch64" ]; then ARCH="arm64";elif [ "$ARCH" == "x86_64" ]; then ARCH="amd64"; fi &&curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl
RUN curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash && mv /kustomize /usr/local/bin/kustomize
ADD hooks /hooks
