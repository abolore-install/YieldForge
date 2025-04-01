# YieldForge - Bitcoin-Native Yield Aggregation Protocol

A non-custodial yield aggregator implementing Bitcoin DeFi strategies on Stacks L2 with institutional-grade risk management.

## Features

- **Risk-Profiled Allocation**

  - Conservative/Moderate/High risk strategies
  - Dynamic APY optimization
  - Customizable user allocations (basis points)

- **Security Framework**

  - Timelocked withdrawals (144 blocks/~24h)
  - Protocol whitelisting system
  - Multi-signature contract ownership
  - Emergency pause functionality

- **Economic Model**

  - 1% performance fee
  - 0.5% insurance fund contribution
  - Auto-compounding positions
  - Cross-protocol TVL balancing

- **Bitcoin Integration**
  - SIP-009 compliant assets
  - Stacks-secured smart contracts
  - Bitcoin-settled transactions

## Contract Architecture

### Core Components

1. **Protocol Registry**

   - Whitelisted DeFi protocols with risk ratings
   - Real-time APY tracking
   - TVL monitoring

2. **Position Management**

   - Shares-based accounting
   - Cross-protocol exposure limits
   - Deposit/Withdrawal queues

3. **Risk Engine**

   - Mean-Variance optimization
   - Protocol correlation matrix
   - Blacklist circuit breakers

4. **Fee Mechanism**
   ```clarity
   (define-private (deduct-fees amount)
       (let
           ((performance-fee (/ (* amount (var-get performance-fee-bps)) u10000))
           (insurance-fee (/ (* amount (var-get insurance-fee-bps)) u10000)))
   ```

## Key Functions

### User Operations

| Function             | Parameters                     | Description                              |
| -------------------- | ------------------------------ | ---------------------------------------- |
| `smart-deposit`      | (amount, token)                | Auto-allocation across optimal protocols |
| `request-withdrawal` | (protocol-id, amount)          | Initiate timelocked withdrawal           |
| `set-risk-profile`   | (conservative, moderate, high) | Set allocation percentages               |

### Protocol Management

```clarity
(define-public (add-protocol name contract-address token-address risk-level apy-bps)
  "Whitelist new protocol with risk rating and APY"
```

### Administrative

- `update-protocol-apy`: Adjust protocol's current APY
- `auto-compound`: Manual yield harvesting (owner-only)
- `pause-contract`: Emergency stop mechanism

## Error Handling

| Code | Error Message                | Description                     |
| ---- | ---------------------------- | ------------------------------- |
| 1000 | ERR-NOT-AUTHORIZED           | Unauthorized access attempt     |
| 1001 | ERR-PROTOCOL-NOT-WHITELISTED | Unapproved protocol interaction |
| 1005 | ERR-WITHDRAWAL-IN-PROGRESS   | Existing pending withdrawal     |
| 1010 | ERR-PROTOCOL-NOT-ACTIVE      | Protocol temporarily suspended  |

## Security Model

1. **Funds Protection**

   - Non-custodial architecture
   - 24h withdrawal timelock
   - TVL-based insurance pool

2. **Protocol Safeguards**

   ```clarity
   (define-map protocol-allocations
     {strategy-id: uint, risk-level: uint}
     {protocol-id: uint, allocation-percentage: uint}
   )
   ```

   - Maximum 25% allocation per protocol
   - APY deviation alerts
   - TVL withdrawal limits

3. **Operational Security**
   - Multi-sig contract upgrades
   - Quarterly security audits
   - Real-time anomaly detection

## Integration Guide

### JavaScript Example

```javascript
// Connect to Stacks wallet
const userSession = new UserSession();

// Execute smart deposit
const txOptions = {
  contractAddress: "SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE",
  contractName: "yieldforge-v1",
  functionName: "smart-deposit",
  functionArgs: [uintCV(1000000), standardPrincipalCV("SP2JXK...")],
  senderKey: userSession.loadUserData().appPrivateKey,
};

await broadcastTransaction(txOptions);
```
