//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import { AggregatorV3Interface } from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";
import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
/**
 * @title DSCEngine
 * @author siddu
 *
 * @notice
 * have the tokens maintain a 1 token= 1 peg$
 * algorthmic minting and burning
 * backed by WETH and WBTC
 */

contract DSCEngine is ReentrancyGuard {
    //ERRORS//
    error amountMustBeMoreThanZero();
    error DSCEngine__TokenAndPriceFeedLengthMismatch();
    error DSCEngine__TokenNotSupported(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

        using OracleLib for AggregatorV3Interface;

    //STATE VARIABLES//

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECESION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECSION = 1e10;
    uint256 private constant FEED_PRECESION = 1e8;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;



    //EVENTS//
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event COllateralRedeemed(address indexed redeemFrom,address indexed redeemTo, address token, uint256 amount);

    //MODIFIERS//
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert amountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported(token);
        }
        _;
    }

    //FUNCTIONS//

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedLengthMismatch();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);

        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function  depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external 
     moreThanZero(amountCollateral)
     isAllowedToken(tokenCollateralAddress){
        _burnDsc(amountDscToBurn,msg.sender,msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender,msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);

     }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external 
    moreThanZero(amountCollateral)
    nonReentrant
    isAllowedToken(tokenCollateralAddress){
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender,msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);

    }
    

    function mintDsc(uint256 amountDiscToMint) public moreThanZero(amountDiscToMint) {
     s_DSCMinted[msg.sender] += amountDiscToMint;
         revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDiscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external 
    moreThanZero(debtToCover)
    nonReentrant{
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor>=MIN_HEALTH_FACTOR){
            revert DSCEngine_HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(user);
    }

    function healthFactor() external view {}

    //Internal//
     
     function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address redeemFrom,
        address redeemTo
     ) private{
            s_collateralDeposited[redeemFrom][tokenCollateralAddress] -= amountCollateral;
            emit COllateralRedeemed(redeemFrom,redeemTo,tokenCollateralAddress,amountCollateral);
            bool success = IERC20(tokenCollateralAddress).transfer(redeemTo, amountCollateral);
            if (!success) {
                revert DSCEngine__TransferFailed();
            }
     }

     function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private{
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
     }







    function _healthFactor(address user) private  view  returns(uint256){

        (uint256 totalDiscMinted, uint256 collateralValueInUsd)= _getAccountInformation(user);
        return _calculateHealthFactor(totalDiscMinted, collateralValueInUsd);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }


    function _getUsdValue(address token, uint256 amount) private view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return((uint256(price)*ADDITIONAL_FEED_PRECSION)*amount)/PRECESION;
    }

    function _calculateHealthFactor(
        uint256 totalDiscMinted,
        uint256 collateralValueInUsd
    )
    internal
    pure
    returns(uint256){
     if(totalDiscMinted == 0) return type(uint256).max;
     uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
     return(collateralAdjustedForThreshold * PRECESION) / totalDiscMinted;
    }

    function revertIfHealthFactorIsBroken(address user) private view  {
        uint256 healthFactorValue = _healthFactor(user);
        if (healthFactorValue < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(healthFactorValue);
        }
    }

    //public&external//


    function calcualteHealthFactor(
        uint256 totalDiscMinted,
        uint256 collateralValueInUsd
    )
    external
    pure
    returns(uint256){
        return _calculateHealthFactor(totalDiscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
    external
    view 
    returns(uint256 totalDiscMinted, uint256 collateralValueInUsd){
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount //WETH or WBTC
    )
    external
    view
    returns(uint256){
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd){
        for(uint256 index =0; index<s_collateralTokens.length; index++){
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return((usdAmountInWei * PRECESION) / uint256(price)) / ADDITIONAL_FEED_PRECSION;
    }

    function getPrecision() external pure returns(uint256){
        return PRECESION;
    }

    function getAdditionalFeedPrecision() external pure returns(uint256){
        return ADDITIONAL_FEED_PRECSION;
    }

    function getLiquidationThreshold() external pure returns(uint256){
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns(uint256){
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns(uint256){
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns(uint256){
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }

    function getDsc() external view returns(address){
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];
    }
    function getHealthFactor(address user) external view returns(uint256){
        return _healthFactor(user);
    }

}
