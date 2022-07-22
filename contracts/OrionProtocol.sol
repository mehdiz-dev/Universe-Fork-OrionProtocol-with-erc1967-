// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./helpers/OwnerRecovery.sol";
import "../implementations/output/LiquidityPoolManagerImplementationPointer.sol";
import "../implementations/output/WalletObserverImplementationPointer.sol";

contract OrionProtocol is
    ERC20,
    ERC20Burnable,
    Ownable,
    OwnerRecovery,
    LiquidityPoolManagerImplementationPointer,
    WalletObserverImplementationPointer
{
    address public immutable orionsManager;

    modifier onlyOrionsManager() {
        address sender = _msgSender();
        require(
            sender == address(orionsManager),
            "Implementations: Not OrionsManager"
        );
        _;
    }

    constructor(address _orionsManager) ERC20("OrionProtocol", "ORN") {
        require(
            _orionsManager != address(0),
            "Implementations: OrionsManager is not set"
        );
        orionsManager = _orionsManager;
        _mint(owner(), 42_000_000_000 * (10**18));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (address(walletObserver) != address(0)) {
            walletObserver.beforeTokenTransfer(_msgSender(), from, to, amount);
        }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        if (address(liquidityPoolManager) != address(0)) {
            liquidityPoolManager.afterTokenTransfer(_msgSender());
        }
    }

    function accountBurn(address account, uint256 amount)
        external
        onlyOrionsManager
    {
        // Note: _burn will call _beforeTokenTransfer which will ensure no denied addresses can create cargos
        // effectively protecting OrionsManager from suspicious addresses
        super._burn(account, amount);
    }

    function accountReward(address account, uint256 amount)
        external
        onlyOrionsManager
    {
        require(
            address(liquidityPoolManager) != account,
            "OrionProtocol: Use liquidityReward to reward liquidity"
        );
        super._mint(account, amount);
    }

    function liquidityReward(uint256 amount) external onlyOrionsManager {
        require(
            address(liquidityPoolManager) != address(0),
            "OrionProtocol: LiquidityPoolManager is not set"
        );
        super._mint(address(liquidityPoolManager), amount);
    }
}