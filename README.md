# nightly-performance tests

This repo contains k8s kusomization to deploy a cronjob that run a script to run nightly performance tests.

The script deploys a keramik network and simulation and tags resources for monitoring.

## Usage

The base manifests are in the `bases/nightly-performance` directory. This path contains the defaults for all the other tests.

The other root level directories are different configurations for the tests. The `kustomization.yaml` file in each directory is used to build the final manifests.

Deploy an update to a test by updating the manifests and run something like

```
kubectl apply -k ./dev-hermetic-amd
```

## Limitations

There are 2 secrets required for the tests to send a Grafana annotation and Discord message.

Neither are required to run a test, but the tests will fail if they are not present.

The tests are configurated to use a custom storageClass that must be present on the cluster, or overridden in the kustomization. The provided storageClass is GCP specific.

Apply it to a new cluster like

```
kubectl apply -f ./storageClass.yaml
```