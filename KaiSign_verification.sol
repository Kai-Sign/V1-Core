// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0 ^0.8.20 ^0.8.6;

// lib/openzeppelin-contracts/contracts/access/IAccessControl.sol

// OpenZeppelin Contracts v4.4.1 (access/IAccessControl.sol)

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}

// lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v4.9.4) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result << 3) < value ? 1 : 0);
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SignedMath.sol)

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int256 a, int256 b) internal pure returns (int256) {
        // Formula from the book "Hacker's Delight"
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}

// staticlib/RealityETH-3.0.sol

contract BalanceHolder {

    mapping(address => uint256) public balanceOf;

    event LogWithdraw(
        address indexed user,
        uint256 amount
    );

    function withdraw() 
    public {
        uint256 bal = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;
        payable(msg.sender).transfer(bal);
        emit LogWithdraw(msg.sender, bal);
    }

}

contract RealityETH_v3_0 is BalanceHolder {

    address constant NULL_ADDRESS = address(0);

    // History hash when no history is created, or history has been cleared
    bytes32 constant NULL_HASH = bytes32(0);

    // An unitinalized finalize_ts for a question will indicate an unanswered question.
    uint32 constant UNANSWERED = 0;

    // An unanswered reveal_ts for a commitment will indicate that it does not exist.
    uint256 constant COMMITMENT_NON_EXISTENT = 0;

    // Commit->reveal timeout is 1/8 of the question timeout (rounded down).
    uint32 constant COMMITMENT_TIMEOUT_RATIO = 8;

    // Proportion withheld when you claim an earlier bond.
    uint256 constant BOND_CLAIM_FEE_PROPORTION = 40; // One 40th ie 2.5%

    // Special value representing a question that was answered too soon.
    // bytes32(-2). By convention we use bytes32(-1) for "invalid", although the contract does not handle this.
    bytes32 constant UNRESOLVED_ANSWER = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;

    event LogSetQuestionFee(
        address arbitrator,
        uint256 amount
    );

    event LogNewTemplate(
        uint256 indexed template_id,
        address indexed user, 
        string question_text
    );

    event LogNewQuestion(
        bytes32 indexed question_id,
        address indexed user, 
        uint256 template_id,
        string question,
        bytes32 indexed content_hash,
        address arbitrator, 
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 created
    );

    event LogMinimumBond(
        bytes32 indexed question_id,
        uint256 min_bond
    );

    event LogFundAnswerBounty(
        bytes32 indexed question_id,
        uint256 bounty_added,
        uint256 bounty,
        address indexed user 
    );

    event LogNewAnswer(
        bytes32 answer,
        bytes32 indexed question_id,
        bytes32 history_hash,
        address indexed user,
        uint256 bond,
        uint256 ts,
        bool is_commitment
    );

    event LogAnswerReveal(
        bytes32 indexed question_id, 
        address indexed user, 
        bytes32 indexed answer_hash, 
        bytes32 answer, 
        uint256 nonce, 
        uint256 bond
    );

    event LogNotifyOfArbitrationRequest(
        bytes32 indexed question_id,
        address indexed user 
    );

    event LogCancelArbitration(
        bytes32 indexed question_id
    );

    event LogFinalize(
        bytes32 indexed question_id,
        bytes32 indexed answer
    );

    event LogClaim(
        bytes32 indexed question_id,
        address indexed user,
        uint256 amount
    );

    event LogReopenQuestion(
        bytes32 indexed question_id,
        bytes32 indexed reopened_question_id
    );

    struct Question {
        bytes32 content_hash;
        address arbitrator;
        uint32 opening_ts;
        uint32 timeout;
        uint32 finalize_ts;
        bool is_pending_arbitration;
        uint256 bounty;
        bytes32 best_answer;
        bytes32 history_hash;
        uint256 bond;
        uint256 min_bond;
    }

    // Stored in a mapping indexed by commitment_id, a hash of commitment hash, question, bond. 
    struct Commitment {
        uint32 reveal_ts;
        bool is_revealed;
        bytes32 revealed_answer;
    }

    // Only used when claiming more bonds than fits into a transaction
    // Stored in a mapping indexed by question_id.
    struct Claim {
        address payee;
        uint256 last_bond;
        uint256 queued_funds;
    }

    uint256 nextTemplateID = 0;
    mapping(uint256 => uint256) public templates;
    mapping(uint256 => bytes32) public template_hashes;
    mapping(bytes32 => Question) public questions;
    mapping(bytes32 => Claim) public question_claims;
    mapping(bytes32 => Commitment) public commitments;
    mapping(address => uint256) public arbitrator_question_fees; 
    mapping(bytes32 => bytes32) public reopened_questions;
    mapping(bytes32 => bool) public reopener_questions;

    modifier onlyArbitrator(bytes32 question_id) {
        require(msg.sender == questions[question_id].arbitrator, "msg.sender must be arbitrator");
        _;
    }

    modifier stateAny() {
        _;
    }

    modifier stateNotCreated(bytes32 question_id) {
        require(questions[question_id].timeout == 0, "question must not exist");
        _;
    }

    modifier stateOpen(bytes32 question_id) {
        require(questions[question_id].timeout > 0, "question must exist");
        require(!questions[question_id].is_pending_arbitration, "question must not be pending arbitration");
        uint32 finalize_ts = questions[question_id].finalize_ts;
        require(finalize_ts == UNANSWERED || finalize_ts > uint32(block.timestamp), "finalization deadline must not have passed");
        uint32 opening_ts = questions[question_id].opening_ts;
        require(opening_ts == 0 || opening_ts <= uint32(block.timestamp), "opening date must have passed"); 
        _;
    }

    modifier statePendingArbitration(bytes32 question_id) {
        require(questions[question_id].is_pending_arbitration, "question must be pending arbitration");
        _;
    }

    modifier stateOpenOrPendingArbitration(bytes32 question_id) {
        require(questions[question_id].timeout > 0, "question must exist");
        uint32 finalize_ts = questions[question_id].finalize_ts;
        require(finalize_ts == UNANSWERED || finalize_ts > uint32(block.timestamp), "finalization dealine must not have passed");
        uint32 opening_ts = questions[question_id].opening_ts;
        require(opening_ts == 0 || opening_ts <= uint32(block.timestamp), "opening date must have passed"); 
        _;
    }

    modifier stateFinalized(bytes32 question_id) {
        require(isFinalized(question_id), "question must be finalized");
        _;
    }

    modifier bondMustDoubleAndMatchMinimum(bytes32 question_id) {
        require(msg.value > 0, "bond must be positive"); 
        uint256 current_bond = questions[question_id].bond;
        if (current_bond == 0) {
            require(msg.value >= (questions[question_id].min_bond), "bond must exceed the minimum");
        } else {
            require(msg.value >= (current_bond * 2), "bond must be double at least previous bond");
        }
        _;
    }

    modifier previousBondMustNotBeatMaxPrevious(bytes32 question_id, uint256 max_previous) {
        if (max_previous > 0) {
            require(questions[question_id].bond <= max_previous, "bond must exceed max_previous");
        }
        _;
    }

    /// @notice Constructor, sets up some initial templates
    /// @dev Creates some generalized templates for different question types used in the DApp.
    constructor() {
        createTemplate('{"title": "%s", "type": "bool", "category": "%s", "lang": "%s"}');
        createTemplate('{"title": "%s", "type": "uint", "decimals": 18, "category": "%s", "lang": "%s"}');
        createTemplate('{"title": "%s", "type": "single-select", "outcomes": [%s], "category": "%s", "lang": "%s"}');
        createTemplate('{"title": "%s", "type": "multiple-select", "outcomes": [%s], "category": "%s", "lang": "%s"}');
        createTemplate('{"title": "%s", "type": "datetime", "category": "%s", "lang": "%s"}');
    }

    /// @notice Function for arbitrator to set an optional per-question fee. 
    /// @dev The per-question fee, charged when a question is asked, is intended as an anti-spam measure.
    /// @param fee The fee to be charged by the arbitrator when a question is asked
    function setQuestionFee(uint256 fee) 
        stateAny() 
    external {
        arbitrator_question_fees[msg.sender] = fee;
        emit LogSetQuestionFee(msg.sender, fee);
    }

    /// @notice Create a reusable template, which should be a JSON document.
    /// Placeholders should use gettext() syntax, eg %s.
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param content The template content
    /// @return The ID of the newly-created template, which is created sequentially.
    function createTemplate(string memory content) 
        stateAny()
    public returns (uint256) {
        uint256 id = nextTemplateID;
        templates[id] = block.number;
        template_hashes[id] = keccak256(abi.encodePacked(content));
        emit LogNewTemplate(id, msg.sender, content);
        nextTemplateID = id + 1;
        return id;
    }

    /// @notice Create a new reusable template and use it to ask a question
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param content The template content
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param arbitrator The arbitration contract that will have the final word on the answer if there is a dispute
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @return The ID of the newly-created template, which is created sequentially.
    function createTemplateAndAskQuestion(
        string memory content, 
        string memory question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce 
    ) 
        // stateNotCreated is enforced by the internal _askQuestion
    public payable returns (bytes32) {
        uint256 template_id = createTemplate(content);
        return askQuestion(template_id, question, arbitrator, timeout, opening_ts, nonce);
    }

    /// @notice Ask a new question and return the ID
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param template_id The ID number of the template the question will use
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param arbitrator The arbitration contract that will have the final word on the answer if there is a dispute
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @return The ID of the newly-created question, created deterministically.
    function askQuestion(uint256 template_id, string memory question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce) 
        // stateNotCreated is enforced by the internal _askQuestion
    public payable returns (bytes32) {

        require(templates[template_id] > 0, "template must exist");

        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));
        bytes32 question_id = keccak256(abi.encodePacked(content_hash, arbitrator, timeout, uint256(0), address(this), msg.sender, nonce));

        // We emit this event here because _askQuestion doesn't need to know the unhashed question. Other events are emitted by _askQuestion.
        emit LogNewQuestion(question_id, msg.sender, template_id, question, content_hash, arbitrator, timeout, opening_ts, nonce, block.timestamp);
        _askQuestion(question_id, content_hash, arbitrator, timeout, opening_ts, 0);

        return question_id;
    }

    /// @notice Ask a new question and return the ID
    /// @dev Template data is only stored in the event logs, but its block number is kept in contract storage.
    /// @param template_id The ID number of the template the question will use
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param arbitrator The arbitration contract that will have the final word on the answer if there is a dispute
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @param min_bond The minimum bond that may be used for an answer.
    /// @return The ID of the newly-created question, created deterministically.
    function askQuestionWithMinBond(uint256 template_id, string memory question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce, uint256 min_bond) 
        // stateNotCreated is enforced by the internal _askQuestion
    public payable returns (bytes32) {

        require(templates[template_id] > 0, "template must exist");

        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));
        bytes32 question_id = keccak256(abi.encodePacked(content_hash, arbitrator, timeout, min_bond, address(this), msg.sender, nonce));

        // We emit this event here because _askQuestion doesn't need to know the unhashed question.
        // Other events are emitted by _askQuestion.
        emit LogNewQuestion(question_id, msg.sender, template_id, question, content_hash, arbitrator, timeout, opening_ts, nonce, block.timestamp);
        _askQuestion(question_id, content_hash, arbitrator, timeout, opening_ts, min_bond);

        return question_id;
    }

    function _askQuestion(bytes32 question_id, bytes32 content_hash, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 min_bond) 
        stateNotCreated(question_id)
    internal {

        // A timeout of 0 makes no sense, and we will use this to check existence
        require(timeout > 0, "timeout must be positive"); 
        require(timeout < 365 days, "timeout must be less than 365 days"); 

        uint256 bounty = msg.value;

        // The arbitrator can set a fee for asking a question. 
        // This is intended as an anti-spam defence.
        // The fee is waived if the arbitrator is asking the question.
        // This allows them to set an impossibly high fee and make users proxy the question through them.
        // This would allow more sophisticated pricing, question whitelisting etc.
        if (arbitrator != NULL_ADDRESS && msg.sender != arbitrator) {
            uint256 question_fee = arbitrator_question_fees[arbitrator];
            require(bounty >= question_fee, "ETH provided must cover question fee"); 
            bounty = bounty - question_fee;
            balanceOf[arbitrator] = balanceOf[arbitrator] + question_fee;
        }

        questions[question_id].content_hash = content_hash;
        questions[question_id].arbitrator = arbitrator;
        questions[question_id].opening_ts = opening_ts;
        questions[question_id].timeout = timeout;

        if (bounty > 0) {
            questions[question_id].bounty = bounty;
            emit LogFundAnswerBounty(question_id, bounty, bounty, msg.sender);
        }

        if (min_bond > 0) {
            questions[question_id].min_bond = min_bond;
            emit LogMinimumBond(question_id, min_bond);
        }

    }

    /// @notice Add funds to the bounty for a question
    /// @dev Add bounty funds after the initial question creation. Can be done any time until the question is finalized.
    /// @param question_id The ID of the question you wish to fund
    function fundAnswerBounty(bytes32 question_id) 
        stateOpen(question_id)
    external payable {
        questions[question_id].bounty = questions[question_id].bounty + msg.value;
        emit LogFundAnswerBounty(question_id, msg.value, questions[question_id].bounty, msg.sender);
    }

    /// @notice Submit an answer for a question.
    /// @dev Adds the answer to the history and updates the current "best" answer.
    /// May be subject to front-running attacks; Substitute submitAnswerCommitment()->submitAnswerReveal() to prevent them.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous) 
        stateOpen(question_id)
        bondMustDoubleAndMatchMinimum(question_id)
        previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external payable {
        _addAnswerToHistory(question_id, answer, msg.sender, msg.value, false);
        _updateCurrentAnswer(question_id, answer);
    }

    /// @notice Submit an answer for a question, crediting it to the specified account.
    /// @dev Adds the answer to the history and updates the current "best" answer.
    /// May be subject to front-running attacks; Substitute submitAnswerCommitment()->submitAnswerReveal() to prevent them.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    /// @param answerer The account to which the answer should be credited
    function submitAnswerFor(bytes32 question_id, bytes32 answer, uint256 max_previous, address answerer)
        stateOpen(question_id)
        bondMustDoubleAndMatchMinimum(question_id)
        previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external payable {
        require(answerer != NULL_ADDRESS, "answerer must be non-zero");
        _addAnswerToHistory(question_id, answer, answerer, msg.value, false);
        _updateCurrentAnswer(question_id, answer);
    }

    // @notice Verify and store a commitment, including an appropriate timeout
    // @param question_id The ID of the question to store
    // @param commitment The ID of the commitment
    function _storeCommitment(bytes32 question_id, bytes32 commitment_id) 
    internal
    {
        require(commitments[commitment_id].reveal_ts == COMMITMENT_NON_EXISTENT, "commitment must not already exist");

        uint32 commitment_timeout = questions[question_id].timeout / COMMITMENT_TIMEOUT_RATIO;
        commitments[commitment_id].reveal_ts = uint32(block.timestamp) + commitment_timeout;
    }

    /// @notice Submit the hash of an answer, laying your claim to that answer if you reveal it in a subsequent transaction.
    /// @dev Creates a hash, commitment_id, uniquely identifying this answer, to this question, with this bond.
    /// The commitment_id is stored in the answer history where the answer would normally go.
    /// Does not update the current best answer - this is left to the later submitAnswerReveal() transaction.
    /// @param question_id The ID of the question
    /// @param answer_hash The hash of your answer, plus a nonce that you will later reveal
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    /// @param _answerer If specified, the address to be given as the question answerer. Defaults to the sender.
    /// @dev Specifying the answerer is useful if you want to delegate the commit-and-reveal to a third-party.
    function submitAnswerCommitment(bytes32 question_id, bytes32 answer_hash, uint256 max_previous, address _answerer) 
        stateOpen(question_id)
        bondMustDoubleAndMatchMinimum(question_id)
        previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external payable {

        bytes32 commitment_id = keccak256(abi.encodePacked(question_id, answer_hash, msg.value));
        address answerer = (_answerer == NULL_ADDRESS) ? msg.sender : _answerer;
        _storeCommitment(question_id, commitment_id);
        _addAnswerToHistory(question_id, commitment_id, answerer, msg.value, true);

    }

    /// @notice Submit the answer whose hash you sent in a previous submitAnswerCommitment() transaction
    /// @dev Checks the parameters supplied recreate an existing commitment, and stores the revealed answer
    /// Updates the current answer unless someone has since supplied a new answer with a higher bond
    /// msg.sender is intentionally not restricted to the user who originally sent the commitment; 
    /// For example, the user may want to provide the answer+nonce to a third-party service and let them send the tx
    /// NB If we are pending arbitration, it will be up to the arbitrator to wait and see any outstanding reveal is sent
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded as bytes32
    /// @param nonce The nonce that, combined with the answer, recreates the answer_hash you gave in submitAnswerCommitment()
    /// @param bond The bond that you paid in your submitAnswerCommitment() transaction
    function submitAnswerReveal(bytes32 question_id, bytes32 answer, uint256 nonce, uint256 bond) 
        stateOpenOrPendingArbitration(question_id)
    external {

        bytes32 answer_hash = keccak256(abi.encodePacked(answer, nonce));
        bytes32 commitment_id = keccak256(abi.encodePacked(question_id, answer_hash, bond));

        require(!commitments[commitment_id].is_revealed, "commitment must not have been revealed yet");
        require(commitments[commitment_id].reveal_ts > uint32(block.timestamp), "reveal deadline must not have passed");

        commitments[commitment_id].revealed_answer = answer;
        commitments[commitment_id].is_revealed = true;

        if (bond == questions[question_id].bond) {
            _updateCurrentAnswer(question_id, answer);
        }

        emit LogAnswerReveal(question_id, msg.sender, answer_hash, answer, nonce, bond);

    }

    function _addAnswerToHistory(bytes32 question_id, bytes32 answer_or_commitment_id, address answerer, uint256 bond, bool is_commitment) 
    internal 
    {
        bytes32 new_history_hash = keccak256(abi.encodePacked(questions[question_id].history_hash, answer_or_commitment_id, bond, answerer, is_commitment));

        // Update the current bond level, if there's a bond (ie anything except arbitration)
        if (bond > 0) {
            questions[question_id].bond = bond;
        }
        questions[question_id].history_hash = new_history_hash;

        emit LogNewAnswer(answer_or_commitment_id, question_id, new_history_hash, answerer, bond, block.timestamp, is_commitment);
    }

    function _updateCurrentAnswer(bytes32 question_id, bytes32 answer)
    internal {
        questions[question_id].best_answer = answer;
        questions[question_id].finalize_ts = uint32(block.timestamp) + questions[question_id].timeout;
    }

    // Like _updateCurrentAnswer but without advancing the timeout
    function _updateCurrentAnswerByArbitrator(bytes32 question_id, bytes32 answer)
    internal {
        questions[question_id].best_answer = answer;
        questions[question_id].finalize_ts = uint32(block.timestamp);
    }

    /// @notice Notify the contract that the arbitrator has been paid for a question, freezing it pending their decision.
    /// @dev The arbitrator contract is trusted to only call this if they've been paid, and tell us who paid them.
    /// @param question_id The ID of the question
    /// @param requester The account that requested arbitration
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function notifyOfArbitrationRequest(bytes32 question_id, address requester, uint256 max_previous) 
        onlyArbitrator(question_id)
        stateOpen(question_id)
        previousBondMustNotBeatMaxPrevious(question_id, max_previous)
    external {
        require(questions[question_id].finalize_ts > UNANSWERED, "Question must already have an answer when arbitration is requested");
        questions[question_id].is_pending_arbitration = true;
        emit LogNotifyOfArbitrationRequest(question_id, requester);
    }

    /// @notice Cancel a previously-requested arbitration and extend the timeout
    /// @dev Useful when doing arbitration across chains that can't be requested atomically
    /// @param question_id The ID of the question
    function cancelArbitration(bytes32 question_id) 
        onlyArbitrator(question_id)
        statePendingArbitration(question_id)
    external {
        questions[question_id].is_pending_arbitration = false;
        questions[question_id].finalize_ts = uint32(block.timestamp) + questions[question_id].timeout;
        emit LogCancelArbitration(question_id);
    }

    /// @notice Submit the answer for a question, for use by the arbitrator.
    /// @dev Doesn't require (or allow) a bond.
    /// If the current final answer is correct, the account should be whoever submitted it.
    /// If the current final answer is wrong, the account should be whoever paid for arbitration.
    /// However, the answerer stipulations are not enforced by the contract.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param answerer The account credited with this answer for the purpose of bond claims
    function submitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address answerer) 
        onlyArbitrator(question_id)
        statePendingArbitration(question_id)
    public {

        require(answerer != NULL_ADDRESS, "answerer must be provided");
        emit LogFinalize(question_id, answer);

        questions[question_id].is_pending_arbitration = false;
        _addAnswerToHistory(question_id, answer, answerer, 0, false);
        _updateCurrentAnswerByArbitrator(question_id, answer);

    }

    /// @notice Submit the answer for a question, for use by the arbitrator, working out the appropriate winner based on the last answer details.
    /// @dev Doesn't require (or allow) a bond.
    /// @param question_id The ID of the question
    /// @param answer The answer, encoded into bytes32
    /// @param payee_if_wrong The account to by credited as winner if the last answer given is wrong, usually the account that paid the arbitrator
    /// @param last_history_hash The history hash before the final one
    /// @param last_answer_or_commitment_id The last answer given, or the commitment ID if it was a commitment.
    /// @param last_answerer The address that supplied the last answer
    function assignWinnerAndSubmitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address payee_if_wrong, bytes32 last_history_hash, bytes32 last_answer_or_commitment_id, address last_answerer) 
    external {
        bool is_commitment = _verifyHistoryInputOrRevert(questions[question_id].history_hash, last_history_hash, last_answer_or_commitment_id, questions[question_id].bond, last_answerer);

        address payee;
        // If the last answer is an unrevealed commit, it's always wrong.
        // For anything else, the last answer was set as the "best answer" in submitAnswer or submitAnswerReveal.
        if (is_commitment && !commitments[last_answer_or_commitment_id].is_revealed) {
            require(commitments[last_answer_or_commitment_id].reveal_ts < uint32(block.timestamp), "You must wait for the reveal deadline before finalizing");
            payee = payee_if_wrong;
        } else {
            payee = (questions[question_id].best_answer == answer) ? last_answerer : payee_if_wrong;
        }
        submitAnswerByArbitrator(question_id, answer, payee);
    }

    /// @notice Report whether the answer to the specified question is finalized
    /// @param question_id The ID of the question
    /// @return Return true if finalized
    function isFinalized(bytes32 question_id) 
    view public returns (bool) {
        uint32 finalize_ts = questions[question_id].finalize_ts;
        return ( !questions[question_id].is_pending_arbitration && (finalize_ts > UNANSWERED) && (finalize_ts <= uint32(block.timestamp)) );
    }

    /// @notice (Deprecated) Return the final answer to the specified question, or revert if there isn't one
    /// @param question_id The ID of the question
    /// @return The answer formatted as a bytes32
    function getFinalAnswer(bytes32 question_id) 
        stateFinalized(question_id)
    external view returns (bytes32) {
        return questions[question_id].best_answer;
    }

    /// @notice Return the final answer to the specified question, or revert if there isn't one
    /// @param question_id The ID of the question
    /// @return The answer formatted as a bytes32
    function resultFor(bytes32 question_id) 
        stateFinalized(question_id)
    public view returns (bytes32) {
        return questions[question_id].best_answer;
    }

    /// @notice Returns whether the question was answered before it had an answer, ie resolved to UNRESOLVED_ANSWER
    /// @param question_id The ID of the question 
    function isSettledTooSoon(bytes32 question_id)
    public view returns(bool) {
        return (resultFor(question_id) == UNRESOLVED_ANSWER);
    }

    /// @notice Like resultFor(), but errors out if settled too soon, or returns the result of a replacement if it was reopened at the right time and settled
    /// @param question_id The ID of the question 
    function resultForOnceSettled(bytes32 question_id)
    external view returns(bytes32) {
        bytes32 result = resultFor(question_id);
        if (result == UNRESOLVED_ANSWER) {
            // Try the replacement
            bytes32 replacement_id = reopened_questions[question_id];
            require(replacement_id != bytes32(0x0), "Question was settled too soon and has not been reopened");
            // We only try one layer down rather than recursing to keep the gas costs predictable
            result = resultFor(replacement_id);
            require(result != UNRESOLVED_ANSWER, "Question replacement was settled too soon and has not been reopened");
        }
        return result;
    }

    /// @notice Asks a new question reopening a previously-asked question that was settled too soon
    /// @dev A special version of askQuestion() that replaces a previous question that was settled too soon
    /// @param template_id The ID number of the template the question will use
    /// @param question A string containing the parameters that will be passed into the template to make the question
    /// @param arbitrator The arbitration contract that will have the final word on the answer if there is a dispute
    /// @param timeout How long the contract should wait after the answer is changed before finalizing on that answer
    /// @param opening_ts If set, the earliest time it should be possible to answer the question.
    /// @param nonce A user-specified nonce used in the question ID. Change it to repeat a question.
    /// @param min_bond The minimum bond that can be used to provide the first answer.
    /// @param reopens_question_id The ID of the question this reopens
    /// @return The ID of the newly-created question, created deterministically.
    function reopenQuestion(uint256 template_id, string memory question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce, uint256 min_bond, bytes32 reopens_question_id)
        // stateNotCreated is enforced by the internal _askQuestion
    public payable returns (bytes32) {

        require(isSettledTooSoon(reopens_question_id), "You can only reopen questions that resolved as settled too soon");

        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));

        // A reopening must exactly match the original question, except for the nonce and the creator
        require(content_hash == questions[reopens_question_id].content_hash, "content hash mismatch");
        require(arbitrator == questions[reopens_question_id].arbitrator, "arbitrator mismatch");
        require(timeout == questions[reopens_question_id].timeout, "timeout mismatch");
        require(opening_ts == questions[reopens_question_id].opening_ts , "opening_ts mismatch");
        require(min_bond == questions[reopens_question_id].min_bond, "min_bond mismatch");

        // If the the question was itself reopening some previous question, you'll have to re-reopen the previous question first.
        // This ensures the bounty can be passed on to the next attempt of the original question.
        require(!reopener_questions[reopens_question_id], "Question is already reopening a previous question");

        // A question can only be reopened once, unless the reopening was also settled too soon in which case it can be replaced
        bytes32 existing_reopen_question_id = reopened_questions[reopens_question_id];

        // Normally when we reopen a question we will take its bounty and pass it on to the reopened version.
        bytes32 take_bounty_from_question_id = reopens_question_id;
        // If the question has already been reopened but was again settled too soon, we can transfer its bounty to the next attempt.
        if (existing_reopen_question_id != bytes32(0)) {
            require(isSettledTooSoon(existing_reopen_question_id), "Question has already been reopened");
            // We'll overwrite the reopening with our new question and move the bounty.
            // Once that's done we'll detach the failed reopener and you'll be able to reopen that too if you really want, but without the bounty.
            reopener_questions[existing_reopen_question_id] = false;
            take_bounty_from_question_id = existing_reopen_question_id;
        }

        bytes32 question_id = askQuestionWithMinBond(template_id, question, arbitrator, timeout, opening_ts, nonce, min_bond);

        reopened_questions[reopens_question_id] = question_id;
        reopener_questions[question_id] = true;

        questions[question_id].bounty = questions[take_bounty_from_question_id].bounty + questions[question_id].bounty;
        questions[take_bounty_from_question_id].bounty = 0;

        emit LogReopenQuestion(question_id, reopens_question_id);

        return question_id;
    }

    /// @notice Return the final answer to the specified question, provided it matches the specified criteria.
    /// @dev Reverts if the question is not finalized, or if it does not match the specified criteria.
    /// @param question_id The ID of the question
    /// @param content_hash The hash of the question content (template ID + opening time + question parameter string)
    /// @param arbitrator The arbitrator chosen for the question (regardless of whether they are asked to arbitrate)
    /// @param min_timeout The timeout set in the initial question settings must be this high or higher
    /// @param min_bond The bond sent with the final answer must be this high or higher
    /// @return The answer formatted as a bytes32
    function getFinalAnswerIfMatches(
        bytes32 question_id, 
        bytes32 content_hash, address arbitrator, uint32 min_timeout, uint256 min_bond
    ) 
        stateFinalized(question_id)
    external view returns (bytes32) {
        require(content_hash == questions[question_id].content_hash, "content hash must match");
        require(arbitrator == questions[question_id].arbitrator, "arbitrator must match");
        require(min_timeout <= questions[question_id].timeout, "timeout must be long enough");
        require(min_bond <= questions[question_id].bond, "bond must be high enough");
        return questions[question_id].best_answer;
    }

    /// @notice Assigns the winnings (bounty and bonds) to everyone who gave the accepted answer
    /// Caller must provide the answer history, in reverse order
    /// @dev Works up the chain and assign bonds to the person who gave the right answer
    /// If someone gave the winning answer earlier, they must get paid from the higher bond
    /// That means we can't pay out the bond added at n until we have looked at n-1
    /// The first answer is authenticated by checking against the stored history_hash.
    /// One of the inputs to history_hash is the history_hash before it, so we use that to authenticate the next entry, etc
    /// Once we get to a null hash we'll know we're done and there are no more answers.
    /// Usually you would call the whole thing in a single transaction, but if not then the data is persisted to pick up later.
    /// @param question_id The ID of the question
    /// @param history_hashes Second-last-to-first, the hash of each history entry. (Final one should be empty).
    /// @param addrs Last-to-first, the address of each answerer or commitment sender
    /// @param bonds Last-to-first, the bond supplied with each answer or commitment
    /// @param answers Last-to-first, each answer supplied, or commitment ID if the answer was supplied with commit->reveal
    function claimWinnings(
        bytes32 question_id, 
        bytes32[] memory history_hashes, address[] memory addrs, uint256[] memory bonds, bytes32[] memory answers
    ) 
        stateFinalized(question_id)
    public {

        require(history_hashes.length > 0, "at least one history hash entry must be provided");

        // These are only set if we split our claim over multiple transactions.
        address payee = question_claims[question_id].payee; 
        uint256 last_bond = question_claims[question_id].last_bond; 
        uint256 queued_funds = question_claims[question_id].queued_funds; 

        // Starts as the hash of the final answer submitted. It'll be cleared when we're done.
        // If we're splitting the claim over multiple transactions, it'll be the hash where we left off last time
        bytes32 last_history_hash = questions[question_id].history_hash;

        bytes32 best_answer = questions[question_id].best_answer;

        uint256 i;
        for (i = 0; i < history_hashes.length; i++) {
        
            // Check input against the history hash, and see which of 2 possible values of is_commitment fits.
            bool is_commitment = _verifyHistoryInputOrRevert(last_history_hash, history_hashes[i], answers[i], bonds[i], addrs[i]);
            
            queued_funds = queued_funds + last_bond; 
            (queued_funds, payee) = _processHistoryItem(
                question_id, best_answer, queued_funds, payee, 
                addrs[i], bonds[i], answers[i], is_commitment);
 
            // Line the bond up for next time, when it will be added to somebody's queued_funds
            last_bond = bonds[i];

            // Burn (just leave in contract balance) a fraction of all bonds except the final one.
            // This creates a cost to increasing your own bond, which could be used to delay resolution maliciously
            if (last_bond != questions[question_id].bond) {
                last_bond = last_bond - last_bond / BOND_CLAIM_FEE_PROPORTION;
            }

            last_history_hash = history_hashes[i];

        }
 
        if (last_history_hash != NULL_HASH) {
            // We haven't yet got to the null hash (1st answer), ie the caller didn't supply the full answer chain.
            // Persist the details so we can pick up later where we left off later.

            // If we know who to pay we can go ahead and pay them out, only keeping back last_bond
            // (We always know who to pay unless all we saw were unrevealed commits)
            if (payee != NULL_ADDRESS) {
                _payPayee(question_id, payee, queued_funds);
                queued_funds = 0;
            }

            question_claims[question_id].payee = payee;
            question_claims[question_id].last_bond = last_bond;
            question_claims[question_id].queued_funds = queued_funds;
        } else {
            // There is nothing left below us so the payee can keep what remains
            _payPayee(question_id, payee, queued_funds + last_bond);
            delete question_claims[question_id];
        }

        questions[question_id].history_hash = last_history_hash;

    }

    function _payPayee(bytes32 question_id, address payee, uint256 value) 
    internal {
        balanceOf[payee] = balanceOf[payee] + value;
        emit LogClaim(question_id, payee, value);
    }

    function _verifyHistoryInputOrRevert(
        bytes32 last_history_hash,
        bytes32 history_hash, bytes32 answer, uint256 bond, address addr
    )
    internal pure returns (bool) {
        if (last_history_hash == keccak256(abi.encodePacked(history_hash, answer, bond, addr, true)) ) {
            return true;
        }
        if (last_history_hash == keccak256(abi.encodePacked(history_hash, answer, bond, addr, false)) ) {
            return false;
        } 
        revert("History input provided did not match the expected hash");
    }

    function _processHistoryItem(
        bytes32 question_id, bytes32 best_answer, 
        uint256 queued_funds, address payee, 
        address addr, uint256 bond, bytes32 answer, bool is_commitment
    )
    internal returns (uint256, address) {

        // For commit-and-reveal, the answer history holds the commitment ID instead of the answer.
        // We look at the referenced commitment ID and switch in the actual answer.
        if (is_commitment) {
            bytes32 commitment_id = answer;
            // If it's a commit but it hasn't been revealed, it will always be considered wrong.
            if (!commitments[commitment_id].is_revealed) {
                delete commitments[commitment_id];
                return (queued_funds, payee);
            } else {
                answer = commitments[commitment_id].revealed_answer;
                delete commitments[commitment_id];
            }
        }

        if (answer == best_answer) {

            if (payee == NULL_ADDRESS) {

                // The entry is for the first payee we come to, ie the winner.
                // They get the question bounty.
                payee = addr;

                if (best_answer != UNRESOLVED_ANSWER && questions[question_id].bounty > 0) {
                    _payPayee(question_id, payee, questions[question_id].bounty);
                    questions[question_id].bounty = 0;
                }

            } else if (addr != payee) {

                // Answerer has changed, ie we found someone lower down who needs to be paid

                // The lower answerer will take over receiving bonds from higher answerer.
                // They should also be paid the takeover fee, which is set at a rate equivalent to their bond. 
                // (This is our arbitrary rule, to give consistent right-answerers a defence against high-rollers.)

                // There should be enough for the fee, but if not, take what we have.
                // There's an edge case involving weird arbitrator behaviour where we may be short.
                uint256 answer_takeover_fee = (queued_funds >= bond) ? bond : queued_funds;
                // Settle up with the old (higher-bonded) payee
                _payPayee(question_id, payee, queued_funds - answer_takeover_fee);

                // Now start queued_funds again for the new (lower-bonded) payee
                payee = addr;
                queued_funds = answer_takeover_fee;

            }

        }

        return (queued_funds, payee);

    }

    /// @notice Convenience function to assign bounties/bonds for multiple questions in one go, then withdraw all your funds.
    /// Caller must provide the answer history for each question, in reverse order
    /// @dev Can be called by anyone to assign bonds/bounties, but funds are only withdrawn for the user making the call.
    /// @param question_ids The IDs of the questions you want to claim for
    /// @param lengths The number of history entries you will supply for each question ID
    /// @param hist_hashes In a single list for all supplied questions, the hash of each history entry.
    /// @param addrs In a single list for all supplied questions, the address of each answerer or commitment sender
    /// @param bonds In a single list for all supplied questions, the bond supplied with each answer or commitment
    /// @param answers In a single list for all supplied questions, each answer supplied, or commitment ID 
    function claimMultipleAndWithdrawBalance(
        bytes32[] memory question_ids, uint256[] memory lengths, 
        bytes32[] memory hist_hashes, address[] memory addrs, uint256[] memory bonds, bytes32[] memory answers
    ) 
        stateAny() // The finalization checks are done in the claimWinnings function
    public {
        
        uint256 qi;
        uint256 i;
        for (qi = 0; qi < question_ids.length; qi++) {
            bytes32 qid = question_ids[qi];
            uint256 ln = lengths[qi];
            bytes32[] memory hh = new bytes32[](ln);
            address[] memory ad = new address[](ln);
            uint256[] memory bo = new uint256[](ln);
            bytes32[] memory an = new bytes32[](ln);
            uint256 j;
            for (j = 0; j < ln; j++) {
                hh[j] = hist_hashes[i];
                ad[j] = addrs[i];
                bo[j] = bonds[i];
                an[j] = answers[i];
                i++;
            }
            claimWinnings(qid, hh, ad, bo, an);
        }
        withdraw();
    }

    /// @notice Returns the questions's content hash, identifying the question content
    /// @param question_id The ID of the question 
    function getContentHash(bytes32 question_id) 
    public view returns(bytes32) {
        return questions[question_id].content_hash;
    }

    /// @notice Returns the arbitrator address for the question
    /// @param question_id The ID of the question 
    function getArbitrator(bytes32 question_id) 
    public view returns(address) {
        return questions[question_id].arbitrator;
    }

    /// @notice Returns the timestamp when the question can first be answered
    /// @param question_id The ID of the question 
    function getOpeningTS(bytes32 question_id) 
    public view returns(uint32) {
        return questions[question_id].opening_ts;
    }

    /// @notice Returns the timeout in seconds used after each answer
    /// @param question_id The ID of the question 
    function getTimeout(bytes32 question_id) 
    public view returns(uint32) {
        return questions[question_id].timeout;
    }

    /// @notice Returns the timestamp at which the question will be/was finalized
    /// @param question_id The ID of the question 
    function getFinalizeTS(bytes32 question_id) 
    public view returns(uint32) {
        return questions[question_id].finalize_ts;
    }

    /// @notice Returns whether the question is pending arbitration
    /// @param question_id The ID of the question 
    function isPendingArbitration(bytes32 question_id) 
    public view returns(bool) {
        return questions[question_id].is_pending_arbitration;
    }

    /// @notice Returns the current total unclaimed bounty
    /// @dev Set back to zero once the bounty has been claimed
    /// @param question_id The ID of the question 
    function getBounty(bytes32 question_id) 
    public view returns(uint256) {
        return questions[question_id].bounty;
    }

    /// @notice Returns the current best answer
    /// @param question_id The ID of the question 
    function getBestAnswer(bytes32 question_id) 
    public view returns(bytes32) {
        return questions[question_id].best_answer;
    }

    /// @notice Returns the history hash of the question 
    /// @param question_id The ID of the question 
    /// @dev Updated on each answer, then rewound as each is claimed
    function getHistoryHash(bytes32 question_id) 
    public view returns(bytes32) {
        return questions[question_id].history_hash;
    }

    /// @notice Returns the highest bond posted so far for a question
    /// @param question_id The ID of the question 
    function getBond(bytes32 question_id) 
    public view returns(uint256) {
        return questions[question_id].bond;
    }

    /// @notice Returns the minimum bond that can answer the question
    /// @param question_id The ID of the question
    function getMinBond(bytes32 question_id)
    public view returns(uint256) {
        return questions[question_id].min_bond;
    }

}

