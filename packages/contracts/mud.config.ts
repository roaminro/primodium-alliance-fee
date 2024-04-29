import { defineWorld } from "@latticexyz/world";

export default defineWorld({
  namespace: "AllianceFee",
  systems: {
    AllianceFeeSys: {
      openAccess: true,
      name: "AllianceFeeSys",
    },
  },
  tables: {
    AllianceFee: {
      key: ["allianceEntity"],
      schema: {
        // alliance entity id
        allianceEntity: "bytes32",
        // an alliance owner address
        allianceOwner: "address",
        // entrance fee in WEI
        entranceFee: "uint256",
      },
    },
    AllianceCollectedFee: {
      key: ["allianceEntity"],
      schema: {
        // alliance entity id
        allianceEntity: "bytes32",
        // collected entrance fee in WEI
        collectedEntranceFee: "uint256",
      },
    },
  },
});
