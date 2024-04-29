// SPDX-License-Identifier: UNKOWN
pragma solidity ^0.8.24;

// MUD imports
import { MudTest } from "@latticexyz/world/test/MudTest.t.sol";
import { console2 } from "forge-std/Test.sol";

import { WorldRegistrationSystem } from "@latticexyz/world/src/modules/init/implementations/WorldRegistrationSystem.sol";
import { System } from "@latticexyz/world/src/System.sol";

import { ResourceId } from "@latticexyz/store/src/ResourceId.sol";
import { WorldResourceIdLib } from "@latticexyz/world/src/WorldResourceId.sol";
import { RESOURCE_SYSTEM } from "@latticexyz/world/src/worldResourceTypes.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";
import { UNLIMITED_DELEGATION } from "@latticexyz/world/src/constants.sol";

// primodium imports
import { IWorld as IPrimodiumWorld } from "primodium/world/IWorld.sol";
import { Home, PositionData, Spawned } from "primodium/index.sol";
import { EAllianceInviteMode } from "primodium/common.sol";

// extension imports
import { AllianceFeeSys } from "../src/systems/AllianceFeeSys.sol";
import { LibHelpers } from "../src/libraries/LibHelpers.sol";
import { PRIMODIUM_NAMESPACE, EXTENSION_NAMESPACE, ALLIANCE_FEE_SYS } from "../src/Constants.sol";
import { AllianceFee, AllianceFeeData } from "codegen/index.sol";
import { IWorld as IExtensionWorld } from "codegen/world/IWorld.sol";

