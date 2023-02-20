// Resturns default labels for node groups by name
local ngLabels(x) =
  if x == 'master' then {
    'node-role.deckhouse.io/control-plane': '',
    'node-role.deckhouse.io/master': '',
  }
  else if x == 'system' then {
    'node-role.deckhouse.io/system': '',
  }
  else if x == 'frontend' then {
    'node-role.deckhouse.io/frontend': '',
  }
  else {};

// Returns default taints for node groups by name
local ngTaints(x) =
  if x == 'master' then [
    {
      effect: 'NoSchedule',
      key: 'node-role.kubernetes.io/control-plane',
    },
  ]
  else if x == 'system' then [
    {
      effect: 'NoExecute',
      key: 'dedicated.deckhouse.io',
      value: 'system',
    },
  ]
  else if x == 'frontend' then [
    {
      effect: 'NoExecute',
      key: 'dedicated.deckhouse.io',
      value: 'system',
    },
  ]
  else [];

// gathers node groups from vm list:
// eg:
// master-0, master-1, master-2 --> master
// system-0, system-2           --> system
// worker-0, worker-2           --> worker
local ngNames(vms) = [
  x
  for x in std.uniq(std.map(
    function(x)
      local a = std.split(x, '-');
      std.join('', a[0:(std.length(a) - 1)]),
    [x.metadata.name for x in vms.items]
  ))
  if x != 'bootstrap'
];


