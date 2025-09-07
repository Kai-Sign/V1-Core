# Known Issues & Limitations - KaiSign v1.0.0

## Overview

This document outlines known issues, limitations, and design decisions in the KaiSign v1.0.0 smart contract system. These items have been identified during development and testing and are documented for transparency with auditors and users.

## Known Issues

### 1. Reality.eth Dependency

**Issue**: Contract depends on external Reality.eth protocol  
**Impact**: Medium  
**Status**: By Design  

**Description**: The system relies on Reality.eth for arbitration, creating an external dependency.

**Mitigation**: 
- Reality.eth is a battle-tested, audited protocol
- Manual override possible through admin functions in emergency
- Contract can be paused if Reality.eth becomes unavailable

---

### 2. Timestamp Dependence

**Issue**: Uses `block.timestamp` for time-based logic  
**Impact**: Low  
**Status**: Acknowledged  

**Description**: Contract uses block timestamps for deadlines and timeouts, which can be manipulated by miners within ~15 seconds.

**Mitigation**:
- All time windows are hours or days (minimum 1 hour)
- 15-second manipulation negligible for these timeframes
- No high-value decisions made on exact timestamps

---

### 3. Front-Running During Reveal Phase

**Issue**: Theoretical front-running possible after commit phase  
**Impact**: Low  
**Status**: Mitigated  

**Description**: Once commitment is made, others know a reveal is coming within 1 hour.

**Mitigation**:
- Commit-reveal scheme prevents copying exact data
- Economic incentives favor original submitters
- Multiple submissions allowed, rewards shared

## Design Limitations

### 1. Non-Upgradeable Contract

**Limitation**: Contract cannot be upgraded after deployment  
**Rationale**: Security and immutability prioritized  
**Impact**: New features require new deployment  

**Alternative Approach**:
- Clear migration path documented
- State can be read from old contract
- Users must manually migrate

---

### 2. Fixed Platform Fee

**Limitation**: 5% platform fee is hardcoded  
**Rationale**: Simplicity and predictability  
**Impact**: Cannot adjust for market conditions  

**Future Consideration**:
- V2 may implement adjustable fees
- Governance mechanism could control fees
- Current fee competitive with alternatives

---

### 3. Single Arbitrator System

**Limitation**: Uses single arbitrator address  
**Rationale**: Simplicity for v1.0  
**Impact**: Centralization point  

**Planned Improvement**:
- Different arbitrator mechanisms planned for future versions

## Edge Cases

### 1. Equal Reveal Timestamps

**Scenario**: Multiple reveals in same block  
**Behavior**: All receive equal rewards  
**Impact**: Negligible  

---

### 2. Minimum Incentive Amounts

**Scenario**: Very small incentive amounts  
**Behavior**: Incentives can be as small as 1 wei  
**Impact**: Platform fee (5%) calculated accordingly  
**Note**: Extremely small incentives may not be economically viable due to gas costs

---

### 3. Blob Data Expiry

**Scenario**: EIP-4844 blob data expires after ~18 days  
**Behavior**: Expected and by design  
**Impact**: Only blob hashes are stored on-chain permanently  
**Note**: Blob data expiry is intentional for EIP-4844 efficiency

## Security Considerations

### 1. Admin Key Management

**Risk**: Admin functions allow pausing and configuration  
**Mitigation**: Multi-sig wallet required  
**Recommendation**: Use time-lock for admin actions  
**Details**: See ADMIN_FUNCTIONS.md for full admin capabilities

---

### 2. Reality.eth Finalization

**Risk**: Dependency on external protocol finalization  
**Mitigation**: Well-tested integration patterns  
**Status**: Standard Reality.eth integration implemented  

## Performance Considerations

### 1. Query Performance

**Note**: All queries are handled via subgraph indexing  
**On-chain**: Direct contract queries available but not primary method  
**Recommendation**: Use subgraph for all data queries  

---

### 2. Storage Growth

**Consideration**: Specs array grows over time  
**Impact**: Not relevant for subgraph queries  
**Note**: On-chain storage is append-only by design  

## Compatibility Notes

### 1. EVM Compatibility

**Requirement**: EVM-compatible chains only  
**Tested On**: Ethereum, Sepolia  
**Not Compatible**: Non-EVM chains (Bitcoin, Solana)  

---

### 2. Wallet Compatibility

**Supported**: All standard Ethereum wallets  
**Special Requirements**: None  
**Hardware Wallets**: Fully compatible  

---

### 3. Tool Compatibility

**Verified With**:
- Etherscan verification ✅
- Tenderly debugging ✅
- Foundry testing ✅
- Slither analysis ✅
- Mythril analysis ✅

## Behavioral Quirks

### 1. Commitment Expiry

**Behavior**: Commitments expire after 1 hour  
**User Impact**: Must reveal within window  
**No Recovery**: Expired commitments lost  

---

### 2. Reality.eth Finalization

**Behavior**: 48-hour default timeout  
**User Impact**: Rewards delayed by timeout  
**Override**: No early finalization possible  

---

### 3. Clawback Period

**Behavior**: 90-day wait for incentive clawback  
**User Impact**: Funds locked for creators  
**Rationale**: Gives ample time for submissions  

## Accepted Risks

The following risks have been evaluated and accepted:

1. **External Protocol Dependency**: Reality.eth
2. **Fixed Parameters**: Platform fee, timeouts
3. **No Upgrade Path**: Immutable deployment
4. **Timestamp Dependence**: For long time windows

## Support and Reporting

### Reporting New Issues

**GitHub**: https://github.com/kaisign/v1-core/issues  
**Response Time**: 24-48 hours  

### Severity Classification

- **Critical**: Funds at risk, system halt
- **High**: Significant functionality impact
- **Medium**: Minor functionality impact
- **Low**: Cosmetic or theoretical issues

## Changelog

### v1.0.0 (Current)
- Initial release
- All issues documented
- Ready for audit

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-09-07  
**Status**: READY FOR AUDIT  

## Disclaimer

This document represents the current known state of the system. Additional issues may be discovered during audit or production use. The development team commits to addressing critical issues and maintaining this documentation.