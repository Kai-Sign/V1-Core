# Interface Specification - KaiSign v1.0.0

## Contract Interface

### Public State Variables

#### Constants
```solidity
string public constant VERSION = "1.0.0"
uint256 public constant PLATFORM_FEE_PERCENT = 5
uint256 public constant COMMIT_REVEAL_TIMEOUT = 1 hours
uint256 public constant INCENTIVE_DURATION = 30 days
uint256 public constant INCENTIVE_CLAWBACK_PERIOD = 90 days
uint32 public constant DEFAULT_TIMEOUT = 48 hours
```

#### Immutable Variables
```solidity
address public immutable realityETH
address public immutable arbitrator
```

#### Configuration Variables
```solidity
uint256 public minBond
uint256 public totalSpecs
```

## Core Functions

### Spec Management

#### proposeSpec
```solidity
function proposeSpec(
    address contractAddress,
    uint256 chainId
) external payable whenNotPaused returns (bytes32 questionId)
```

**Description**: Propose a new specification for a contract  
**Access**: Public  
**Parameters**:
- `contractAddress`: The contract address to add specs for
- `chainId`: The chain ID where the contract is deployed

**Requirements**:
- Contract not paused
- `msg.value >= minBond`
- Contract not already proposed
- Valid contract address (not zero)
- Valid chain ID (not zero)

**Returns**: `questionId` - Reality.eth question identifier

**Events Emitted**:
```solidity
event SpecProposed(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed proposer,
    bytes32 questionId,
    uint256 bond
)
```

#### commitSpec
```solidity
function commitSpec(
    address contractAddress,
    uint256 chainId,
    bytes32 commitment
) external whenNotPaused
```

**Description**: Commit a hidden specification hash  
**Access**: Public  
**Parameters**:
- `contractAddress`: The contract address
- `chainId`: The chain ID
- `commitment`: Hash of (blobHash, nonce)

**Requirements**:
- Contract not paused
- Contract must be proposed
- No existing commitment from sender
- Valid commitment (not zero)

**Events Emitted**:
```solidity
event SpecCommitted(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed committer,
    bytes32 commitment
)
```

#### revealSpec
```solidity
function revealSpec(
    address contractAddress,
    uint256 chainId,
    bytes32 blobHash,
    uint256 nonce
) external whenNotPaused nonReentrant returns (uint256 specId)
```

**Description**: Reveal a previously committed specification  
**Access**: Public  
**Parameters**:
- `contractAddress`: The contract address
- `chainId`: The chain ID
- `blobHash`: The blob hash containing spec data
- `nonce`: The nonce used in commitment

**Requirements**:
- Contract not paused
- No reentrancy
- Valid commitment exists
- Correct hash match: `keccak256(abi.encode(blobHash, nonce)) == commitment`
- Not already revealed
- Within reveal timeout period

**Returns**: `specId` - Unique identifier for the specification

**Events Emitted**:
```solidity
event SpecRevealed(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed revealer,
    bytes32 blobHash,
    uint256 specId
)
```

### Incentive System

#### createIncentive
```solidity
function createIncentive(
    address contractAddress,
    uint256 chainId,
    uint256 deadline
) external payable whenNotPaused nonReentrant
```

**Description**: Create an incentive pool for specifications  
**Access**: Public  
**Parameters**:
- `contractAddress`: Target contract address
- `chainId`: Target chain ID
- `deadline`: Deadline for claiming incentive

**Requirements**:
- Contract not paused
- No reentrancy
- `msg.value > 0`
- `deadline > block.timestamp`
- `deadline <= block.timestamp + INCENTIVE_DURATION`
- Valid contract and chain ID

**Events Emitted**:
```solidity
event IncentiveCreated(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed creator,
    uint256 amount,
    uint256 deadline
)
```

#### clawbackIncentive
```solidity
function clawbackIncentive(
    address contractAddress,
    uint256 chainId
) external whenNotPaused nonReentrant
```

**Description**: Reclaim unclaimed incentive after clawback period  
**Access**: Incentive creator only  
**Parameters**:
- `contractAddress`: Contract address
- `chainId`: Chain ID

**Requirements**:
- Contract not paused
- No reentrancy
- Caller must be incentive creator
- Clawback period must have passed
- Incentive pool must have remaining funds

**Events Emitted**:
```solidity
event IncentiveClawback(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed creator,
    uint256 amount
)
```

### Reality.eth Integration

#### handleResult
```solidity
function handleResult(
    bytes32 questionId,
    bytes32 answer
) external
```

**Description**: Handle Reality.eth question finalization  
**Access**: Reality.eth contract only  
**Parameters**:
- `questionId`: The Reality.eth question ID
- `answer`: The finalized answer (0x0...01 for accepted)

**Requirements**:
- Caller must be Reality.eth contract
- Question must exist in system
- Question not already settled

**Events Emitted**:
```solidity
event SpecAccepted(bytes32 indexed questionId)
// or
event SpecRejected(bytes32 indexed questionId)

event IncentiveClaimed(
    address indexed contractAddress,
    uint256 indexed chainId,
    address indexed claimer,
    uint256 amount
)
```

### Admin Functions

#### setMinBond
```solidity
function setMinBond(uint256 newMinBond) external onlyRole(ADMIN_ROLE)
```

**Description**: Update minimum bond requirement  
**Access**: Admin only  
**Parameters**:
- `newMinBond`: New minimum bond amount in wei

**Requirements**:
- Caller must have ADMIN_ROLE
- `newMinBond > 0`

**Events Emitted**:
```solidity
event MinBondUpdated(uint256 oldMinBond, uint256 newMinBond)
```