{
  // VirtualMachines resource template
  vms(name, num, p): [
    {
      apiVersion: 'deckhouse.io/v1alpha1',
      kind: 'VirtualMachine',
      metadata: {
        name: name + '-' + x,
        namespace: 'default',
        labels: {
          role: name,
        },
      },
      spec: {
        running: true,
        bootDisk: {
          autoDelete: true,
          size: p.disk,
          source: {
            kind: 'ClusterVirtualMachineImage',
            name: 'ubuntu-22.04',
          },
        },
        resources: {
          cpu: p.cpu,
          memory: p.mem,
        },
        affinity: {
          podAntiAffinity: {
            requiredDuringSchedulingIgnoredDuringExecution: [
              {
                labelSelector: {
                  matchExpressions: [
                    {
                      key: 'app',
                      operator: 'In',
                      values: [name],
                    },
                  ],
                },
                topologyKey: 'kubernetes.io/hostname',
              },
            ],
          },
        },
      },
    }
    for x in std.range(0, num - 1)
  ],

  // NodeGroups resource template
  ngs(vms): [
    {
      apiVersion: 'deckhouse.io/v1',
      kind: 'NodeGroup',
      metadata: {
        name: x,
      },
      spec: {
        nodeTemplate: {
          labels: ngLabels(x),
          taints: ngTaints(x),
        },
        nodeType: 'Static',
      },
    }
    for x in ngNames(vms)
  ],

  // Generates bootstrap script
  script(vms, ngs, d8config, sshUser='ubuntu', sshOpts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'):
    std.join(
      '\n',
      ['\n# apply vm resources'] +
      [
        "sudo kubectl apply -f- <<'EOT'",
        std.manifestJsonMinified(vms),
        'EOT',
      ]
      +
      ['\n# wait for vms to be deployed'] +
      [
        std.format(
          'sudo kubectl wait  %s --timeout=5m --for=jsonpath={.status.phase}=Running ',
          [std.join(' ', ['vm/' + x.metadata.name for x in vms.items])]
        ),
      ]
      +
      ['\n# gather vm ip addresses'] +
      [
        std.format(
          'D8VM_%s=$(sudo kubectl get -n %s vm/%s -o jsonpath={.status.ipAddress})',
          [std.strReplace(x.metadata.name, '-', '_'), x.metadata.namespace, x.metadata.name]
        )
        for x in vms.items
      ]
      +
      ['\n# install docker'] +
      [
        std.format('ssh %s %s@$D8VM_bootstrap_0 sudo apt-get update', [sshOpts, sshUser]),
        std.format('ssh %s %s@$D8VM_bootstrap_0 sudo apt-get -y install docker.io', [sshOpts, sshUser]),
      ]
      +
      ['\n# generate and copy temprorary ssh key for dhctl'] +
      [
        std.format('yes "" | ssh %s %s@$D8VM_bootstrap_0 sudo ssh-keygen -q -t rsa -f /root/.ssh/id_rsa', [sshOpts, sshUser]),
        std.format('SSH_PUBLICKEY=$(ssh %s %s@$D8VM_bootstrap_0 sudo cat /root/.ssh/id_rsa.pub)', [sshOpts, sshUser]),
        std.format("ssh %s %s@$D8VM_master_0 'mkdir -p $HOME/.ssh'", [sshOpts, sshUser]),
        std.format("echo \"$SSH_PUBLICKEY\" | ssh %s %s@$D8VM_master_0 'cat >> $HOME/.ssh/authorized_keys'", [sshOpts, sshUser]),
      ]
      +
      ['\n# write dhctl config file'] +
      [
        std.format("ssh %s %s@$D8VM_bootstrap_0 'sudo tee /root/config.yml' >/dev/null <<'EOT'", [sshOpts, sshUser]),
        d8config,
        'EOT',
      ]
      +
      ['\n# bootstrap first master'] +
      [
        std.format('ssh %s %s@$D8VM_bootstrap_0 sudo docker run --pull=always -v /root/config.yml:/config.yml -v /root/.ssh/:/tmp/.ssh/ registry.deckhouse.io/deckhouse/ce/install:stable \\\n', [sshOpts, sshUser]) +
        std.format('  dhctl bootstrap --ssh-user=%s --ssh-host=$D8VM_master_0 --ssh-agent-private-keys=/tmp/.ssh/id_rsa --config=/config.yml', sshUser),
      ]
      +
      ['\n# bootstrap other masters'] +
      [
        std.format("BOOTSTRAP_master=$(ssh %s %s@$D8VM_master_0 sudo kubectl -n d8-cloud-instance-manager get secret manual-bootstrap-for-master -o json | jq '.data.\"bootstrap.sh\"' -r)", [sshOpts, sshUser]),
      ]
      +
      [
        std.format(
          'echo "$BOOTSTRAP_%s" | ssh %s %s@$D8VM_%s "base64 -d | sudo bash -s"',
          ['master', sshOpts, sshUser, std.strReplace(vm.metadata.name, '-', '_')]
        )
        for vm in vms.items
        if vm.metadata.name != 'master-0'
        if std.startsWith(vm.metadata.name, 'master-')
      ]
      +
      ['\n# create node groups'] +
      [
        std.format("ssh %s %s@$D8VM_master_0 sudo kubectl apply -f- <<'EOT'", [sshOpts, sshUser]),
        std.manifestJsonMinified(ngs),
        'EOT',
        std.format(
          'ssh %s %s@$D8VM_master_0 sudo kubectl wait -n default %s --for=jsonpath={.status.conditionSummary.ready}=True',
          [sshOpts, sshUser, std.join(' ', ['ng/' + x.metadata.name for x in ngs.items])]
        ),
      ]
      +
      ['\n# bootstrap other nodes'] +
      [
        std.format(
          "BOOTSTRAP_%s=$(ssh %s %s@$D8VM_master_0 sudo kubectl -n d8-cloud-instance-manager get secret manual-bootstrap-for-%s -o json | jq '.data.\"bootstrap.sh\"' -r)",
          [ng.metadata.name, sshOpts, sshUser, std.strReplace(ng.metadata.name, '-', '_')]
        )
        for ng in ngs.items
        if ng.metadata.name != 'master'
      ]
      +
      [
        std.format(
          'echo "$BOOTSTRAP_%s" | ssh %s %s@$D8VM_%s "base64 -d | sudo bash -s"',
          [ng.metadata.name, sshOpts, sshUser, std.strReplace(vm.metadata.name, '-', '_')]
        )
        for vm in vms.items
        for ng in ngs.items
        if ng.metadata.name != 'master'
        if std.startsWith(vm.metadata.name, ng.metadata.name + '-')
      ]
    ),
}
