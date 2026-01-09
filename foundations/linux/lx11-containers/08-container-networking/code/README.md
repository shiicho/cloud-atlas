# Container Networking Code Examples

This directory contains demonstration scripts for container networking concepts.

## Scripts

### veth-bridge-demo.sh

Demonstrates veth pairs and bridge networking:
- Creates a bridge (virtual switch)
- Creates two network namespaces (simulating containers)
- Connects namespaces to bridge via veth pairs
- Tests inter-container connectivity

```bash
sudo ./veth-bridge-demo.sh
```

### nat-setup.sh

Demonstrates NAT configuration with nftables:
- Creates a network namespace with external connectivity
- Configures IP forwarding
- Sets up masquerade (SNAT) for outbound traffic
- Demonstrates port forwarding (DNAT)

**IMPORTANT**: Uses nftables (modern) instead of iptables (legacy)

```bash
sudo ./nat-setup.sh
```

## Requirements

- Linux kernel with namespace support
- Root privileges (sudo)
- iproute2 package (ip command)
- nftables package (nft command)

## Network Topology

### veth-bridge-demo.sh

```
   container1 (172.20.0.2)  container2 (172.20.0.3)
        |                         |
      veth1-ct                  veth2-ct
        |                         |
      veth1-br                  veth2-br
        |                         |
        +----------+----------+
                   |
               br-demo (172.20.0.1)
```

### nat-setup.sh

```
   Container (172.21.0.2)
        |
      veth pair
        |
   Host (172.21.0.1)
        |
   nftables NAT (MASQUERADE)
        |
   External Network
```

## Key Concepts

### veth Pair
Virtual Ethernet pair - like a virtual network cable with two ends

### Bridge
Virtual switch - connects multiple network interfaces

### NAT (Network Address Translation)
- **SNAT/MASQUERADE**: Changes source IP for outbound traffic
- **DNAT**: Redirects incoming traffic to different destination

### nftables vs iptables

| Feature | nftables | iptables |
|---------|----------|----------|
| Syntax | Unified | Multiple tables |
| Performance | Better | Legacy |
| Updates | Atomic | Sequential |
| Status | Modern | Deprecated |

## Cleanup

Both scripts automatically clean up on exit. If manual cleanup is needed:

```bash
# Delete namespaces
sudo ip netns del container1
sudo ip netns del container2
sudo ip netns del nat-container

# Delete bridge
sudo ip link del br-demo

# Delete nftables table
sudo nft delete table ip container_nat
```
