// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IUSDG.sol";
import "./YieldToken.sol";

contract USDG is YieldToken, IUSDG {

    mapping (address => bool) public vaults;

    modifier onlyVault() {
        require(vaults[msg.sender], "USDG: forbidden");
        _;
    }

    //构造设置资金池管理员
    constructor(address _vault) public YieldToken("USD Gambit", "USDG", 0) {
        vaults[_vault] = true;
    }

    //gov添加资金池管理员
    function addVault(address _vault) external override onlyGov {
        vaults[_vault] = true;
    }

    //gov删除资金池管理员
    function removeVault(address _vault) external override onlyGov {
        vaults[_vault] = false;
    }

    //资金池管理员mint
    function mint(address _account, uint256 _amount) external override onlyVault {
        _mint(_account, _amount);
    }

    //资金池管理员burn
    function burn(address _account, uint256 _amount) external override onlyVault {
        _burn(_account, _amount);
    }
}
