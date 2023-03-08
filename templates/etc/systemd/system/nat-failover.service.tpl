[Unit]
Description=Lambda trigger for failover and recovery of nat instance
Before=shutdown.target reboot.target halt.target
Requires=network-online.target network.target

[Service]
KillMode=mixed
ExecStart=/bin/sleep 60
ExecStart=/usr/bin/python3 /usr/local/bin/nat-failover-trigger.py -t recover
ExecStop=/usr/bin/python3 /usr/local/bin/nat-failover-trigger.py -t failover
ExecStop=/bin/sleep 30
RemainAfterExit=yes
Type=oneshot
SyslogIdentifier=nat-instance-failover

[Install]
WantedBy=multi-user.target
