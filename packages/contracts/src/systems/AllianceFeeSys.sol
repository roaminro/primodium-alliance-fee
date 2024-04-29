// SPDX-License-Identifier: UNKOWN

/**
 * @title AllianceFeeSys
 * @dev A contract to handle alliances entrance fees.
 */
pragma solidity ^0.8.24;

// MUD imports
import { System } from "@latticexyz/world/src/System.sol";
import { ResourceId } from "@latticexyz/store/src/ResourceId.sol";
import { FunctionSelectors } from "@latticexyz/world/src/codegen/tables/FunctionSelectors.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";
import { WorldResourceIdLib } from "@latticexyz/world/src/WorldResourceId.sol";

// primodium imports
import { PlayerAlliance, PlayerAllianceData } from "primodium/index.sol";
import { EAllianceRole } from "primodium/common.sol";
import { IWorld as IPrimodiumWorld } from "primodium/world/IWorld.sol";

// extension imports
import { EXTENSION_NAMESPACE } from "../Constants.sol";
import { LibHelpers } from "../libraries/LibHelpers.sol";
import { AllianceFee, AllianceFeeData, AllianceCollectedFee } from "codegen/index.sol";
import { IWorld } from "codegen/world/IWorld.sol";

/**
 * @dev A contract to handle alliances entrance fees.
 * @notice Alliance owner must delegate invite creation to this contract
 */
contract AllianceFeeSys is System {
  /**
   * @dev ERRORS
   */
  error NoPlayerAllianceFound();
  error PlayerNotAllianceOwner();
  error AllianceNotJoinable();
  error EntranceFeeNotCovered();
  error NoFeeToCollect();
  error NoAllianceOwner();

  /**
   * @dev IMMUTABLES
   */
  ResourceId immutable _extensionNamespaceResource = WorldResourceIdLib.encodeNamespace(EXTENSION_NAMESPACE);

  /**
   * @dev METHODS
   */

  /// @dev set entrance fee of an alliance (player must have owner role for the alliance)
  /// @param entranceFee entrance fee in WEI
  /// @notice setting an entranceFee to 0 effectively disable joining alliances via entrance fee
  /// @notice TODO: see how to allow for using Primodium resources as entrance fee
  function setAllianceFee(uint256 entranceFee) public {
    // StoreSwitch.setStoreAddress(_world());
    // get player entity
    bytes32 playerEntity = LibHelpers.addressToEntity(_msgSender());

    // get player alliance
    PlayerAllianceData memory playerAllianceData = PlayerAlliance.get(playerEntity);

    if (playerAllianceData.alliance == 0) {
      revert NoPlayerAllianceFound();
    }

    // check that the player has alliance owner role
    if (playerAllianceData.role != uint8(EAllianceRole.Owner)) {
      revert PlayerNotAllianceOwner();
    }

    // save new entrance fee
    AllianceFee.set(playerAllianceData.alliance, _msgSender(), entranceFee);
  }

  /// @dev join an alliance by paying an entrance fee
  /// @param allianceEntity alliance entity id
  /// @notice an alliance can only be joined this way if entranceFee is greater than zero (0)
  /// @notice to avoid generating a delegation, the player will still have to manually join the alliance after receiving the invite
  function joinAlliance(bytes32 allianceEntity) public payable {
    // StoreSwitch.setStoreAddress(_world());
    // check if alliance is setup and joinable via this system
    AllianceFeeData memory allianceFeeData = AllianceFee.get(allianceEntity);

    if (allianceFeeData.entranceFee == 0) {
      revert AllianceNotJoinable();
    }

    if (_msgValue() < allianceFeeData.entranceFee) {
      revert EntranceFeeNotCovered();
    }

    IPrimodiumWorld primodiumWorld = IPrimodiumWorld(_world());
    // find the alliance invite function selector
    bytes4 allianceInviteSelector = primodiumWorld.Primodium__invite.selector;

    // look up that function selector in the MUD FunctionSelectors table, and get the actual function selector.
    // eventually, these should match, but currently that is not the case.
    (ResourceId allianceSystemId, bytes4 allianceSystemInviteFunctionSelector) = FunctionSelectors.get(
      allianceInviteSelector
    );

    // now we can call the invite function in the AllianceSystem
    // @notice: this call will revert if this contract does not have a valid delegation anymore
    primodiumWorld.callFrom(
      allianceFeeData.allianceOwner,
      allianceSystemId,
      abi.encodeWithSelector(allianceSystemInviteFunctionSelector, _msgSender())
    );

    /// @notice to allow for calling the alliance join function you would need to have a delegation from the _msgSender()

    // now that the player has been invited, proceed with joining the alliance

    // find the alliance join function selector
    // bytes4 allianceJoinSelector = primodiumWorld.Primodium__join.selector;

    // look up that function selector in the MUD FunctionSelectors table, and get the actual function selector.
    // eventually, these should match, but currently that is not the case.
    // (, bytes4 allianceSystemJoinFunctionSelector) = FunctionSelectors.get(allianceJoinSelector);

    // now we can call the join function in the AllianceSystem
    // @notice: this call will revert if this contract does not have a valid delegation anymore
    // primodiumWorld.callFrom(
    //   _msgSender(),
    //   allianceSystemId,
    //   abi.encodeWithSelector(allianceSystemJoinFunctionSelector, allianceEntity)
    // );

    // update collected fee
    uint256 collectedEntranceFee = AllianceCollectedFee.get(allianceEntity);
    collectedEntranceFee += _msgValue();
    AllianceCollectedFee.set(allianceEntity, collectedEntranceFee);
  }

  /// @dev collect all the collected entrance fee for an alliance
  /// @param allianceEntity alliance entity id
  /// @notice this can be called by anybody as the fee will be sent to the alliance owner
  /// @notice an alliance can have several owners, but the collected fee will be sent to the last owner that setup the entrance fee
  function collectAllianceEntranceFee(bytes32 allianceEntity) public payable {
    // check that there is a fee to collect and that there is a valid alliance owner address
    uint256 collectedEntranceFee = AllianceCollectedFee.get(allianceEntity);

    if (collectedEntranceFee == 0) {
      revert NoFeeToCollect();
    }

    address allianceOwner = AllianceFee.getAllianceOwner(allianceEntity);

    if (allianceOwner == address(0)) {
      revert NoAllianceOwner();
    }

    // transfer fee to alliance owner
    IWorld(_world()).transferBalanceToAddress(_extensionNamespaceResource, allianceOwner, collectedEntranceFee);

    // reset collected fee
    AllianceCollectedFee.set(allianceEntity, 0);
  }
}
