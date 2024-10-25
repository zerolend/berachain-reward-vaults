// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

library Utils {
    using SafeTransferLib for address;

    /// @notice Error for overflow when increasing allowance
    error IncreaseAllowanceOverflow();

    /// @dev Reverts with the selector of a custom error in the scratch space.
    function revertWith(bytes4 selector) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            revert(0, 0x04)
        }
    }

    /// @dev Reverts for the reason encoding a silent revert, Error(string), or a custom error.
    function revertFor(bytes memory reason) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function revertWith(bytes4 selector, address addr) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, addr)
            revert(0, 0x24) // 4 (selector) + 32 (addr)
        }
    }

    function revertWith(bytes4 selector, uint256 amount) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, amount)
            revert(0, 0x24) // 4 (selector) + 32 (amount)
        }
    }

    function revertWith(bytes4 selector, uint256 amount1, uint256 amount2) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, amount1)
            mstore(0x24, amount2)
            revert(0, 0x44) // 4 (selector) + 32 (amount1) + 32 (amount2)
        }
    }

    function revertWith(bytes4 selector, address addr1, address addr2) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, addr1)
            mstore(0x24, addr2)
            revert(0, 0x44) // 4 (selector) + 32 (addr1) + 32 (addr2)
        }
    }

    /// @dev Increase the calling contract's allowance toward `spender` by `amount`.
    /// @dev Does not check if token exists.
    function safeIncreaseAllowance(address token, address spender, uint256 amount) internal {
        unchecked {
            uint256 oldAllowance = allowance(token, address(this), spender);
            uint256 newAllowance = oldAllowance + amount;
            if (newAllowance < oldAllowance) revertWith(IncreaseAllowanceOverflow.selector);
            token.safeApprove(spender, newAllowance);
        }
    }

    /// @dev Returns the amount of ERC20 `token` that `owner` has allowed `spender` to use.
    /// Returns zero if the `token` does not exist.
    function allowance(address token, address owner, address spender) internal view returns (uint256 amount) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, 0xdd62ed3e00000000000000000000000000000000000000000000000000000000) // Store function selector of
                // `allowance(address,address)`.
            mstore(0x04, owner) // Store the `owner` argument.
            mstore(0x24, spender) // Store the `spender` argument.
            amount :=
                mul( // The arguments of `mul` are evaluated from right to left.
                    mload(0),
                    and( // The arguments of `and` are evaluated from right to left.
                        gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                        staticcall(gas(), token, 0, 0x44, 0, 0x20)
                    )
                )
            mstore(0x24, 0) // clear the upper bits of free memory pointer.
        }
    }
}
