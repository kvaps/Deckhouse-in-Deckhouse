# Deckhouse-in-Deckhouse

Run Deckhouse in Deckhouse using virtualization module

## Quick Start

### Preparation

[Setup Deckhouse](https://deckhouse.io/gs/bm/step2.html) with [cni-cilium], enable [virtualization] and [linstor] modules:

[cni-cilium]: https://deckhouse.io/documentation/latest/modules/021-cni-cilium/
[virtualization]: https://deckhouse.io/documentation/latest/modules/490-virtualization/
[linstor]: https://deckhouse.io/documentation/latest/modules/041-linstor/

```yaml
---
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: cni-cilium
spec:
  enabled: true
  settings:
    # Choose one:
    # - without network encapsulation (direct routes):
    #     createNodeRoutes: true
    # - with network encapsulation (vxlan tunnel):
    #     tunnelMode: VXLAN
  version: 1
---
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: virtualization
spec:
  enabled: true
  settings:
    vmCIDRs:
    - 10.10.10.0/24
  version: 1
---
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: linstor
spec:
  enabled: true
  version: 1
```

Configure storage-pools as referenced in [linstor module configuration](https://deckhouse.io/documentation/latest/modules/041-linstor/configuration.html)

### Usage

Setup jsonnet (version v0.18.0 is required):

```bash
# From repository of your OS
brew install jsonnet
# From github (alternative go version)
curl -sSL https://github.com/google/go-jsonnet/releases/download/v0.19.1/go-jsonnet_0.19.1_Linux_x86_64.tar.gz | tar -C /usr/local/bin/ -xzvf- jsonnet jsonnetfmt
```

Clone this repo:

```bash
git clone https://github.com/kvaps/Deckhouse-in-Deckhouse
```

Example cluster is described in [`example.jsonnet`](example.jsonnet) file.

It consists of:
- 3 masters
- 2 system
- 1 frontend
- 2 worker nodes  

Additionaly one bootstrap vm will be used for first time cluster initiation. It can be removed after first master is bootstrapped.

Feel free to make your own copy and update any settings in it.  
Refer jsonnet documentation to see [examples](https://jsonnet.org/), and [standard library](https://jsonnet.org/ref/stdlib.html)

Run following commands to render the information:
```bash
# List all virtual machines going to be deployed
jsonnet example.jsonnet | jq .vms

# List all node groups going to be added in new cluster
jsonnet example.jsonnet | jq .ngs

# Print deckhouse config file
jsonnet example.jsonnet | jq -r .config

# Print bootstrap commands which includes everything above
jsonnet example.jsonnet | jq -r .script
```

SSH on some node of your cluster, with passing trough your ssh-agent (for passwordless authentication)

```bash
ssh -A user@10.22.33.44
```
and run those commands
