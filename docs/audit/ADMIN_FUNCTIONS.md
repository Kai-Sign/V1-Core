# Admin Functions Documentation - KaiSign v1.0.0

## Overview

This document details all administrative functions available in the KaiSign contract, their capabilities, limitations, and security considerations.

## Admin Role Permissions

### Available Admin Functions

#### 1. pause()
```solidity
function pause() external onlyRole(ADMIN_ROLE)
```
**Purpose**: Temporarily halt all contract operations  
**Effect**:
- Stops all state-changing functions
- View functions remain operational
- Preserves all contract state
- No funds are locked or lost

**Use Case**: Emergency response to security issues or external protocol failures

---

#### 2. unpause()
```solidity
function unpause() external onlyRole(ADMIN_ROLE)
```
**Purpose**: Resume contract operations after pause  
**Effect**:
- Re-enables all functions
- No state is lost during pause
- Operations continue from where they left off

**Use Case**: Resume normal operations after issue resolution

---

#### 3. setMinBond(uint256)
```solidity
function setMinBond(uint256 newMinBond) external onlyRole(ADMIN_ROLE)
```
**Purpose**: Adjust minimum bond requirement  
**Effect**:
- Changes bond amount for new proposals
- Does not affect existing proposals
- Must be greater than 0

**Use Case**: Adjust for network conditions or spam prevention

---

#### 4. grantRole(bytes32, address)
```solidity
function grantRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role))
```
**Purpose**: Add new admin  
**Effect**:
- Grant admin privileges to another address
- Multiple admins supported
- Follows OpenZeppelin AccessControl pattern

**Use Case**: Add team members or transition to multisig

---

#### 5. revokeRole(bytes32, address)
```solidity
function revokeRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role))
```
**Purpose**: Remove admin  
**Effect**:
- Revoke admin privileges from an address
- Cannot revoke own role if last admin
- Immediate effect

**Use Case**: Remove compromised or unnecessary admin accounts

---

#### 6. renounceRole(bytes32, address)
```solidity
function renounceRole(bytes32 role, address account) public
```
**Purpose**: Self-remove admin role  
**Effect**:
- Admin can renounce their own role
- Cannot be called by others
- Ensure other admins exist first

**Use Case**: Clean handover of responsibilities

## Admin Limitations

### What Admins CANNOT Do

Admins are explicitly prevented from:

1. **Modifying Existing Data**
   - Cannot alter existing specs or proposals
   - Cannot change commitment hashes
   - Cannot modify reveal data

2. **Accessing User Funds**
   - Cannot withdraw user bonds
   - Cannot redirect incentives
   - Cannot claim platform fees (goes to treasury)

3. **Overriding Protocol Logic**
   - Cannot change Reality.eth outcomes
   - Cannot bypass commit-reveal timing
   - Cannot alter settled questions

4. **Changing Core Parameters**
   - Cannot alter platform fee percentage (5%)
   - Cannot change immutable addresses:
     - realityETH address
     - arbitrator address
     - treasury address

5. **Upgrading Contract**
   - Contract is non-upgradeable by design
   - Cannot add new functions
   - Cannot modify existing logic

## Security Model

### Multi-Signature Requirement

**Recommendation**: Admin role should be held by a multi-signature wallet

**Suggested Configuration**:
- 3-of-5 multisig for mainnet
- 2-of-3 minimum for testnet
- Time-lock consideration for sensitive operations

### Role Hierarchy

```
DEFAULT_ADMIN_ROLE (0x00)
    └── ADMIN_ROLE
```

- DEFAULT_ADMIN_ROLE: Can manage ADMIN_ROLE
- ADMIN_ROLE: Can execute admin functions
- Initial deployer gets DEFAULT_ADMIN_ROLE

### Access Control Events

All admin actions emit events for transparency:
```solidity
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)
event Paused(address account)
event Unpaused(address account)
event MinBondUpdated(uint256 oldMinBond, uint256 newMinBond)
```

## Emergency Procedures

### Pause Protocol

**When to Pause**:
- Critical vulnerability discovered
- Reality.eth compromise
- Suspicious activity detected
- External dependency failure

**Pause Procedure**:
1. Execute pause() from admin account
2. Investigate issue
3. Communicate with users
4. Implement fix if needed
5. Execute unpause() when safe

### Admin Transition

**Safe Transition Process**:
1. Grant new admin role first
2. Verify new admin can execute functions
3. Revoke old admin role
4. Document transition

**Never**:
- Remove all admins
- Transition during active operations
- Skip verification steps

## Monitoring Admin Actions

### Recommended Monitoring

1. **Real-time Alerts** for:
   - pause() calls
   - Role changes
   - Min bond adjustments

2. **Regular Audits** of:
   - Active admin addresses
   - Recent admin actions
   - Role assignments

3. **Documentation** of:
   - Why actions were taken
   - Who authorized actions
   - Impact assessment

## Best Practices

### Do's
- ✅ Use multisig for admin role
- ✅ Document all admin actions
- ✅ Test on testnet first
- ✅ Communicate changes to users
- ✅ Keep admin count minimal
- ✅ Regular security reviews

### Don'ts
- ❌ Share admin private keys
- ❌ Use EOA for mainnet admin
- ❌ Make changes without consensus
- ❌ Pause without communication
- ❌ Remove last admin
- ❌ Rush emergency procedures

## Incident Response

### Response Matrix

| Severity | Response Time | Action | Authority |
|----------|--------------|--------|-----------|
| Critical | Immediate | Pause contract | Any admin |
| High | 1 hour | Team consensus | 2+ admins |
| Medium | 24 hours | Scheduled action | Team vote |
| Low | Next update | Document only | Any admin |

### Communication Protocol

1. **Internal**: Immediate team notification
2. **Public**: Within 1 hour via official channels
3. **Post-Mortem**: Within 48 hours
4. **Resolution**: When issue resolved

## Governance Considerations

### Current Model
- Centralized admin control
- Quick response capability
- Clear accountability

### Future Considerations
- Transition to DAO governance
- Time-locked operations
- Community voting mechanisms
- Progressive decentralization

## Compliance and Legal

### Admin Responsibilities
- Fiduciary duty to users
- Compliance with local regulations
- Transparent operations
- Regular reporting

### Liability Limitations
- Admin actions are logged
- No warranty implied
- Users accept risks
- Force majeure provisions

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-09-07  
**Classification**: Public  

## Contact

For admin-related inquiries:
- GitHub: https://github.com/kaisign/v1-core
- Emergency: [Via multisig signers]