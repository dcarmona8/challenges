 # Challenge 1
 
Because it seems that text relates to Azure, I've tried to focus solution in Azure AKS.

![Pasted image 20240819090726](https://github.com/user-attachments/assets/621273b7-2133-40dc-b944-e98f948d27c3)

- **Isolate specific node groups forbidding the pods scheduling in this node
groups.**

1. Proposed solution needs to label pool of nodes where it is going to be forbidden scheduling. Label assigned to these nodes will be `no-schedule=true`
```
az aks nodepool update --resource-group AKSResourceGroup --cluster-name AKSCluster --name NodePoolForbidden --labels "no-schedule=true"
```
Where:
- **AKSResourceGroup**: `<Resource Group name created in Azure>`
- **AKSCluster**: `<AKS Cluster Name created in Azure>`
- **NodePoolForbidden**: `<Name of Node Pool, set of nodes logically grouped with a name>`

2. Update deployment.yaml with new label

In `deployment.yaml`, it will be used `nodeAffinity` rule to ensure pods are not scheduled on nodes with previous label, so it is neccesary to update deployment section below:

```
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: no-schedule
                    operator: NotIn
                    values:
                      - "true"

```

- **Prevent Pods of the Same Type from Being Scheduled on the Same Node**

To ensure two pods of same type are not scheduled on node, it will be used **Pod Anti-Affinity**,
so it will be added section below to deployment manifest:

```
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - ping
              topologyKey: "kubernetes.io/hostname"
```

- **Deploy Pods Across Different Availability Zones**

In Azure,  AKS cluster in 3 availability zones is selected. Azure labels nodes with `topology.kubernetes.io/zone` label for pods.

Command `kubectl get nodes --show-labels` may be used to check this point is correct.

```
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: topology.kubernetes.io/zone
                    operator: In
                    values:
                      - "zone-1"
                      - "zone-2"
                      - "zone-3"
```

