output: { all: "| tee -a /var/log/cloud-init-output.log" }

apt_upgrade: true

packages:
 - traceroute
 - nmap
 - keepalived
 - python3-boto3

write_files:
  - path: /usr/local/bin/nat-failover-trigger.py
    encoding: gz+b64
    owner: root:root
    permissions: 0744
    content: ${nat_script_file}
  - path: /etc/systemd/system/nat-failover.service
    encoding: gz+b64
    owner: root:root
    permissions: 0644
    content: ${nat_systemd_file}
  - path: /usr/local/bin/add_default_route.py
    encoding: gz+b64
    owner: root:root
    permissions: 0744
    content: ${nat_add_route_file}

bootcmd:
  - [ sh, -c, "[ -x /var/lib/cloud/instance/scripts/runcmd ] && /var/lib/cloud/instance/scripts/runcmd" ]

runcmd:

  - [ sh, -c, "sysctl -q -w net.ipv4.ip_forward=1" ]
  - [ sh, -c, "echo 1 > /proc/sys/net/ipv4/ip_forward" ]
  - [ iptables, -t, nat, -I, POSTROUTING, -s, ${vpc_cidr}, -d, 0.0.0.0/0, -j, MASQUERADE ]
  - [ sh, -c, "systemctl enable nat-failover.service" ]
  - [ sh, -c, "systemctl daemon-reload" ]
  - [ sh, -c, "/usr/local/bin/add_default_route.py" ]

package_upgrade: true