contract AllianceFeeSysTest is MudTest {
  // the environment variables are pulled from your .env
  address extensionDeployerAddress = vm.envAddress("ADDRESS_ALICE");

  address playerAddressBob = vm.envAddress("ADDRESS_BOB");
  uint256 playerPrivateKeyBob = vm.envUint("PRIVATE_KEY_BOB");

  address playerAddressMallory = vm.envAddress("ADDRESS_MALLORY");
  uint256 playerPrivateKeyMallory = vm.envUint("PRIVATE_KEY_MALLORY");

  IPrimodiumWorld primodiumWorld;
  IExtensionWorld extensionWorld;

  bytes32 bobAllianceEntity;

  // defining these up top for use below.
  // namespaces are truncated to 14 bytes, and systems to 16 bytes.
  // namespaces must be unique, so if you get an Already Exists revert, try changing the namespace.
  // systems are also unique within a namespace, but redeploying a system will overwrite the previous version.

  // override MudTest setUp
  // the setUp function is run before each test function that follows
  function setUp() public override {
    // import MUD specific test setup
    super.setUp();

    // configure the target world
    worldAddress = vm.envAddress("WORLD_ADDRESS");
    // StoreSwitch.setStoreAddress(worldAddress);
    primodiumWorld = IPrimodiumWorld(worldAddress);
    extensionWorld = IExtensionWorld(worldAddress);

    // this test forks the live world state, and runs it on a local anvil instance
    // changes made in this test will not affect the live world state
    vm.createSelectFork(vm.envString("PRIMODIUM_RPC_URL"), vm.envUint("BLOCK_NUMBER"));
    console2.log("\nForkLivePrimodium is running.");

    // cache an instance of the WorldRegistrationSystem for the world
    WorldRegistrationSystem world = WorldRegistrationSystem(worldAddress);

    // derive the namespaceResource and systemResource from the namespace and system
    // specifics can be found at https://mud.dev/guides/extending-a-world
    // in the Deploy to the Blockchain Explanation spoiler
    ResourceId namespaceResource = WorldResourceIdLib.encodeNamespace(EXTENSION_NAMESPACE);
    ResourceId systemResource = WorldResourceIdLib.encode(RESOURCE_SYSTEM, EXTENSION_NAMESPACE, ALLIANCE_FEE_SYS);
    console2.log("World Address: ", worldAddress);
    console2.log("Namespace ID:   %x", uint256(ResourceId.unwrap(namespaceResource)));
    console2.log("System ID:      %x", uint256(ResourceId.unwrap(systemResource)));

    // interacting with the chain requires us to pretend to be someone
    // here, we are pretending to be the extension deployer
    vm.startPrank(extensionDeployerAddress);

    // register the namespace
    world.registerNamespace(namespaceResource);

    AllianceFeeSys allianceFeeSys = new AllianceFeeSys();
    console2.log("AllianceFeeSys address: ", address(allianceFeeSys));

    // register the system
    world.registerSystem(systemResource, allianceFeeSys, true);

    // register all functions in the system
    // if you have multiple functions, you will need ro register each one
    world.registerFunctionSelector(systemResource, "setAllianceFee(uint256)");
    world.registerFunctionSelector(systemResource, "joinAlliance(bytes32)");
    world.registerFunctionSelector(systemResource, "collectAllianceEntranceFee(bytes32)");
    console2.log(
      "Successfully registered the extension's namespace, contract and function selectors to the Primodium world address."
    );

    // stop being the system deployer
    vm.stopPrank();

    vm.startBroadcast(playerPrivateKeyBob);

    world.registerDelegation(address(allianceFeeSys), UNLIMITED_DELEGATION, new bytes(0));
    console2.log("Bob successfully delegated to extension's system for unlimited delegation.");

    // // stop being the active player
    vm.stopBroadcast();

    spawnPlayers();
    createBobAlliance();
  }

  function spawnPlayers() internal {
    vm.startBroadcast(playerPrivateKeyBob);

    // attempting to spawn the player if they have not started the game yet
    bytes32 playerEntity = LibHelpers.addressToEntity(playerAddressBob);
    bool playerIsSpawned = Spawned.get(playerEntity);
    if (!playerIsSpawned) {
      console2.log("Spawning Bob");
      primodiumWorld.Primodium__spawn();
    }

    vm.stopBroadcast();

    vm.startBroadcast(playerPrivateKeyMallory);

    // attempting to spawn the player if they have not started the game yet
    playerEntity = LibHelpers.addressToEntity(playerAddressMallory);
    playerIsSpawned = Spawned.get(playerEntity);
    if (!playerIsSpawned) {
      console2.log("Spawning Mallory");
      primodiumWorld.Primodium__spawn();
    }

    vm.stopBroadcast();
  }

  function createBobAlliance() internal {
    vm.startBroadcast(playerPrivateKeyBob);

    bobAllianceEntity = primodiumWorld.Primodium__create("Bob Alliance", EAllianceInviteMode.Closed);
    console2.log("Bob Alliance entity: %x", uint256(bobAllianceEntity));

    vm.stopBroadcast();
  }

  function test_setEntranceFee() public {
    console2.log("\ntest_setEntranceFee");

    vm.startBroadcast(playerPrivateKeyBob);

    // set entrance fee to 1 Ether
    extensionWorld.AllianceFee__setAllianceFee(1 ether);

    AllianceFeeData memory allianceFeeData = AllianceFee.get(bobAllianceEntity);

    assertEq(allianceFeeData.entranceFee, 1 ether);
    assertEq(allianceFeeData.allianceOwner, playerAddressBob);

    vm.stopBroadcast();
  }

  function test_joinAlliance() public {
    console2.log("\ntest_joinAlliance");

    vm.startBroadcast(playerPrivateKeyBob);

    // set entrance fee to 0 Ether
    extensionWorld.AllianceFee__setAllianceFee(0 ether);

    vm.stopBroadcast();

    vm.startBroadcast(playerAddressMallory);

    // trying to join alliance directly should fail
    vm.expectRevert("[Alliance] Either alliance is not open or player has not been invited");
    primodiumWorld.Primodium__join(bobAllianceEntity);

    // should not be able to join the alliance without paying the entrance fee
    vm.expectRevert(AllianceFeeSys.AllianceNotJoinable.selector);
    extensionWorld.AllianceFee__joinAlliance(bobAllianceEntity);

    vm.stopBroadcast();

    vm.startBroadcast(playerPrivateKeyBob);

    // set entrance fee to 1 Ether
    extensionWorld.AllianceFee__setAllianceFee(1 ether);

    vm.stopBroadcast();

    vm.startBroadcast(playerAddressMallory);

    // should not be able to join the alliance without paying the entrance fee
    vm.expectRevert(AllianceFeeSys.EntranceFeeNotCovered.selector);
    extensionWorld.AllianceFee__joinAlliance(bobAllianceEntity);

    // should  be able to join the alliance by paying the entrance fee
    vm.deal(playerAddressMallory, 1 ether);

    extensionWorld.AllianceFee__joinAlliance{ value: 1 ether }(bobAllianceEntity);
    primodiumWorld.Primodium__join(bobAllianceEntity);

    assertEq(playerAddressMallory.balance, 0);

    vm.stopBroadcast();
  }

  function test_collectAllianceEntranceFee() public {
    console2.log("\ntest_collectAllianceEntranceFee");

    vm.startBroadcast(playerPrivateKeyBob);

    // set entrance fee to 1 Ether
    extensionWorld.AllianceFee__setAllianceFee(1 ether);

    vm.stopBroadcast();

    uint256 balance = playerAddressBob.balance;
    assertEq(balance, 0);

    vm.startBroadcast(playerPrivateKeyMallory);
    vm.deal(playerAddressMallory, 1 ether);

    // join alliance
    extensionWorld.AllianceFee__joinAlliance{ value: 1 ether }(bobAllianceEntity);
    primodiumWorld.Primodium__join(bobAllianceEntity);

    // use any player to collect the fee
    extensionWorld.AllianceFee__collectAllianceEntranceFee(bobAllianceEntity);

    vm.stopBroadcast();

    balance = playerAddressBob.balance;
    assertEq(balance, 1 ether);
  }
}
