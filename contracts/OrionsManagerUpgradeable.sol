// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./helpers/OwnerRecoveryUpgradeable.sol";
import "../implementations/output/OrionProtocolImplementationPointerUpgradeable.sol";
import "../implementations/output/LiquidityPoolManagerImplementationPointerUpgradeable.sol";

contract OrionsManagerUpgradeable is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    OwnerRecoveryUpgradeable,
    ReentrancyGuardUpgradeable,
    OrionProtocolImplementationPointerUpgradeable,
    LiquidityPoolManagerImplementationPointerUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct OrionInfoEntity {
        OrionEntity orion;
        uint256 id;
        uint256 pendingRewards;
        uint256 rewardPerDay;
        uint256 compoundDelay;
    }

    struct OrionEntity {
        uint256 id;
        string name;
        uint256 creationTime;
        uint256 lastProcessingTimestamp;
        uint256 rewardMult;
        uint256 orionValue;
        uint256 totalClaimed;
        bool exists;
    }

    struct TierStorage {
        uint256 rewardMult;
        uint256 amountLockedInTier;
        bool exists;
    }

    CountersUpgradeable.Counter private _orionCounter;
    mapping(uint256 => OrionEntity) private _orions;
    mapping(uint256 => TierStorage) private _tierTracking;
    uint256[] _tiersTracked;

    uint256 public rewardPerDay;
    uint256 public creationMinPrice;
    uint256 public compoundDelay;
    uint256 public processingFee;

    uint24[6] public tierLevel;
    uint16[6] public tierSlope;

    uint256 private constant ONE_DAY = 86400;
    uint256 public totalValueLocked;

    modifier onlyOrionOwner() {
        address sender = _msgSender();
        require(
            sender != address(0),
            "Orions: Cannot be from the zero address"
        );
        require(
            isOwnerOfOrions(sender),
            "Orions: No Orion owned by this account"
        );
        require(
            !liquidityPoolManager.isFeeReceiver(sender),
            "Orions: Fee receivers cannot own Orions"
        );
        _;
    }

    modifier checkPermissions(uint256 _orionId) {
        address sender = _msgSender();
        require(orionExists(_orionId), "Orions: This orion doesn't exist");
        require(
            isOwnerOfOrion(sender, _orionId),
            "Orions: You do not control this Orion"
        );
        _;
    }

    modifier orionProtocolSet() {
        require(
            address(orionProtocol) != address(0),
            "Orions: OrionProtocol is not set"
        );
        _;
    }

    event Compound(
        address indexed account,
        uint256 indexed orionId,
        uint256 amountToCompound
    );
    event Cashout(
        address indexed account,
        uint256 indexed orionId,
        uint256 rewardAmount
    );

    event CompoundAll(
        address indexed account,
        uint256[] indexed affectedOrions,
        uint256 amountToCompound
    );
    event CashoutAll(
        address indexed account,
        uint256[] indexed affectedOrions,
        uint256 rewardAmount
    );

    event Create(
        address indexed account,
        uint256 indexed newOrionId,
        uint256 amount
    );

    function initialize() external initializer {
        __ERC721_init("Amphi Ecosystem", "TBL");
        __Ownable_init();
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // Initialize contract
        changeRewardPerDay(46299); // 4% per day
        changeNodeMinPrice(42_000 * (10**18)); // 42,000 ORN
        changeCompoundDelay(14400); // 4h
        changeProcessingFee(28); // 28%
        changeTierSystem(
            [100000, 105000, 110000, 120000, 130000, 140000],
            [1000, 500, 100, 50, 10, 0]
        );
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
        // return Strings.strConcat(
        //     _baseTokenURI(),
        //     Strings.uint2str(tokenId)
        // );

        // ToDo: fix this
        // To fix: https://andyhartnett.medium.com/solidity-tutorial-how-to-store-nft-metadata-and-svgs-on-the-blockchain-6df44314406b
        // Base64 support for names coming: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2884/files
        //string memory tokenURI = "test";
        //_setTokenURI(newOrionId, tokenURI);

        return ERC721URIStorageUpgradeable.tokenURI(tokenId);
    }

    function createOrionWithTokens(
        string memory orionName,
        uint256 orionValue
    ) external nonReentrant whenNotPaused orionProtocolSet returns (uint256) {
        address sender = _msgSender();

        require(
            bytes(orionName).length > 1 && bytes(orionName).length < 32,
            "Orions: Incorrect name length, must be between 2 to 32"
        );
        require(
            orionValue >= creationMinPrice,
            "Orions: Orion value set below minimum"
        );
        require(
            isNameAvailable(sender, orionName),
            "Orions: Name not available"
        );
        require(
            orionProtocol.balanceOf(sender) >= creationMinPrice,
            "Orions: Balance too low for creation"
        );

        // Burn the tokens used to mint the NFT
        orionProtocol.accountBurn(sender, orionValue);

        // Send processing fee to liquidity
        (uint256 orionValueTaxed, uint256 feeAmount) = getProcessingFee(
            orionValue
        );
        orionProtocol.liquidityReward(feeAmount);

        // Increment the total number of tokens
        _orionCounter.increment();

        uint256 newOrionId = _orionCounter.current();
        uint256 currentTime = block.timestamp;

        // Add this to the TVL
        totalValueLocked += orionValueTaxed;
        logTier(tierLevel[0], int256(orionValueTaxed));

        // Add Orion
        _orions[newOrionId] = OrionEntity({
            id: newOrionId,
            name: orionName,
            creationTime: currentTime,
            lastProcessingTimestamp: currentTime,
            rewardMult: tierLevel[0],
            orionValue: orionValueTaxed,
            totalClaimed: 0,
            exists: true
        });

        // Assign the Orion to this account
        _mint(sender, newOrionId);

        emit Create(sender, newOrionId, orionValueTaxed);

        return newOrionId;
    }

    function cashoutReward(uint256 _orionId)
        external
        nonReentrant
        onlyOrionOwner
        checkPermissions(_orionId)
        whenNotPaused
        orionProtocolSet
    {
        address account = _msgSender();
        uint256 reward = _getOrionCashoutRewards(_orionId);
        _cashoutReward(reward);

        emit Cashout(account, _orionId, reward);
    }

    function cashoutAll()
        external
        nonReentrant
        onlyOrionOwner
        whenNotPaused
        orionProtocolSet
    {
        address account = _msgSender();
        uint256 rewardsTotal = 0;

        uint256[] memory orionsOwned = getOrionIdsOf(account);
        for (uint256 i = 0; i < orionsOwned.length; i++) {
            rewardsTotal += _getOrionCashoutRewards(orionsOwned[i]);
        }
        _cashoutReward(rewardsTotal);

        emit CashoutAll(account, orionsOwned, rewardsTotal);
    }

    function compoundReward(uint256 _orionId)
        external
        nonReentrant
        onlyOrionOwner
        checkPermissions(_orionId)
        whenNotPaused
        orionProtocolSet
    {
        address account = _msgSender();

        (
            uint256 amountToCompound,
            uint256 feeAmount
        ) = _getOrionCompoundRewards(_orionId);
        require(
            amountToCompound > 0,
            "Orions: You must wait until you can compound again"
        );
        if (feeAmount > 0) {
            orionProtocol.liquidityReward(feeAmount);
        }

        emit Compound(account, _orionId, amountToCompound);
    }

    function compoundAll()
        external
        nonReentrant
        onlyOrionOwner
        whenNotPaused
        orionProtocolSet
    {
        address account = _msgSender();
        uint256 feesAmount = 0;
        uint256 amountsToCompound = 0;
        uint256[] memory orionsOwned = getOrionIdsOf(account);
        uint256[] memory orionsAffected = new uint256[](orionsOwned.length);

        for (uint256 i = 0; i < orionsOwned.length; i++) {
            (
                uint256 amountToCompound,
                uint256 feeAmount
            ) = _getOrionCompoundRewards(orionsOwned[i]);
            if (amountToCompound > 0) {
                orionsAffected[i] = orionsOwned[i];
                feesAmount += feeAmount;
                amountsToCompound += amountToCompound;
            } else {
                delete orionsAffected[i];
            }
        }

        require(amountsToCompound > 0, "Orions: No rewards to compound");
        if (feesAmount > 0) {
            orionProtocol.liquidityReward(feesAmount);
        }

        emit CompoundAll(account, orionsAffected, amountsToCompound);
    }

    // Private reward functions

    function _getOrionCashoutRewards(uint256 _orionId)
        private
        returns (uint256)
    {
        OrionEntity storage orion = _orions[_orionId];

        if (!isProcessable(orion)) {
            return 0;
        }

        uint256 reward = calculateReward(orion);
        orion.totalClaimed += reward;

        if (orion.rewardMult != tierLevel[0]) {
            logTier(orion.rewardMult, -int256(orion.orionValue));
            logTier(tierLevel[0], int256(orion.orionValue));
        }

        orion.rewardMult = tierLevel[0];
        orion.lastProcessingTimestamp = block.timestamp;
        return reward;
    }

    function _getOrionCompoundRewards(uint256 _orionId)
        private
        returns (uint256, uint256)
    {
        OrionEntity storage orion = _orions[_orionId];

        if (!isProcessable(orion)) {
            return (0, 0);
        }

        uint256 reward = calculateReward(orion);
        if (reward > 0) {
            (uint256 amountToCompound, uint256 feeAmount) = getProcessingFee(
                reward
            );
            totalValueLocked += amountToCompound;

            logTier(orion.rewardMult, -int256(orion.orionValue));

            orion.lastProcessingTimestamp = block.timestamp;
            orion.orionValue += amountToCompound;
            orion.rewardMult += increaseMultiplier(orion.rewardMult);

            logTier(orion.rewardMult, int256(orion.orionValue));

            return (amountToCompound, feeAmount);
        }

        return (0, 0);
    }

    function _cashoutReward(uint256 amount) private {
        require(
            amount > 0,
            "Orions: You don't have enough reward to cash out"
        );
        address to = _msgSender();
        (uint256 amountToReward, uint256 feeAmount) = getProcessingFee(amount);
        orionProtocol.accountReward(to, amountToReward);
        // Send the fee to the contract where liquidity will be added later on
        orionProtocol.liquidityReward(feeAmount);
    }

    function logTier(uint256 mult, int256 amount) private {
        TierStorage storage tierStorage = _tierTracking[mult];
        if (tierStorage.exists) {
            require(
                tierStorage.rewardMult == mult,
                "Orions: rewardMult does not match in TierStorage"
            );
            uint256 amountLockedInTier = uint256(
                int256(tierStorage.amountLockedInTier) + amount
            );
            require(
                amountLockedInTier >= 0,
                "Orions: amountLockedInTier cannot underflow"
            );
            tierStorage.amountLockedInTier = amountLockedInTier;
        } else {
            // Tier isn't registered exist, register it
            require(
                amount > 0,
                "Orions: Fatal error while creating new TierStorage. Amount cannot be below zero."
            );
            _tierTracking[mult] = TierStorage({
                rewardMult: mult,
                amountLockedInTier: uint256(amount),
                exists: true
            });
            _tiersTracked.push(mult);
        }
    }

    // Private view functions

    function getProcessingFee(uint256 rewardAmount)
        private
        view
        returns (uint256, uint256)
    {
        uint256 feeAmount = 0;
        if (processingFee > 0) {
            feeAmount = (rewardAmount * processingFee) / 100;
        }
        return (rewardAmount - feeAmount, feeAmount);
    }

    function increaseMultiplier(uint256 prevMult)
        private
        view
        returns (uint256)
    {
        if (prevMult >= tierLevel[5]) {
            return tierSlope[5];
        } else if (prevMult >= tierLevel[4]) {
            return tierSlope[4];
        } else if (prevMult >= tierLevel[3]) {
            return tierSlope[2];
        } else if (prevMult >= tierLevel[2]) {
            return tierSlope[2];
        } else if (prevMult >= tierLevel[1]) {
            return tierSlope[1];
        } else {
            return tierSlope[0];
        }
    }

    function isProcessable(OrionEntity memory orion)
        private
        view
        returns (bool)
    {
        return
            block.timestamp >= orion.lastProcessingTimestamp + compoundDelay;
    }

    function calculateReward(OrionEntity memory orion)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                orion.orionValue,
                orion.rewardMult,
                block.timestamp - orion.lastProcessingTimestamp,
                rewardPerDay
            );
    }

    function rewardPerDayFor(OrionEntity memory orion)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                orion.orionValue,
                orion.rewardMult,
                ONE_DAY,
                rewardPerDay
            );
    }

    function _calculateRewardsFromValue(
        uint256 _orionValue,
        uint256 _rewardMult,
        uint256 _timeRewards,
        uint256 _rewardPerDay
    ) private pure returns (uint256) {
        uint256 rewards = (_timeRewards * _rewardPerDay) / 1000000;
        uint256 rewardsMultiplicated = (rewards * _rewardMult) / 100000;
        return (rewardsMultiplicated * _orionValue) / 100000;
    }

    function orionExists(uint256 _orionId) private view returns (bool) {
        require(_orionId > 0, "Orions: Id must be higher than zero");
        OrionEntity memory orion = _orions[_orionId];
        if (orion.exists) {
            return true;
        }
        return false;
    }

    // Public view functions

    function calculateTotalDailyEmission() external view returns (uint256) {
        uint256 dailyEmission = 0;
        for (uint256 i = 0; i < _tiersTracked.length; i++) {
            TierStorage memory tierStorage = _tierTracking[_tiersTracked[i]];
            dailyEmission += _calculateRewardsFromValue(
                tierStorage.amountLockedInTier,
                tierStorage.rewardMult,
                ONE_DAY,
                rewardPerDay
            );
        }
        return dailyEmission;
    }

    function isNameAvailable(address account, string memory orionName)
        public
        view
        returns (bool)
    {
        uint256[] memory orionsOwned = getOrionIdsOf(account);
        for (uint256 i = 0; i < orionsOwned.length; i++) {
            OrionEntity memory orion = _orions[orionsOwned[i]];
            if (keccak256(bytes(orion.name)) == keccak256(bytes(orionName))) {
                return false;
            }
        }
        return true;
    }

    function isOwnerOfOrions(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    function isOwnerOfOrion(address account, uint256 _orionId)
        public
        view
        returns (bool)
    {
        uint256[] memory orionIdsOf = getOrionIdsOf(account);
        for (uint256 i = 0; i < orionIdsOf.length; i++) {
            if (orionIdsOf[i] == _orionId) {
                return true;
            }
        }
        return false;
    }

    function getOrionIdsOf(address account)
        public
        view
        returns (uint256[] memory)
    {
        uint256 numberOfOrions = balanceOf(account);
        uint256[] memory orionIds = new uint256[](numberOfOrions);
        for (uint256 i = 0; i < numberOfOrions; i++) {
            uint256 orionId = tokenOfOwnerByIndex(account, i);
            require(
                orionExists(orionId),
                "Orions: This orion doesn't exist"
            );
            orionIds[i] = orionId;
        }
        return orionIds;
    }

    function getOrionsByIds(uint256[] memory _orionIds)
        external
        view
        returns (OrionInfoEntity[] memory)
    {
        OrionInfoEntity[] memory orionsInfo = new OrionInfoEntity[](
            _orionIds.length
        );
        for (uint256 i = 0; i < _orionIds.length; i++) {
            uint256 orionId = _orionIds[i];
            OrionEntity memory orion = _orions[orionId];
            orionsInfo[i] = OrionInfoEntity(
                orion,
                orionId,
                calculateReward(orion),
                rewardPerDayFor(orion),
                compoundDelay
            );
        }
        return orionsInfo;
    }

    // Owner functions

    function changeNodeMinPrice(uint256 _creationMinPrice) public onlyOwner {
        require(
            _creationMinPrice > 0,
            "Orions: Minimum price to create a Orion must be above 0"
        );
        creationMinPrice = _creationMinPrice;
    }

    function changeCompoundDelay(uint256 _compoundDelay) public onlyOwner {
        require(
            _compoundDelay > 0,
            "Orions: compoundDelay must be greater than 0"
        );
        compoundDelay = _compoundDelay;
    }

    function changeRewardPerDay(uint256 _rewardPerDay) public onlyOwner {
        require(
            _rewardPerDay > 0,
            "Orions: rewardPerDay must be greater than 0"
        );
        rewardPerDay = _rewardPerDay;
    }

    function changeTierSystem(
        uint24[6] memory _tierLevel,
        uint16[6] memory _tierSlope
    ) public onlyOwner {
        require(
            _tierLevel.length == 6,
            "Orions: newTierLevels length has to be 6"
        );
        require(
            _tierSlope.length == 6,
            "Orions: newTierSlopes length has to be 6"
        );
        tierLevel = _tierLevel;
        tierSlope = _tierSlope;
    }

    function changeProcessingFee(uint8 _processingFee) public onlyOwner {
        require(_processingFee <= 30, "Cashout fee can never exceed 30%");
        processingFee = _processingFee;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Mandatory overrides

    function _burn(uint256 tokenId)
        internal
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
    {
        ERC721Upgradeable._burn(tokenId);
        ERC721URIStorageUpgradeable._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}