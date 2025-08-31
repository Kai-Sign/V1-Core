// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title BlobAccount
 * @notice ERC-4337 Smart Account that can request blob posting through UserOps
 * @dev Deployed on Sepolia for each user to enable blob transactions via UserOps
 */
contract BlobAccount is BaseAccount, Initializable {
    using ECDSA for bytes32;

    address public owner;
    IEntryPoint private immutable _entryPoint;
    
    // Blob posting requests
    struct BlobRequest {
        bytes32 dataHash;
        bytes32 blobHash;
        uint256 timestamp;
        bool posted;
    }
    
    mapping(uint256 => BlobRequest) public blobRequests;
    uint256 public blobRequestCount;
    
    // Events
    event BlobRequested(uint256 indexed requestId, bytes32 dataHash, address requester);
    event BlobPosted(uint256 indexed requestId, bytes32 blobHash, bytes32 txHash);
    event ReceivedEther(address indexed sender, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == address(this), "Only owner");
        _;
    }

    constructor(IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
        _disableInitializers();
    }

    function initialize(address anOwner) public initializer {
        owner = anOwner;
    }

    /**
     * @notice Request a blob to be posted
     * @param dataHash Hash of the data to be posted as a blob
     * @return requestId The ID of the blob request
     */
    function requestBlobPost(bytes32 dataHash) external onlyOwner returns (uint256 requestId) {
        requestId = blobRequestCount++;
        
        blobRequests[requestId] = BlobRequest({
            dataHash: dataHash,
            blobHash: bytes32(0),
            timestamp: block.timestamp,
            posted: false
        });
        
        emit BlobRequested(requestId, dataHash, owner);
    }

    /**
     * @notice Confirm that a blob was posted (called by bundler)
     * @param requestId The request that was fulfilled
     * @param blobHash The versioned hash of the posted blob
     * @param txHash Transaction hash of the blob transaction
     */
    function confirmBlobPost(
        uint256 requestId,
        bytes32 blobHash,
        bytes32 txHash
    ) external {
        // Only bundler or owner can confirm
        require(
            msg.sender == owner || 
            msg.sender == address(this) ||
            msg.sender == address(entryPoint()),
            "Unauthorized"
        );
        
        BlobRequest storage request = blobRequests[requestId];
        require(request.timestamp > 0, "Invalid request");
        require(!request.posted, "Already posted");
        
        request.blobHash = blobHash;
        request.posted = true;
        
        emit BlobPosted(requestId, blobHash, txHash);
    }

    /**
     * @notice Execute a transaction (called by EntryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * @notice Execute a batch of transactions
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "Length mismatch");
        
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * @notice Validate user's signature and nonce
     */
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal override returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address recovered = hash.recover(userOp.signature);
        
        if (recovered != owner) {
            return SIG_VALIDATION_FAILED;
        }
        return 0;
    }

    /**
     * @notice Get the EntryPoint address
     */
    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    /**
     * @notice Internal call helper
     */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @notice Check if caller is EntryPoint or owner
     */
    function _requireFromEntryPointOrOwner() internal view {
        require(
            msg.sender == address(entryPoint()) || msg.sender == owner,
            "Not EntryPoint or owner"
        );
    }

    /**
     * @notice Deposit ETH to EntryPoint for gas
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /**
     * @notice Get deposit balance in EntryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * @notice Withdraw deposit from EntryPoint
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}