// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.24;

library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //tokens addresses
    address aTokenAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  struct UserConfigurationMap {
    uint256 data;
  }

  enum InterestRateMode {NONE, STABLE, VARIABLE}
}
