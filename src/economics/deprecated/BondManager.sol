// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BondManager
 * @notice Bond escalation system for KaiSign attestations (Reality.eth-style)
 * @dev Dual-mode: ETH (Phase 1) or bToken (Phase 2)
 *
 * Bond Escalation:
 * - Initial proposal starts 2-day timer
 * - Anyone can post counter-bond (>= last bond) with opposite answer
 * - Each new bond resets the 2-day timer
 * - When timer expires, last answer wins
 */
contract BondManager is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========
    error BelowMinBond();
    error AlreadyProposed();
    error NotProposed();
    error AlreadyFinalized();
    error Unauthorized();
    error UsePostBondToken();
    error UsePostBondETH();
    error TransferFailed();
    error MustMatchOrExceedLastBond();
    error ChallengePeriodActive();

    // ========== CONSTANTS ==========
    uint64 public constant CHALLENGE_PERIOD = 2 days;

    // ========== STATE ==========
    address public immutable registry;
    address public immutable treasury;
    IERC20 public bondToken;
    uint256 public minBond;

    // ========== ESCALATION STATE ==========
    struct EscalationState {
        uint256 approveTotal;
        uint256 rejectTotal;
        uint256 lastBondAmount;
        bool lastAnswer;           // true = approve, false = reject
        uint64 lastBondTime;
        bool finalized;
    }

    mapping(bytes32 => EscalationState) public escalations;
    mapping(bytes32 => mapping(address => uint256)) public userApproveBonds;
    mapping(bytes32 => mapping(address => uint256)) public userRejectBonds;
    mapping(bytes32 => address[]) public approveVoters;
    mapping(bytes32 => address[]) public rejectVoters;
    mapping(bytes32 => mapping(address => bool)) private _hasVotedApprove;
    mapping(bytes32 => mapping(address => bool)) private _hasVotedReject;

    // ========== REVOKE ESCALATION ==========
    struct RevokeEscalation {
        uint256 revokeTotal;
        uint256 keepTotal;
        uint256 lastBondAmount;
        bool lastAnswer;           // true = revoke, false = keep
        uint64 lastBondTime;
        bool finalized;
    }

    mapping(bytes32 => RevokeEscalation) public revokeEscalations;
    mapping(bytes32 => mapping(address => uint256)) public userRevokeBonds;
    mapping(bytes32 => mapping(address => uint256)) public userKeepBonds;
    mapping(bytes32 => address[]) public revokeVoters;
    mapping(bytes32 => address[]) public keepVoters;
    mapping(bytes32 => mapping(address => bool)) private _hasVotedRevoke;
    mapping(bytes32 => mapping(address => bool)) private _hasVotedKeep;

    // ========== EVENTS ==========
    event BondPosted(bytes32 indexed uid, address indexed voter, uint256 amount, bool approve);
    event RevokeBondPosted(bytes32 indexed uid, address indexed voter, uint256 amount, bool revoke);
    event BondTokenSet(address indexed token);
    event MinBondSet(uint256 minBond);
    event Settled(bytes32 indexed uid, bool approved);
    event RevokeSettled(bytes32 indexed uid, bool revoked);

    // ========== CONSTRUCTOR ==========
    constructor(
        address _registry,
        address _treasury,
        uint256 _minBond,
        address _initialOwner
    ) {
        require(_registry != address(0), "Invalid registry");
        require(_treasury != address(0), "Invalid treasury");

        registry = _registry;
        treasury = _treasury;
        minBond = _minBond;

        if (_initialOwner != msg.sender) {
            _transferOwnership(_initialOwner);
        }
    }

    // ========== ADMIN ==========

    function setBondToken(address _bondToken) external onlyOwner {
        bondToken = IERC20(_bondToken);
        emit BondTokenSet(_bondToken);
    }

    function setMinBond(uint256 _minBond) external onlyOwner {
        minBond = _minBond;
        emit MinBondSet(_minBond);
    }

    // ========== PROPOSE (Initial Bond) ==========

    /**
     * @notice Post initial approval bond for an attestation
     * @param uid The attestation UID
     */
    function propose(bytes32 uid) external payable nonReentrant {
        if (address(bondToken) != address(0)) revert UsePostBondToken();
        if (escalations[uid].lastBondTime != 0) revert AlreadyProposed();
        if (msg.value < minBond) revert BelowMinBond();

        escalations[uid] = EscalationState({
            approveTotal: msg.value,
            rejectTotal: 0,
            lastBondAmount: msg.value,
            lastAnswer: true,
            lastBondTime: uint64(block.timestamp),
            finalized: false
        });

        userApproveBonds[uid][msg.sender] += msg.value;
        if (!_hasVotedApprove[uid][msg.sender]) {
            _hasVotedApprove[uid][msg.sender] = true;
            approveVoters[uid].push(msg.sender);
        }

        emit BondPosted(uid, msg.sender, msg.value, true);
    }

    function proposeToken(bytes32 uid, uint256 amount) external nonReentrant {
        if (address(bondToken) == address(0)) revert UsePostBondETH();
        if (escalations[uid].lastBondTime != 0) revert AlreadyProposed();
        if (amount < minBond) revert BelowMinBond();

        bondToken.safeTransferFrom(msg.sender, address(this), amount);

        escalations[uid] = EscalationState({
            approveTotal: amount,
            rejectTotal: 0,
            lastBondAmount: amount,
            lastAnswer: true,
            lastBondTime: uint64(block.timestamp),
            finalized: false
        });

        userApproveBonds[uid][msg.sender] += amount;
        if (!_hasVotedApprove[uid][msg.sender]) {
            _hasVotedApprove[uid][msg.sender] = true;
            approveVoters[uid].push(msg.sender);
        }

        emit BondPosted(uid, msg.sender, amount, true);
    }

    // ========== POST BOND (Escalation) ==========

    /**
     * @notice Post counter-bond to escalate
     * @param uid The attestation UID
     * @param approve True to approve, false to reject
     */
    function postBond(bytes32 uid, bool approve) external payable nonReentrant {
        if (address(bondToken) != address(0)) revert UsePostBondToken();

        EscalationState storage state = escalations[uid];
        if (state.lastBondTime == 0) revert NotProposed();
        if (state.finalized) revert AlreadyFinalized();
        if (msg.value < state.lastBondAmount) revert MustMatchOrExceedLastBond();
        if (msg.value < minBond) revert BelowMinBond();

        if (approve) {
            state.approveTotal += msg.value;
            userApproveBonds[uid][msg.sender] += msg.value;
            if (!_hasVotedApprove[uid][msg.sender]) {
                _hasVotedApprove[uid][msg.sender] = true;
                approveVoters[uid].push(msg.sender);
            }
        } else {
            state.rejectTotal += msg.value;
            userRejectBonds[uid][msg.sender] += msg.value;
            if (!_hasVotedReject[uid][msg.sender]) {
                _hasVotedReject[uid][msg.sender] = true;
                rejectVoters[uid].push(msg.sender);
            }
        }

        state.lastBondAmount = msg.value;
        state.lastAnswer = approve;
        state.lastBondTime = uint64(block.timestamp);

        emit BondPosted(uid, msg.sender, msg.value, approve);
    }

    function postBondToken(bytes32 uid, uint256 amount, bool approve) external nonReentrant {
        if (address(bondToken) == address(0)) revert UsePostBondETH();

        EscalationState storage state = escalations[uid];
        if (state.lastBondTime == 0) revert NotProposed();
        if (state.finalized) revert AlreadyFinalized();
        if (amount < state.lastBondAmount) revert MustMatchOrExceedLastBond();
        if (amount < minBond) revert BelowMinBond();

        bondToken.safeTransferFrom(msg.sender, address(this), amount);

        if (approve) {
            state.approveTotal += amount;
            userApproveBonds[uid][msg.sender] += amount;
            if (!_hasVotedApprove[uid][msg.sender]) {
                _hasVotedApprove[uid][msg.sender] = true;
                approveVoters[uid].push(msg.sender);
            }
        } else {
            state.rejectTotal += amount;
            userRejectBonds[uid][msg.sender] += amount;
            if (!_hasVotedReject[uid][msg.sender]) {
                _hasVotedReject[uid][msg.sender] = true;
                rejectVoters[uid].push(msg.sender);
            }
        }

        state.lastBondAmount = amount;
        state.lastAnswer = approve;
        state.lastBondTime = uint64(block.timestamp);

        emit BondPosted(uid, msg.sender, amount, approve);
    }

    // ========== QUERIES ==========

    function canFinalize(bytes32 uid) public view returns (bool) {
        EscalationState storage state = escalations[uid];
        if (state.lastBondTime == 0 || state.finalized) return false;
        return block.timestamp >= state.lastBondTime + CHALLENGE_PERIOD;
    }

    function getCurrentAnswer(bytes32 uid) public view returns (bool) {
        return escalations[uid].lastAnswer;
    }

    function tally(bytes32 uid) external view returns (uint256 approveWeight, uint256 rejectWeight) {
        EscalationState storage state = escalations[uid];
        return (state.approveTotal, state.rejectTotal);
    }

    // ========== SETTLEMENT (Called by Registry) ==========

    function settleApproved(bytes32 uid) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        EscalationState storage state = escalations[uid];
        if (state.finalized) revert AlreadyFinalized();

        state.finalized = true;

        uint256 slashedPool = state.rejectTotal;
        uint256 approveTotal = state.approveTotal;

        // Return approve bonds + distribute slashed reject bonds (no treasury cut on bonds)
        _distributeWinnings(uid, true, approveTotal, slashedPool);

        emit Settled(uid, true);
    }

    function settleRejected(bytes32 uid) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        EscalationState storage state = escalations[uid];
        if (state.finalized) revert AlreadyFinalized();

        state.finalized = true;

        uint256 slashedPool = state.approveTotal;
        uint256 rejectTotal = state.rejectTotal;

        // Return reject bonds + distribute slashed approve bonds (no treasury cut on bonds)
        _distributeWinnings(uid, false, rejectTotal, slashedPool);

        emit Settled(uid, false);
    }

    function _distributeWinnings(
        bytes32 uid,
        bool winnersApproved,
        uint256 winnerTotal,
        uint256 slashedPool
    ) internal {
        if (winnerTotal == 0) return;

        // Get list of winners and their bonds
        address[] storage winners = winnersApproved ? approveVoters[uid] : rejectVoters[uid];

        if (winners.length == 0) return;

        // Distribute proportionally: each winner gets (their bond / winnerTotal) * totalPayout
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 userBond = winnersApproved
                ? userApproveBonds[uid][winner]
                : userRejectBonds[uid][winner];

            if (userBond == 0) continue;

            // Calculate share: (userBond * (winnerTotal + slashedPool)) / winnerTotal
            uint256 share = (userBond * (winnerTotal + slashedPool)) / winnerTotal;

            if (address(bondToken) == address(0)) {
                // ETH mode
                (bool success, ) = payable(winner).call{value: share}("");
                if (!success) revert TransferFailed();
            } else {
                // Token mode
                bondToken.safeTransfer(winner, share);
            }
        }
    }

    // ========== REVOKE ESCALATION ==========

    function proposeRevoke(bytes32 uid) external payable nonReentrant {
        if (address(bondToken) != address(0)) revert UsePostBondToken();
        if (revokeEscalations[uid].lastBondTime != 0) revert AlreadyProposed();
        if (msg.value < minBond) revert BelowMinBond();

        revokeEscalations[uid] = RevokeEscalation({
            revokeTotal: msg.value,
            keepTotal: 0,
            lastBondAmount: msg.value,
            lastAnswer: true,
            lastBondTime: uint64(block.timestamp),
            finalized: false
        });

        userRevokeBonds[uid][msg.sender] += msg.value;
        if (!_hasVotedRevoke[uid][msg.sender]) {
            _hasVotedRevoke[uid][msg.sender] = true;
            revokeVoters[uid].push(msg.sender);
        }

        emit RevokeBondPosted(uid, msg.sender, msg.value, true);
    }

    function postRevokeBond(bytes32 uid, bool revoke) external payable nonReentrant {
        if (address(bondToken) != address(0)) revert UsePostBondToken();

        RevokeEscalation storage state = revokeEscalations[uid];
        if (state.lastBondTime == 0) revert NotProposed();
        if (state.finalized) revert AlreadyFinalized();
        if (msg.value < state.lastBondAmount) revert MustMatchOrExceedLastBond();
        if (msg.value < minBond) revert BelowMinBond();

        if (revoke) {
            state.revokeTotal += msg.value;
            userRevokeBonds[uid][msg.sender] += msg.value;
            if (!_hasVotedRevoke[uid][msg.sender]) {
                _hasVotedRevoke[uid][msg.sender] = true;
                revokeVoters[uid].push(msg.sender);
            }
        } else {
            state.keepTotal += msg.value;
            userKeepBonds[uid][msg.sender] += msg.value;
            if (!_hasVotedKeep[uid][msg.sender]) {
                _hasVotedKeep[uid][msg.sender] = true;
                keepVoters[uid].push(msg.sender);
            }
        }

        state.lastBondAmount = msg.value;
        state.lastAnswer = revoke;
        state.lastBondTime = uint64(block.timestamp);

        emit RevokeBondPosted(uid, msg.sender, msg.value, revoke);
    }

    function canFinalizeRevoke(bytes32 uid) public view returns (bool) {
        RevokeEscalation storage state = revokeEscalations[uid];
        if (state.lastBondTime == 0 || state.finalized) return false;
        return block.timestamp >= state.lastBondTime + CHALLENGE_PERIOD;
    }

    function getRevokeAnswer(bytes32 uid) public view returns (bool) {
        return revokeEscalations[uid].lastAnswer;
    }

    function settleRevokeApproved(bytes32 uid) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        RevokeEscalation storage state = revokeEscalations[uid];
        if (state.finalized) revert AlreadyFinalized();

        state.finalized = true;

        // Revoke approved: revokeVoters win, keepVoters lose
        _distributeRevokeWinnings(uid, true, state.revokeTotal, state.keepTotal);

        emit RevokeSettled(uid, true);
    }

    function settleRevokeRejected(bytes32 uid) external nonReentrant {
        if (msg.sender != registry) revert Unauthorized();

        RevokeEscalation storage state = revokeEscalations[uid];
        if (state.finalized) revert AlreadyFinalized();

        state.finalized = true;

        // Revoke rejected: keepVoters win, revokeVoters lose
        _distributeRevokeWinnings(uid, false, state.keepTotal, state.revokeTotal);

        emit RevokeSettled(uid, false);
    }

    function _distributeRevokeWinnings(
        bytes32 uid,
        bool revokeWon,
        uint256 winnerTotal,
        uint256 slashedPool
    ) internal {
        if (winnerTotal == 0) return;

        // Get list of winners and their bonds
        address[] storage winners = revokeWon ? revokeVoters[uid] : keepVoters[uid];

        if (winners.length == 0) return;

        // Distribute proportionally: each winner gets (their bond / winnerTotal) * totalPayout
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 userBond = revokeWon
                ? userRevokeBonds[uid][winner]
                : userKeepBonds[uid][winner];

            if (userBond == 0) continue;

            // Calculate share: (userBond * (winnerTotal + slashedPool)) / winnerTotal
            uint256 share = (userBond * (winnerTotal + slashedPool)) / winnerTotal;

            if (address(bondToken) == address(0)) {
                // ETH mode
                (bool success, ) = payable(winner).call{value: share}("");
                if (!success) revert TransferFailed();
            } else {
                // Token mode
                bondToken.safeTransfer(winner, share);
            }
        }
    }

    // ========== EMERGENCY ==========

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    // ========== RECEIVE ==========
    receive() external payable {}
}