// lib/openzeppelin-contracts/contracts/security/Pausable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol

// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// lib/openzeppelin-contracts/contracts/utils/Strings.sol

// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toString(int256 value) internal pure returns (string memory) {
        return string(abi.encodePacked(value < 0 ? "-" : "", toString(SignedMath.abs(value))));
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// lib/openzeppelin-contracts/contracts/access/AccessControl.sol

// OpenZeppelin Contracts (last updated v4.9.0) (access/AccessControl.sol)

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```solidity
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```solidity
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it. We recommend using {AccessControlDefaultAdminRules}
 * to enforce additional security measures for this role.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `_msgSender()` is missing `role`.
     * Overriding this function changes the behavior of the {onlyRole} modifier.
     *
     * Format of the revert message is described in {_checkRole}.
     *
     * _Available since v4.6._
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * May emit a {RoleGranted} event.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     *
     * NOTE: This function is deprecated in favor of {_grantRole}.
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

// src/KaiSign.sol

contract KaiSign is ReentrancyGuard, AccessControl, Pausable {

    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================
    error AlreadyProposed();
    error NotProposed();
    error InsufficientBond();
    error InsufficientIncentive();
    error InvalidContract();
    error ContractNotFound();
    error CommitmentNotFound();
    error CommitmentExpired();
    error CommitmentAlreadyRevealed();
    error InvalidReveal();
    error NotFinalized();
    error AlreadySettled();
    error NoIncentiveToClaim();
    error IncentiveExpired();
    error Unauthorized();
    error ClawbackTooEarly();

    // =============================================================================
    //                                   ROLES
    // =============================================================================
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // =============================================================================
    //                                CONSTANTS
    // =============================================================================
    string public constant VERSION = "1.0.0";
    uint256 public constant PLATFORM_FEE_PERCENT = 5; // 5%
    uint256 public constant COMMIT_REVEAL_TIMEOUT = 1 hours;
    uint256 public constant INCENTIVE_DURATION = 30 days;
    uint256 public constant INCENTIVE_CLAWBACK_PERIOD = 90 days; // 3 months
    uint32 public constant DEFAULT_TIMEOUT = 48 hours; // 48 hours for Reality.eth questions

    // =============================================================================
    //                              STATE VARIABLES
    // =============================================================================
    address public immutable realityETH;
    address public immutable arbitrator;
    address public immutable treasury;
    uint256 public minBond;
    uint256 public templateId;
    
    // Blob hash storage only
    mapping(bytes32 => bytes32) public specBlobHash;
    
    // Commit-reveal mechanism
    mapping(bytes32 => CommitData) public commitments;
    
    // Contract address integration with chain support
    mapping(uint256 => mapping(address => bytes32[])) public contractSpecs;
    mapping(uint256 => mapping(address => uint256)) public contractSpecCount;
    
    // Incentive system
    mapping(bytes32 => IncentiveData) public incentives;
    mapping(address => bytes32[]) public userIncentives;
    mapping(uint256 => mapping(address => uint256)) public incentivePool;
    mapping(uint256 => mapping(address => uint256)) public poolContributorCount;
    
    // Spec management
    mapping(bytes32 => ERC7730Spec) public specs;
    mapping(bytes32 => mapping(address => uint256)) public userBonds;
    
    // =============================================================================
    //                                   ENUMS
    // =============================================================================
    enum Status {
        Committed,    // Commitment submitted, waiting for reveal
        Submitted,    // Revealed and submitted, waiting for proposal
        Proposed,     // Question created on Reality.eth
        Finalized,    // Final result determined
        Cancelled     // Cancelled/invalid
    }

    // =============================================================================
    //                                 STRUCTS
    // =============================================================================
    
    // Optimized struct packing for gas efficiency
    struct ERC7730Spec {
        uint64 createdTimestamp;    // 8 bytes
        uint64 proposedTimestamp;   // 8 bytes  
        Status status;              // 1 byte
        uint80 totalBonds;          // 10 bytes (up to ~1.2M ETH)
        uint32 reserved;            // 4 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        address creator;            // 20 bytes  
        address targetContract;     // 20 bytes - contract this spec validates
        // SLOT 2: 40 bytes - needs 2 slots but efficiently packed
        
        bytes32 blobHash;          // 32 bytes - EIP-4844 blob hash for ERC7730 JSON
        bytes32 questionId;        // 32 bytes - full slot
        bytes32 incentiveId;       // 32 bytes - linked incentive if any
        uint256 chainId;           // 32 bytes - target chain ID
        // SLOTS 3+: Only when spec has blobHash/questionId/incentiveId/chainId
    }

    struct CommitData {
        address committer;          // 20 bytes
        uint64 commitTimestamp;     // 8 bytes
        uint32 reserved1;           // 4 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        address targetContract;     // 20 bytes
        bool isRevealed;            // 1 byte
        uint80 bondAmount;          // 10 bytes (up to 1.2M ETH)
        uint8 reserved;             // 1 byte - for alignment
        // SLOT 2: 32 bytes total (perfectly packed!)
        
        uint64 revealDeadline;      // 8 bytes (safe until year 2554)
        uint256 chainId;            // 32 bytes - target chain ID
        bytes32 incentiveId;        // 32 bytes - if incentivized
        // SLOTS 3-4: Chain ID and incentive data
    }

    struct IncentiveData {
        address creator;            // 20 bytes
        uint80 amount;              // 10 bytes (up to ~1.2M ETH)
        uint16 reserved1;           // 2 bytes - reserved for future use
        // SLOT 1: 32 bytes total (perfectly packed!)
        
        uint64 deadline;            // 8 bytes
        uint64 createdAt;           // 8 bytes
        address targetContract;     // 20 bytes - truncated to 16 bytes
        // SLOT 2: 36 bytes - needs 2 slots
        
        bool isClaimed;             // 1 byte
        bool isActive;              // 1 byte
        uint256 chainId;            // 32 bytes - target chain ID
        // SLOT 3: Chain ID and flags
        
        string description;         // Dynamic - separate slots when needed
        // SLOT 4+: Description when exists
    }

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event LogCommitSpec(
        address indexed committer,
        bytes32 indexed commitmentId,
        address indexed targetContract,
        uint256 chainId,
        uint256 bondAmount,
        uint64 revealDeadline
    );

    event LogRevealSpec(
        address indexed creator,
        bytes32 indexed specID,
        bytes32 indexed blobHash,
        bytes32 commitmentId,
        address targetContract,
        uint256 chainId
    );

    event LogCreateSpec(
        address indexed creator,
        bytes32 indexed specID,
        bytes32 indexed blobHash,
        address targetContract,
        uint256 chainId,
        uint256 timestamp,
        bytes32 incentiveId
    );

    event LogProposeSpec(
        address indexed user,
        bytes32 indexed specID,
        bytes32 questionId,
        uint256 bond
    );

    // The following events related to spec assertion have been removed.
    // Originally, KaiSign allowed anyone to top up a spec’s bond and vote on the outcome
    // through `assertSpecValid` and `assertSpecInvalid`. Those functions (and their
    // associated events) have been removed to simplify the contract and rely solely on
    // Reality.eth’s native bond mechanism.

    event LogHandleResult(
        bytes32 indexed specID,
        bool isAccepted
    );

    event LogIncentiveCreated(
        bytes32 indexed incentiveId,
        address indexed creator,
        address indexed targetContract,
        uint256 chainId,
        uint256 amount,
        uint64 deadline,
        string description
    );

    event LogIncentiveClaimed(
        bytes32 indexed incentiveId,
        address indexed claimer,
        bytes32 indexed specID,
        uint256 amount
    );

    event LogIncentiveClawback(
        bytes32 indexed incentiveId,
        address indexed creator,
        uint256 amount
    );

    event LogContractSpecAdded(
        address indexed targetContract,
        bytes32 indexed specID,
        address indexed creator,
        uint256 chainId,
        bytes32 blobHash
    );

    event LogEmergencyPause(address indexed admin);
    event LogEmergencyUnpause(address indexed admin);

    // =============================================================================
    //                                MODIFIERS
    // =============================================================================
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    // =============================================================================
    //                               CONSTRUCTOR
    // =============================================================================
    constructor(
        address _realityETH,
        address _arbitrator,
        address _treasury,
        uint256 _minBond,
        address[] memory _initialAdmins
    ) {
        if (_realityETH == address(0)) revert InvalidContract();
        if (_arbitrator == address(0)) revert InvalidContract();
        if (_treasury == address(0)) revert InvalidContract();
        if (_initialAdmins.length == 0) revert Unauthorized();

        realityETH = _realityETH;
        arbitrator = _arbitrator;
        treasury = _treasury;
        minBond = _minBond;

        // Set up initial admins
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _initialAdmins.length; i++) {
            _grantRole(ADMIN_ROLE, _initialAdmins[i]);
        }

        // Create Reality.eth template
        templateId = RealityETH_v3_0(realityETH).createTemplate(
            '{"title": "Is the ERC7730 specification %s for contract %s on chain %s correct?", "type": "bool", "category": "misc"}'
        );
    }

    // =============================================================================
    //                              ADMIN FUNCTIONS
    // =============================================================================
    
    function setMinBond(uint256 _minBond) external onlyAdmin {
        minBond = _minBond;
    }

    function addAdmin(address newAdmin) external onlyAdmin {
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function removeAdmin(address admin) external onlyAdmin {
        _revokeRole(ADMIN_ROLE, admin);
    }

    // Emergency pause/unpause - any admin can trigger
    function emergencyPause() external onlyAdmin {
        _pause();
        emit LogEmergencyPause(msg.sender);
    }

    function emergencyUnpause() external onlyAdmin {
        _unpause();
        emit LogEmergencyUnpause(msg.sender);
    }

    // =============================================================================
    //                           INCENTIVE SYSTEM
    // =============================================================================
    
    function createIncentive(
        address targetContract,
        uint256 targetChainId,
        uint256 amount,
        uint64 duration,
        string calldata description
    ) external payable nonReentrant whenNotPaused returns (bytes32 incentiveId) {
        if (targetContract == address(0)) revert InvalidContract();
        if (targetChainId == 0) revert InvalidContract();
        if (amount > type(uint80).max) revert InsufficientIncentive(); // Prevent overflow
        if (duration == 0 || duration > 30 days) revert IncentiveExpired();
        
        // ETH incentive only
        if (msg.value < amount) revert InsufficientIncentive();
        // Refund excess ETH
        if (msg.value > amount) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - amount}("");
            require(success, "Excess ETH refund failed");
        }
        
        incentiveId = keccak256(abi.encodePacked(
            msg.sender,
            targetContract,
            targetChainId,
            amount,
            block.timestamp,
            description
        ));

        incentives[incentiveId] = IncentiveData({
            creator: msg.sender,
            amount: uint80(amount),
            reserved1: 0,
            deadline: uint64(block.timestamp + duration),
            createdAt: uint64(block.timestamp),
            targetContract: targetContract,
            isClaimed: false,
            isActive: true,
            chainId: targetChainId,
            description: description
        });

        userIncentives[msg.sender].push(incentiveId);
        incentivePool[targetChainId][targetContract] += amount;
        poolContributorCount[targetChainId][targetContract]++;

        emit LogIncentiveCreated(
            incentiveId,
            msg.sender,
            targetContract,
            targetChainId,
            amount,
            uint64(block.timestamp + duration),
            description
        );
    }

    // =============================================================================
    //                           COMMIT-REVEAL PATTERN
    // =============================================================================
    
    function commitSpec(
        bytes32 commitment,
        address targetContract,
        uint256 targetChainId
    ) external nonReentrant whenNotPaused {
        if (targetContract == address(0)) revert InvalidContract();
        if (targetChainId == 0) revert InvalidContract();
        // This function is intentionally non-payable. Any Ether sent with this call will
        // cause the transaction to revert before reaching this code. Bonds must be
        // supplied during the reveal step, not at commit time.

        uint64 currentTime = uint64(block.timestamp);

        bytes32 commitmentId = keccak256(abi.encodePacked(
            commitment,
            msg.sender,
            targetContract,
            targetChainId,
            currentTime
        ));

        // Store the commitment with zero bond. The bond will be provided at reveal time.
        commitments[commitmentId] = CommitData({
            committer: msg.sender,
            commitTimestamp: currentTime,
            reserved1: 0,
            targetContract: targetContract,
            isRevealed: false,
            bondAmount: 0,
            reserved: 0,
            revealDeadline: currentTime + uint64(COMMIT_REVEAL_TIMEOUT),
            chainId: targetChainId,
            incentiveId: bytes32(0)
        });

        emit LogCommitSpec(
            msg.sender,
            commitmentId,
            targetContract,
            targetChainId,
            0,
            currentTime + uint64(COMMIT_REVEAL_TIMEOUT)
        );
    }

    function revealSpec(
        bytes32 commitmentId,
        bytes32 blobHash,
        bytes32 metadataHash,
        uint256 nonce
    ) external payable nonReentrant whenNotPaused returns (bytes32 specID) {
        return _revealSpecInternal(commitmentId, blobHash, metadataHash, nonce);
    }
    
    
    function _revealSpecInternal(
        bytes32 commitmentId,
        bytes32 blobHash,
        bytes32 metadataHash,
        uint256 nonce
    ) internal returns (bytes32 specID) {
        CommitData storage commitment = commitments[commitmentId];
        
        if (commitment.committer == address(0)) revert CommitmentNotFound();
        if (commitment.committer != msg.sender) revert InvalidReveal();
        if (commitment.isRevealed) revert CommitmentAlreadyRevealed();
        // If the commit has expired, no reveal is allowed.
        if (block.timestamp > commitment.revealDeadline) revert CommitmentExpired();
        // Blob hash is mandatory for EIP-4844 blob reference
        if (blobHash == bytes32(0)) revert InvalidReveal();
        
        // Collect the bond at reveal time. Require it meets the minimum bond.
        // No platform fee is deducted - the full amount goes to the spec.
        if (msg.value < minBond) revert InsufficientBond();
        uint256 netBondAmount = msg.value;
        // Prevent overflow when storing into uint80
        if (netBondAmount > type(uint80).max) revert InsufficientBond();
        // Record the bond on the commitment. This replaces any bond recorded during commit.
        commitment.bondAmount = uint80(netBondAmount);

        // Verify commitment: use metadataHash instead of blobHash for verification
        bytes32 expectedCommitment = keccak256(abi.encodePacked(metadataHash, nonce));
        bytes32 reconstructedCommitmentId = keccak256(abi.encodePacked(
            expectedCommitment,
            commitment.committer,
            commitment.targetContract,
            commitment.chainId,
            commitment.commitTimestamp
        ));

        if (reconstructedCommitmentId != commitmentId) revert InvalidReveal();

        // Create spec ID
        specID = keccak256(abi.encodePacked(
            blobHash,
            commitment.targetContract,
            commitment.chainId,
            msg.sender,
            commitment.commitTimestamp
        ));

        if (specs[specID].createdTimestamp != 0) revert AlreadyProposed();

        // Mark commitment as revealed
        commitment.isRevealed = true;

        // Create spec and store ERC7730 JSON
        specs[specID] = ERC7730Spec({
            createdTimestamp: uint64(block.timestamp),
            proposedTimestamp: 0,
            status: Status.Submitted,
            totalBonds: uint80(commitment.bondAmount),
            reserved: 0,
            creator: msg.sender,
            targetContract: commitment.targetContract,
            blobHash: blobHash,
            questionId: bytes32(0),
            incentiveId: bytes32(0),
            chainId: commitment.chainId
        });
        
        // Store the blob hash
        specBlobHash[specID] = blobHash;

        // Index by contract and chain
        contractSpecs[commitment.chainId][commitment.targetContract].push(specID);
        contractSpecCount[commitment.chainId][commitment.targetContract]++;

        emit LogRevealSpec(
            msg.sender,
            specID,
            blobHash,
            commitmentId,
            commitment.targetContract,
            commitment.chainId
        );

        emit LogCreateSpec(
            msg.sender,
            specID,
            blobHash,
            commitment.targetContract,
            commitment.chainId,
            block.timestamp,
            bytes32(0)
        );

        emit LogContractSpecAdded(
            commitment.targetContract,
            specID,
            msg.sender,
            commitment.chainId,
            blobHash
        );

        // Auto-propose if enough bond was provided
        if (commitment.bondAmount >= minBond) {
            _proposeSpec(specID, true);
        }

        // No platform fee is collected for spec submissions
        return specID;
    }

    // =============================================================================
    //                              SPEC MANAGEMENT
    // =============================================================================
    
    function proposeSpec(bytes32 specID) external payable nonReentrant whenNotPaused {
        _proposeSpec(specID, false);
    }

    function _proposeSpec(bytes32 specID, bool isInternalCall) internal {
        ERC7730Spec storage spec = specs[specID];
        if (spec.createdTimestamp == 0) revert NotProposed();
        if (spec.status != Status.Submitted) revert AlreadyProposed();

        uint256 additionalBond;
        uint256 totalBond;
        
        if (isInternalCall) {
            // Called from revealSpec - no additional bond, use existing totalBonds
            additionalBond = 0;
            totalBond = spec.totalBonds;
        } else {
            // Called from proposeSpec - msg.value is additional bond
            additionalBond = msg.value;
            totalBond = spec.totalBonds + additionalBond;
        }
        
        if (totalBond < minBond) revert InsufficientBond();
        if (totalBond > type(uint80).max) revert InsufficientBond(); // Prevent overflow

        // EFFECTS: update state before external interactions
        spec.status = Status.Proposed;
        spec.proposedTimestamp = uint64(block.timestamp);
        spec.totalBonds = uint80(totalBond);
        // Track the entire amount credited to the spec for this user
        if (additionalBond > 0) {
            userBonds[specID][msg.sender] += additionalBond;
        }

        // INTERACTIONS: create Reality.eth question using the total bond
        string memory delim = unicode"␟";
        string memory questionParams = string(abi.encodePacked(
            _bytes32ToString(spec.blobHash),
            delim,
            _addressToString(spec.targetContract),
            delim,
            _uint256ToString(spec.chainId)
        ));

        spec.questionId = RealityETH_v3_0(realityETH).askQuestionWithMinBond{value: totalBond}(
            templateId,
            questionParams,
            arbitrator,
            DEFAULT_TIMEOUT,
            0,
            0,
            minBond
        );

        emit LogProposeSpec(msg.sender, specID, spec.questionId, totalBond);

    }

    function handleResult(bytes32 specID) external nonReentrant whenNotPaused {
        ERC7730Spec storage spec = specs[specID];
        if (spec.status != Status.Proposed) revert NotProposed();

        // Check if Reality.eth question is finalized
        if (!RealityETH_v3_0(realityETH).isFinalized(spec.questionId)) revert NotFinalized();

        bytes32 result = RealityETH_v3_0(realityETH).resultFor(spec.questionId);
        bool specAccepted = uint256(result) == 1;

        spec.status = Status.Finalized;
        emit LogHandleResult(specID, specAccepted);

        if (specAccepted) {
            // Blob hash is stored in the contract
            // Metadata is in the blob sidecar referenced by blobHash
            
            // Claim from the incentive pool for this contract/chain
            uint256 poolAmount = incentivePool[spec.chainId][spec.targetContract];
            if (poolAmount > 0) {
                incentivePool[spec.chainId][spec.targetContract] = 0;
                _claimFromPool(poolAmount, specID, spec.creator);
            }
        }
    }

    function _claimIncentive(bytes32 incentiveId, bytes32 specID, address claimer) internal {
        IncentiveData storage incentive = incentives[incentiveId];
        if (incentive.isClaimed || !incentive.isActive) revert NoIncentiveToClaim();
        if (block.timestamp > incentive.deadline) revert IncentiveExpired();

        incentive.isClaimed = true;
        incentive.isActive = false;

        uint256 platformFee = (incentive.amount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = incentive.amount - platformFee;

        // ETH payout only
        (bool success, ) = payable(claimer).call{value: claimerAmount}("");
        require(success, "Claimer transfer failed");
        (bool treasurySuccess, ) = treasury.call{value: platformFee, gas: 50000}("");
        require(treasurySuccess, "Treasury transfer failed");

        emit LogIncentiveClaimed(incentiveId, claimer, specID, claimerAmount);
    }

    function _claimFromPool(uint256 poolAmount, bytes32 specID, address claimer) internal {
        if (poolAmount == 0) revert NoIncentiveToClaim();

        uint256 platformFee = (poolAmount * PLATFORM_FEE_PERCENT) / 100;
        uint256 claimerAmount = poolAmount - platformFee;

        // ETH payout only
        (bool success, ) = payable(claimer).call{value: claimerAmount}("");
        require(success, "Claimer transfer failed");
        (bool treasurySuccess, ) = treasury.call{value: platformFee, gas: 50000}("");
        require(treasurySuccess, "Treasury transfer failed");

        emit LogIncentiveClaimed(bytes32(0), claimer, specID, claimerAmount);
    }

    // Allow incentive creators to reclaim funds after 3 months if unclaimed
    function clawbackIncentive(bytes32 incentiveId) external nonReentrant whenNotPaused {
        IncentiveData storage incentive = incentives[incentiveId];
        
        if (incentive.creator != msg.sender) revert Unauthorized();
        if (incentive.isClaimed || !incentive.isActive) revert NoIncentiveToClaim();
        if (block.timestamp < incentive.createdAt + INCENTIVE_CLAWBACK_PERIOD) revert ClawbackTooEarly();
        
        // Mark as inactive and claimed to prevent double-spending
        incentive.isClaimed = true;
        incentive.isActive = false;
        
        uint256 clawbackAmount = incentive.amount;
        
        // ETH clawback only - no platform fee on clawback
        (bool success, ) = payable(msg.sender).call{value: clawbackAmount}("");
        require(success, "Clawback transfer failed");

        // Reduce pool amount by clawback amount
        incentivePool[incentive.chainId][incentive.targetContract] -= clawbackAmount;
        poolContributorCount[incentive.chainId][incentive.targetContract]--;
        
        emit LogIncentiveClawback(incentiveId, msg.sender, clawbackAmount);
    }

    // =============================================================================
    //                              BOND SETTLEMENT
    // =============================================================================

    // =============================================================================
    //                              QUERY FUNCTIONS
    // =============================================================================
    
    function getSpecsByContract(address targetContract, uint256 chainId) external view returns (bytes32[] memory) {
        return contractSpecs[chainId][targetContract];
    }

    function getSpecsByContractPaginated(
        address targetContract,
        uint256 chainId,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory specIds, uint256 total) {
        bytes32[] storage allSpecs = contractSpecs[chainId][targetContract];
        total = allSpecs.length;
        
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        specIds = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            specIds[i - offset] = allSpecs[i];
        }
    }

    function getContractSpecCount(address targetContract, uint256 chainId) external view returns (uint256) {
        return contractSpecCount[chainId][targetContract];
    }

    function getUserIncentives(address user) external view returns (bytes32[] memory) {
        return userIncentives[user];
    }

    function getIncentivePool(address targetContract, uint256 chainId) external view returns (uint256 poolAmount, uint256 contributorCount) {
        return (incentivePool[chainId][targetContract], poolContributorCount[chainId][targetContract]);
    }
    
    
    function getSpecBlobHash(bytes32 specID) external view returns (bytes32) {
        return specBlobHash[specID];
    }
    

    // =============================================================================
    //                              UTILITY FUNCTIONS
    // =============================================================================
    
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint8(data[i] >> 4)];
            str[3+i*2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66); // "0x" + 64 characters
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }

}

