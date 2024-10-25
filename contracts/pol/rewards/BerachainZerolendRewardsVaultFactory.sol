// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBerachainRewardsVaultFactory } from "../interfaces/IBerachainRewardsVaultFactory.sol";
import { IBerachainRewardsVault } from "./BerachainZerolendRewardsVault.sol";

/// @title BerachainRewardsVaultFactory
/// @author Berachain Team
/// @notice Factory contract for creating BerachainRewardsVaults and keeping track of them.
contract BerachainZerolendRewardsVaultFactory is IBerachainRewardsVaultFactory, Ownable {
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The beacon address.
    address public immutable beacon;

    /// @notice The BGT token address.
    address public immutable bgt;

    /// @notice The distributor address.
    address public immutable distributor;

    /// @notice The Berachef address.
    address public immutable berachef;

    /// @notice Mapping of staking token to vault address.
    mapping(address stakingToken => address vault) public getVault;

    /// @notice Array of all vaults that have been created.
    address[] public allVaults;

    constructor(
        address _bgt,
        address _distributor,
        address _berachef,
        address _governance,
        address _vaultImpl
    )
        Ownable(_governance)
    {
        // slither-disable-next-line missing-zero-check
        bgt = _bgt;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        berachef = _berachef;

        beacon = address(new UpgradeableBeacon(_governance, _vaultImpl));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVaultFactory
    function createRewardsVault(address stakingToken) external returns (address) {
        if (getVault[stakingToken] != address(0)) VaultAlreadyExists.selector.revertWith();

        // Use solady library to deploy deterministic beacon proxy.
        bytes32 salt = keccak256(abi.encode(stakingToken));
        address vault = LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt);

        // Store the vault in the mapping and array.
        getVault[stakingToken] = vault;
        allVaults.push(vault);
        emit VaultCreated(stakingToken, vault);

        // Initialize the vault.
        IBerachainRewardsVault(vault).initialize(bgt, distributor, berachef, owner(), stakingToken);

        return vault;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVaultFactory
    function predictRewardsVaultAddress(address stakingToken) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(stakingToken));
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, salt, address(this));
    }

    /// @inheritdoc IBerachainRewardsVaultFactory
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }
}
