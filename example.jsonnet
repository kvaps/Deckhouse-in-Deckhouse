local d8virt = import 'lib/d8virt.jsonnet';

// Create list of virtual machines (bootstrap and master are manadatory)
local vms =
  d8virt.vms('bootstrap', 1, { cpu: '1', mem: '4Gi', disk: '20Gi' }) +
  d8virt.vms('master', 3, { cpu: '4', mem: '8Gi', disk: '40Gi' }) +
  d8virt.vms('system', 2, { cpu: '4', mem: '8Gi', disk: '100Gi' }) +
  d8virt.vms('worker', 2, { cpu: '8', mem: '16Gi', disk: '150Gi' }) +
  [
    // Example override: add specific nodeSelector for frontend VM
    x { spec+: { nodeSelector: { 'node-role.deckhouse.io/frontend': '' } } }
    for x in d8virt.vms('frontend', 1, { cpu: '2', mem: '4Gi', disk: '20Gi' })
  ];

// Specify overrides for virtual machine resources
local vmOverrides = {
  spec+: {
    bootDisk+: {
      source: {
        kind: 'ClusterVirtualMachineImage',
        name: 'ubuntu-22.04',
      },
      storageClassName: 'linstor-thindata-r2',
    },
    userName: 'ubuntu',
    sshPublicKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAEQDSB2i8Sstj6kl9Ekyn7A3T',
  },
};

// Specify Deckhouse config
local d8Config = [
  {
    apiVersion: 'deckhouse.io/v1',
    kind: 'ClusterConfiguration',
    clusterType: 'Static',
    podSubnetCIDR: '10.112.0.0/16',
    serviceSubnetCIDR: '10.223.0.0/16',
    kubernetesVersion: 'Automatic',
    clusterDomain: 'cluster.local',
  },
  {
    apiVersion: 'deckhouse.io/v1',
    kind: 'InitConfiguration',
    deckhouse: {
      releaseChannel: 'Stable',
      configOverrides: {
        global: {
          modules: {
            publicDomainTemplate: '%s.example.com',
          },
        },
        cniCiliumEnabled: true,
        cniCilium: {
          tunnelMode: 'VXLAN',
        },
      },
    },
  },
  {
    apiVersion: 'deckhouse.io/v1',
    kind: 'StaticClusterConfiguration',
    internalNetworkCIDRs: [
      '10.10.10.0/24',
    ],
  },
];

// Start building root object
{
  // List of VirtualMachines with overrides
  vms: {
    apiVersion: 'v1',
    kind: 'List',
    items: [
      vm + vmOverrides
      for vm in vms
    ],
  },
  // List of NodeGroups
  ngs: {
    apiVersion: 'v1',
    kind: 'List',
    items: d8virt.ngs($.vms),
  },
  // Deckhouse bootstrap config
  config: std.manifestYamlStream(d8Config, false, false, false),
  // Bootstrap script includes all above
  script: d8virt.script(self.vms, self.ngs, self.config),
}