#### pause
```solidity
function pause() external onlyRole(ADMIN_ROLE)
```

**Description**: Pause contract operations  
**Access**: Admin only  

**Events Emitted**:
```solidity
event Paused(address account)
```

#### unpause
```solidity
function unpause() external onlyRole(ADMIN_ROLE)
```

**Description**: Resume contract operations  
**Access**: Admin only  

**Events Emitted**:
```solidity
event Unpaused(address account)
```

## View Functions

### getContractKey
```solidity
function getContractKey(
    address contractAddress,
    uint256 chainId
) public pure returns (bytes32)
```

**Description**: Generate unique key for contract/chain combination  
**Returns**: Keccak256 hash of encoded parameters

### getSpecsByContract
```solidity
function getSpecsByContract(
    address contractAddress,
    uint256 chainId
) external view returns (Spec[] memory)
```

**Description**: Get all specifications for a contract  
**Returns**: Array of Spec structs

### getSpecsByContractPaginated
```solidity
function getSpecsByContractPaginated(
    address contractAddress,
    uint256 chainId,
    uint256 offset,
    uint256 limit
) external view returns (Spec[] memory specs, uint256 total)
```

**Description**: Get paginated specifications  
**Parameters**:
- `offset`: Starting index
- `limit`: Maximum number of results

**Returns**: 
- `specs`: Array of specifications
- `total`: Total count available

### getContractSpecCount
```solidity
function getContractSpecCount(
    address contractAddress,
    uint256 chainId
) external view returns (uint256)
```

**Description**: Get count of specifications for a contract  
**Returns**: Number of specifications

### getSpecBlobHash
```solidity
function getSpecBlobHash(uint256 specId) external view returns (bytes32)
```

**Description**: Get blob hash for a specific spec ID  
**Returns**: Blob hash or 0x0 if not found

### getIncentivePool
```solidity
function getIncentivePool(
    address contractAddress,
    uint256 chainId
) external view returns (uint256 totalAmount, uint256 remainingAmount)
```

**Description**: Get incentive pool information  
**Returns**:
- `totalAmount`: Total incentives created
- `remainingAmount`: Unclaimed incentives

### getUserIncentives
```solidity
function getUserIncentives(
    address user
) external view returns (UserIncentive[] memory)
```

**Description**: Get all incentives created by a user  
**Returns**: Array of UserIncentive structs

## Data Structures

### Spec
```solidity
struct Spec {
    address submitter;      // Address that revealed the spec
    bytes32 blobHash;      // EIP-4844 blob hash
    uint256 timestamp;     // Submission timestamp
    bool accepted;         // Acceptance status
}
```

### ProposedContract
```solidity
struct ProposedContract {
    address proposer;      // Address that proposed
    bytes32 questionId;    // Reality.eth question ID
    uint256 bond;          // Bond amount
    uint256 proposalTime;  // Proposal timestamp
    bool settled;          // Settlement status
}
```

### Commitment
```solidity
struct Commitment {
    bytes32 hash;          // Commitment hash
    uint256 timestamp;     // Commit timestamp
    bool revealed;         // Reveal status
}
```

### Incentive
```solidity
struct Incentive {
    address creator;       // Incentive creator
    uint256 totalAmount;   // Total incentive amount
    uint256 remainingAmount; // Unclaimed amount
    uint256 deadline;      // Claim deadline
    uint256 createdAt;     // Creation timestamp
}
```

## Error Codes

```solidity
error AlreadyProposed()           // Contract already has active proposal
error NotProposed()               // Contract not proposed
error InsufficientBond()          // Bond below minimum
error InsufficientIncentive()     // Zero incentive amount
error InvalidContract()           // Invalid contract address
error ContractNotFound()          // Contract not in system
error CommitmentNotFound()        // No commitment from sender
error CommitmentExpired()         // Reveal period expired
error CommitmentAlreadyRevealed() // Already revealed
error InvalidReveal()             // Hash mismatch
error NotFinalized()              // Reality.eth not finalized
error AlreadySettled()            // Question already settled
error NoIncentiveToClaim()        // No incentive available
error IncentiveExpired()          // Past deadline
error Unauthorized()              // Caller not authorized
error ClawbackTooEarly()          // Clawback period not reached
```

## Integration Examples

### JavaScript/ethers.js
```javascript
const KaiSign = await ethers.getContractAt("KaiSign", KAISIGN_ADDRESS);

// Propose a spec
const bond = ethers.utils.parseEther("0.01");
const tx = await KaiSign.proposeSpec(
    "0x...", // contract address
    1,       // mainnet chain ID
    { value: bond }
);

// Commit a spec
const blobHash = "0x...";
const nonce = ethers.BigNumber.from(ethers.utils.randomBytes(32));
const commitment = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
        ["bytes32", "uint256"],
        [blobHash, nonce]
    )
);
await KaiSign.commitSpec(contractAddress, chainId, commitment);

// Reveal after committing
await KaiSign.revealSpec(contractAddress, chainId, blobHash, nonce);
```

### Solidity Integration
```solidity
interface IKaiSign {
    function getSpecsByContract(
        address contractAddress,
        uint256 chainId
    ) external view returns (Spec[] memory);
}

contract IntegrationExample {
    IKaiSign public kaisign;
    
    function checkSpecs(address target) external view {
        IKaiSign.Spec[] memory specs = kaisign.getSpecsByContract(
            target,
            block.chainid
        );
        
        for (uint i = 0; i < specs.length; i++) {
            if (specs[i].accepted) {
                // Use accepted spec
                bytes32 blobHash = specs[i].blobHash;
                // Fetch blob data and use for clear signing
            }
        }
    }
}
```