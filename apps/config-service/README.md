# RGS Kubernetes Deployment

## Prerequisites

Install the following tools

- [pack](https://github.com/buildpacks/pack)
- [kustomize](https://kustomize.io/)

## Build/Run locally

Deploy the app using `kubectl`:

```sh
git clone git@github.com:Everi-Digital/rgs-kubernetes.git
cd rgs-kubernetes/apps
kubectl apply -k apps/config-service/overlays/dev/
```

Build the app using `pack`:

```sh
git clone https://github.com/everi/config-service.git ../config-service
cd ../config-service
pack build applications/maven
```

Test locally with Docker

```sh
docker run --rm --tty --publish 8080:8080 applications/maven
curl -s http://localhost:8080/actuator/health | jq .
```

## Tag/Push to registry

```sh
docker tag applications/maven:latest azltandevacr.azurecr.io/rgs-server-config-service:0.0.1
docker push azltandevacr.azurecr.io/rgs-server-config-service:0.0.1
```

## Update the digest reference on production image

View change first

```sh
kustomize build apps/config-service/overlays/prod | kbld -f -
```

Update using `yq` and `kbld`

```sh
CURRENT_APP_IMAGE=$(kustomize build apps/config-service/overlays/dev | yq e '.spec.template.spec.containers[].image')
IMAGE=$(kustomize build apps/config-service/overlays/dev | kbld -f - | grep -e 'image:' | awk '{print $NF}')
sed -i "s|${CURRENT_APP_IMAGE}|${IMAGE}|" apps/config-service/overlays/prod/deployment.yaml
```
